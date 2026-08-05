import asyncio
from graph import rag_pipeline

async def test():
    inputs = {
        "question": "what is my stockout risk?",
        "company_id": "test_company"
    }
    state = rag_pipeline.invoke(inputs)
    print("Intent:", state.get("intent"))
    print("Generation:", state.get("generation"))
    
if __name__ == "__main__":
    asyncio.run(test())
