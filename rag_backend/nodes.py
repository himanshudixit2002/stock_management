import json
import logging
from langchain_google_genai import ChatGoogleGenerativeAI, GoogleGenerativeAIEmbeddings
from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_core.prompts import ChatPromptTemplate
from state import GraphState
from intent_classifier import classify_intent as run_intent_classifier
from context_engine import filter_context
from actions import UpdateStock, CreatePurchaseOrder, CreateSalesOrder, NavigateToScreen, GenerateReport, SearchProducts

logger = logging.getLogger(__name__)

# Singleton initialization
llm_lite = ChatGoogleGenerativeAI(model="gemini-2.0-flash-lite", temperature=0)
llm_pro = ChatGoogleGenerativeAI(model="gemini-2.5-flash", temperature=0)
llm_grader = ChatGoogleGenerativeAI(model="gemini-2.0-flash-lite", temperature=0)

embeddings = GoogleGenerativeAIEmbeddings(model="models/gemini-embedding-2")

# Lazy initialization variables for Chroma
vectorstore = None
retriever = None

def get_retriever():
    global vectorstore, retriever
    if retriever is None:
        try:
            vectorstore = Chroma(collection_name="stock_inventory", embedding_function=embeddings, persist_directory="./chroma_db")
            retriever = vectorstore.as_retriever(search_kwargs={"k": 3})
        except Exception as e:
            logger.error(f"Failed to initialize ChromaDB: {e}")
            raise e
    return retriever

tools = [UpdateStock, CreatePurchaseOrder, CreateSalesOrder, NavigateToScreen, GenerateReport, SearchProducts]
llm_lite_with_tools = llm_lite.bind_tools(tools)

pro_prompt = ChatPromptTemplate.from_messages([
    ("system", "You are Nova, the intelligent inventory assistant for SmartShelfKart.\n\n"
               "CRITICAL RULES:\n"
               "1. BE EXTREMELY CONCISE. No introductory/concluding fluff.\n"
               "2. Use short bullet points and bold text for metrics.\n"
               "3. You do NOT have tools bound here. Base answers solely on context.\n"),
    ("user", "Chat History: {chat_history}\nContext: {context}\nQuestion: {question}\nAssistant:")
])

def classify_intent(state: GraphState):
    logger.info(f"Classifying intent for question: {state['question']}")
    intent = run_intent_classifier(state["question"], state.get("chat_history", []))
    logger.info(f"Classified intent: {intent}")
    return {"intent": intent, "max_retries": state.get("max_retries", 2)}

def smart_retrieve(state: GraphState):
    intent = state["intent"]
    question = state["question"]
        
    provided_context = state.get("provided_context", "")
    if provided_context:
        filtered = filter_context(intent, question, provided_context)
        return {"documents": [Document(page_content=filtered)] if filtered else []}
    
    try:
        r = get_retriever()
        documents = r.invoke(question)
    except Exception as e:
        logger.error(f"Retrieval error: {e}")
        documents = []
        
    return {"documents": documents}

def generate(state: GraphState):
    intent = state["intent"]
    question = state["question"]
    documents = state.get("documents", [])
    chat_history = state.get("chat_history", [])
    
    if intent == "GREETING":
        return {"generation": "Hi! I'm Nova, your Inventory AI. How can I help you today?"}
    
    if intent == "NAVIGATION":
        return {"generation": "Navigating..."}
        
    docs_text = "\n\n".join(doc.page_content for doc in documents) if documents else "No relevant inventory data found."
    
    try:
        if intent in ["STOCK_UPDATE", "ORDER_MGMT"]:
            msg_history = chat_history.copy()
            msg_history.append({"role": "user", "content": f"Context: {docs_text}\nQuestion: {question}"})
            response = llm_lite_with_tools.invoke(msg_history)
        else:
            chain = pro_prompt | (llm_lite if intent in ["STOCK_QUERY", "GENERAL"] else llm_pro)
            response = chain.invoke({"context": docs_text, "question": question, "chat_history": str(chat_history)})
            
    except Exception as e:
        logger.error(f"Generation error: {e}")
        return {"generation": "I'm having trouble processing your request right now."}
        
    # Tool call formatting
    action_payload = None
    if hasattr(response, "tool_calls") and response.tool_calls:
        tool_call = response.tool_calls[0]
        name = tool_call["name"]
        args = tool_call["args"]
        
        type_mapping = {
            "UpdateStock": "update_stock",
            "CreatePurchaseOrder": "create_purchase_order",
            "CreateSalesOrder": "create_sales_order",
            "NavigateToScreen": "navigate",
            "GenerateReport": "generate_report",
            "SearchProducts": "search_products"
        }
        
        action_payload = args
        action_payload["type"] = type_mapping.get(name, name)
        
        action_json = json.dumps(action_payload)
        generation = f"Action prepared.\n\n[ACTION: {action_json}]"
        return {"generation": generation, "action_payload": action_payload}
        
    generation = response.content
    if isinstance(generation, list):
        generation = "".join(b["text"] if isinstance(b, dict) and "text" in b else str(b) for b in generation)
    elif not isinstance(generation, str):
        generation = str(generation)
        
    return {"generation": generation}

def grade_documents(state: GraphState):
    docs_text = "\n\n".join(doc.page_content for doc in state.get("documents", []))
    if not docs_text:
        return {"doc_grade": "irrelevant"}
        
    prompt = ChatPromptTemplate.from_messages([
        ("system", "Is this context relevant to answering the question? Answer 'yes' or 'no' only."),
        ("user", "Context: {context}\nQuestion: {question}")
    ])
    try:
        res = (prompt | llm_grader).invoke({"context": docs_text, "question": state["question"]})
        grade = "relevant" if "yes" in res.content.lower() else "irrelevant"
    except:
        grade = "relevant"
        
    return {"doc_grade": grade}

def grade_hallucination(state: GraphState):
    if state.get("action_payload"):
        return {"hallucination_grade": "grounded"}
        
    docs_text = "\n\n".join(doc.page_content for doc in state.get("documents", []))
    prompt = ChatPromptTemplate.from_messages([
        ("system", "Is this answer fully grounded in the provided context? Answer 'yes' or 'no' only."),
        ("user", "Context: {context}\nAnswer: {answer}")
    ])
    try:
        res = (prompt | llm_grader).invoke({"context": docs_text, "answer": state["generation"]})
        grade = "grounded" if "yes" in res.content.lower() else "hallucinated"
    except:
        grade = "grounded"
        
    return {"hallucination_grade": grade}

def format_response(state: GraphState):
    generation = state.get("generation", "")
    if state.get("retries", 0) > 0:
        logger.info(f"Response formatted after {state['retries']} retries.")
    return {"generation": generation}

def retries_incrementer_retrieve(state: GraphState):
    return {"retries": state.get("retries", 0) + 1}

def retries_incrementer_generate(state: GraphState):
    return {"retries": state.get("retries", 0) + 1}
