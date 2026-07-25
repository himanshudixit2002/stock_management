import os
from langchain_chroma import Chroma
from langchain_core.documents import Document
from dotenv import load_dotenv

load_dotenv()

def get_embeddings_instance():
    gemini_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if gemini_key:
        from langchain_google_genai import GoogleGenerativeAIEmbeddings
        return GoogleGenerativeAIEmbeddings(model="models/gemini-embedding-2", google_api_key=gemini_key)
    else:
        try:
            from langchain_community.embeddings import FakeEmbeddings
            return FakeEmbeddings(size=768)
        except Exception:
            return None

def ingest_data():
    embeddings = get_embeddings_instance()
    if not embeddings:
        print("ERROR: No valid embedding configuration found. Ingestion skipped.")
        return

    print("Initializing Embeddings and VectorStore...")
    vectorstore = Chroma(
        collection_name="stock_inventory",
        embedding_function=embeddings,
        persist_directory="./chroma_db"
    )

    print("Loading mock inventory documents...")
    documents = [
        Document(
            page_content="SKU: APP-01 (Apples). Current Stock: 15 units. Reorder Point (Min Threshold): 50 units. Supplier Lead Time: 3 days. Weekly Sales Velocity: 40 units.",
            metadata={"category": "Produce", "sku": "APP-01"}
        ),
        Document(
            page_content="SKU: TECH-L01 (Laptops). Current Stock: 100 units. Reorder Point: 20 units. Supplier Lead Time: 14 days. Weekly Sales Velocity: 10 units.",
            metadata={"category": "Electronics", "sku": "TECH-L01"}
        ),
        Document(
            page_content="SKU: BEV-W01 (Bottled Water). Current Stock: 200 units. Reorder Point: 100 units. Supplier Lead Time: 1 day. Weekly Sales Velocity: 150 units.",
            metadata={"category": "Beverages", "sku": "BEV-W01"}
        )
    ]
    
    vectorstore.add_documents(documents)
    print(f"Successfully ingested {len(documents)} documents into ChromaDB!")

def ingest_custom_products(products_list, company_id: str = "default"):
    """
    Ingests a list of custom product dicts into ChromaDB vectorstore.
    Each item in products_list should be a dict with keys:
    'name', 'barcode', 'stock', 'min_threshold', 'category', 'cost_price', 'selling_price', 'sales_velocity', 'lead_time_days'
    """
    embeddings = get_embeddings_instance()
    if not embeddings:
        print("ERROR: No valid embedding configuration found. Custom product ingestion skipped.")
        return

    vectorstore = Chroma(
        collection_name="stock_inventory",
        embedding_function=embeddings,
        persist_directory="./chroma_db"
    )

    documents = []
    cid = (company_id or "default").strip()
    for item in products_list:
        content = (
            f"Product: {item.get('name', 'Unknown')}. Barcode: {item.get('barcode', 'N/A')}. "
            f"Current Stock: {item.get('stock', 0)} units. Reorder Point (Min Threshold): {item.get('min_threshold', 10)} units. "
            f"Category: {item.get('category', 'General')}. Cost Price: {item.get('cost_price', 0)}. Selling Price: {item.get('selling_price', 0)}. "
            f"Weekly Sales Velocity: {item.get('sales_velocity', 0)} units. Supplier Lead Time: {item.get('lead_time_days', 3)} days."
        )
        doc = Document(
            page_content=content,
            metadata={"category": item.get('category', 'General'), "barcode": item.get('barcode', ''), "company_id": cid}
        )
        documents.append(doc)

    if documents:
        vectorstore.add_documents(documents)
        print(f"Successfully ingested {len(documents)} custom product documents for company '{cid}' into ChromaDB!")


if __name__ == "__main__":
    ingest_data()
