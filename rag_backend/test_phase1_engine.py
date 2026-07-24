import time
import os
import sys

# Ensure backend path is in sys.path
sys.path.insert(0, os.path.dirname(__file__))

from semantic_cache import SemanticCacheManager
from cache_manager import CacheManager
from inventory_db import db_instance

def test_semantic_cache_basic():
    print("--- 1. Testing Vector Semantic Cache Basic Set & Get ---")
    cache = SemanticCacheManager(ttl_seconds=300, similarity_threshold=0.80)
    
    query1 = "What products are low on stock?"
    data1 = {"generation": "Wireless Mouse (BC: 123) is below threshold.", "intent": "ANALYTICS"}
    
    cache.set(query1, data1)
    
    # Exact match check
    start = time.time()
    res1 = cache.get(query1)
    duration_exact = (time.time() - start) * 1000
    assert res1 is not None, "Exact match failed"
    assert res1["generation"] == data1["generation"]
    print(f"✅ Exact match returned in {duration_exact:.2f}ms")

def test_semantic_cache_paraphrase():
    print("--- 2. Testing Paraphrased Query Matching ---")
    cache = SemanticCacheManager(ttl_seconds=300, similarity_threshold=0.75)
    
    original_q = "List all items running out of stock"
    cached_payload = {"generation": "Item A and Item B are low stock", "intent": "ANALYTICS"}
    cache.set(original_q, cached_payload)
    
    paraphrased_q = "Which products are running out of stock?"
    start = time.time()
    res = cache.get(paraphrased_q)
    duration_semantic = (time.time() - start) * 1000
    
    assert res is not None, "Semantic paraphrase match failed"
    assert res["generation"] == cached_payload["generation"]
    print(f"✅ Paraphrased match returned in {duration_semantic:.2f}ms: '{paraphrased_q}' matched '{original_q}'")

def test_cache_stats_and_clear():
    print("--- 3. Testing Cache Statistics & Clearing ---")
    cache = SemanticCacheManager(ttl_seconds=300, similarity_threshold=0.80)
    cache.set("Show low stock items", {"gen": "test"})
    cache.get("Show low stock items")
    cache.get("Non existent item query")
    
    stats = cache.get_stats()
    assert stats["hits"] >= 1
    assert stats["misses"] >= 1
    assert stats["entries_count"] == 1
    print(f"✅ Cache Stats: {stats}")
    
    cache.clear()
    assert cache.get_stats()["entries_count"] == 0
    print("✅ Cache cleared successfully")

def test_fastapi_endpoints():
    print("--- 4. Testing FastAPI Server Endpoints ---")
    from fastapi.testclient import TestClient
    from main import app
    
    client = TestClient(app)
    
    # Health check
    resp = client.get("/health")
    assert resp.status_code == 200
    print("✅ Health check endpoint OK")
    
    # Cache stats endpoint
    resp_stats = client.get("/api/cache/stats")
    assert resp_stats.status_code == 200
    body = resp_stats.json()
    assert "vector_semantic_cache" in body
    assert "persistent_cache" in body
    print(f"✅ Cache stats endpoint OK: {body}")

if __name__ == "__main__":
    test_semantic_cache_basic()
    test_semantic_cache_paraphrase()
    test_cache_stats_and_clear()
    test_fastapi_endpoints()
    print("\n🎉 ALL PHASE 1 TESTS PASSED SUCCESSFULLY!")
