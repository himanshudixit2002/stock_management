import os
from cache_manager import CacheManager

def test_cache_manager():
    db_path = "rag_backend/test_cache.db"
    
    # Clean up previous test run if any
    if os.path.exists(db_path):
        os.remove(db_path)
        
    print("Initializing CacheManager...")
    cache = CacheManager(db_path=db_path)
    
    question = "What is the stock of Apples?"
    context = "Apples: 15 units"
    history = [{"role": "user", "content": "hello"}]
    generation = "Apples currently has 15 units of stock."
    
    # 1. Test cache miss
    print("Testing cache get on empty cache (should be None)...")
    res = cache.get(question, context, history)
    assert res is None, "Cache should have missed"
    print("✓ Cache miss verified.")
    
    # 2. Test cache set and retrieve
    print("Setting value in cache...")
    cache.set(question, context, history, generation)
    
    print("Testing cache get on populated cache (should hit)...")
    res = cache.get(question, context, history)
    assert res == generation, f"Cache hit failed. Expected: {generation}, Got: {res}"
    print("✓ Cache hit verified.")
    
    # 3. Test context invalidation
    print("Testing cache get with modified context (should miss)...")
    new_context = "Apples: 10 units"
    res = cache.get(question, new_context, history)
    assert res is None, "Cache should have missed due to context change"
    print("✓ Cache invalidation on context change verified.")
    
    # 4. Test history invalidation
    print("Testing cache get with modified history (should miss)...")
    new_history = [{"role": "user", "content": "hi there"}]
    res = cache.get(question, context, new_history)
    assert res is None, "Cache should have missed due to history change"
    print("✓ Cache invalidation on history change verified.")
    
    # 5. Test cache clear
    print("Testing cache clear...")
    cache.clear()
    res = cache.get(question, context, history)
    assert res is None, "Cache should be empty after clear"
    print("✓ Cache clear verified.")
    
    # Clean up
    if os.path.exists(db_path):
        os.remove(db_path)
        
    print("\nAll Cache tests passed successfully!")

if __name__ == "__main__":
    test_cache_manager()
