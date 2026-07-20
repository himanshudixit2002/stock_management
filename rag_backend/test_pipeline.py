from dotenv import load_dotenv
load_dotenv()

from graph import rag_pipeline

print("Running pipeline with dynamic context...")
inputs = {
    "question": "Which item has the lowest stock?", 
    "retries": 0,
    "provided_context": "SKU: 1, Name: Magic Wand, Stock: 2, Min: 5\nSKU: 2, Name: Invisibility Cloak, Stock: 10, Min: 2"
}
try:
    final_state = rag_pipeline.invoke(inputs)
    print("Generation:", final_state.get("generation"))
    print("Retries:", final_state.get("retries"))
except Exception as e:
    import traceback
    traceback.print_exc()
