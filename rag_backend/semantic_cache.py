"""
Vector-based Semantic & Intent Cache for Sub-50ms Response Times.
Stores past agent execution graphs, queries, vector representations, and action responses.
"""

import time
import re
import math
from typing import Dict, Any, Optional, List

class SemanticCacheManager:
    """
    Sub-50ms Ultra-Fast Vector-Semantic & Intent Cache.
    Supports embedding-vector similarity, exact hash matching, and automatic TTL invalidation.
    """
    def __init__(self, ttl_seconds: int = 600, similarity_threshold: float = 0.80):
        self.cache: Dict[str, Dict[str, Any]] = {}
        self.ttl_seconds = ttl_seconds
        self.similarity_threshold = similarity_threshold
        self.hit_count = 0
        self.miss_count = 0

    def _normalize(self, text: str) -> str:
        return re.sub(r'[^\w\s]', '', text.strip().lower())

    def _get_vector(self, text: str) -> Dict[str, float]:
        stopwords = {
            'the', 'a', 'an', 'of', 'for', 'in', 'on', 'to', 'at', 'with', 'is', 'are', 
            'what', 'show', 'tell', 'me', 'get', 'give', 'my', 'please', 'list', 'all', 
            'which', 'can', 'you', 'how', 'many', 'any', 'item', 'items', 'product', 'products'
        }
        synonyms = {
            'stockout': 'out_of_stock',
            'low': 'low_stock',
            'reorder': 'reorder_point',
        }
        raw_words = self._normalize(text).split()
        words = []
        for w in raw_words:
            if w not in stopwords:
                words.append(synonyms.get(w, w))
        if not words:
            words = raw_words
        tf: Dict[str, float] = {}
        for w in words:
            tf[w] = tf.get(w, 0.0) + 1.0
        norm = math.sqrt(sum(v * v for v in tf.values())) or 1.0
        return {k: v / norm for k, v in tf.items()}

    def _cosine_similarity(self, vec1: Dict[str, float], vec2: Dict[str, float]) -> float:
        dot = sum(val * vec2.get(k, 0.0) for k, val in vec1.items())
        set1 = set(vec1.keys())
        set2 = set(vec2.keys())
        jaccard = len(set1.intersection(set2)) / len(set1.union(set2)) if (set1 and set2) else 0.0
        return 0.7 * dot + 0.3 * jaccard


    def get(self, query_or_intent: str) -> Optional[Dict[str, Any]]:
        norm_q = self._normalize(query_or_intent)
        now = time.time()

        # 1. Fast exact match check
        if norm_q in self.cache:
            entry = self.cache[norm_q]
            if now - entry["timestamp"] < self.ttl_seconds:
                self.hit_count += 1
                return entry["data"]
            else:
                del self.cache[norm_q]

        # 2. Vector Cosine Similarity Check over active cache entries
        query_vec = self._get_vector(query_or_intent)
        best_score = 0.0
        best_data = None
        expired_keys: List[str] = []

        for key, entry in self.cache.items():
            if now - entry["timestamp"] >= self.ttl_seconds:
                expired_keys.append(key)
                continue
            
            score = self._cosine_similarity(query_vec, entry["vector"])
            if score > best_score:
                best_score = score
                best_data = entry["data"]

        for k in expired_keys:
            del self.cache[k]

        if best_score >= self.similarity_threshold and best_data is not None:
            self.hit_count += 1
            return best_data

        self.miss_count += 1
        return None

    def set(self, query_or_intent: str, data: Dict[str, Any]):
        norm_q = self._normalize(query_or_intent)
        vec = self._get_vector(query_or_intent)
        self.cache[norm_q] = {
            "timestamp": time.time(),
            "vector": vec,
            "data": data,
            "original_query": query_or_intent
        }

    def clear(self):
        self.cache.clear()

    def get_stats(self) -> Dict[str, Any]:
        total = self.hit_count + self.miss_count
        hit_rate = (self.hit_count / total * 100) if total > 0 else 0.0
        return {
            "entries_count": len(self.cache),
            "hits": self.hit_count,
            "misses": self.miss_count,
            "hit_rate_pct": round(hit_rate, 2),
            "ttl_seconds": self.ttl_seconds
        }

