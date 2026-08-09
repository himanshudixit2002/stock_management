import os
from langchain_chroma import Chroma
from langchain_core.documents import Document
from dotenv import load_dotenv

load_dotenv()

import re, hashlib, math
from typing import List

class LocalDenseEmbeddings:
    """Fast, deterministic local 384-dim dense embedding model (zero Gemini / external network dependencies)."""
    def embed_documents(self, texts: List[str]) -> List[List[float]]:
        return [self._embed(t) for t in texts]

    def embed_query(self, text: str) -> List[float]:
        return self._embed(text)

    def _embed(self, text: str) -> List[float]:
        words = re.sub(r'[^\w\s]', '', text.lower()).split()
        dim = 384
        vec = [0.0] * dim
        for w in words:
            h = int(hashlib.md5(w.encode('utf-8')).hexdigest(), 16)
            idx = h % dim
            val = (h % 100) / 100.0 - 0.5
            vec[idx] += val
        norm = math.sqrt(sum(v*v for v in vec)) or 1.0
        return [v / norm for v in vec]

def get_embeddings_instance():
    gemini_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if gemini_key:
        try:
            from langchain_google_genai import GoogleGenerativeAIEmbeddings
            return GoogleGenerativeAIEmbeddings(model="models/text-embedding-004", google_api_key=gemini_key)
        except Exception as e:
            print(f"Ingest Gemini embedding init warning: {e}")
    return LocalDenseEmbeddings()


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
