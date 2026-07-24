import sqlite3
import hashlib
import json
import os
import re
from typing import Optional, Tuple, List

class CacheManager:
    def __init__(self, db_path: str = "rag_backend/cache.db", similarity_threshold: float = 0.80):
        self.db_path = db_path
        self.similarity_threshold = similarity_threshold
        self._init_db()

    def _init_db(self):
        # Ensure parent directory exists
        dir_name = os.path.dirname(self.db_path)
        if dir_name:
            os.makedirs(dir_name, exist_ok=True)
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS query_cache (
                    cache_key TEXT PRIMARY KEY,
                    question TEXT NOT NULL,
                    context TEXT NOT NULL,
                    history TEXT,
                    generation TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            # Create index for fast retrieval
            conn.execute("CREATE INDEX IF NOT EXISTS idx_cache_key ON query_cache (cache_key)")

    def _compute_key(self, question: str, context: Optional[str], history: Optional[list]) -> str:
        history_str = json.dumps(history or [], sort_keys=True)
        context_str = context or ""
        raw_str = f"q:{question.strip().lower()}|c:{context_str}|h:{history_str}"
        return hashlib.sha256(raw_str.encode("utf-8")).hexdigest()

    def _tokenize(self, text: str) -> set:
        stopwords = {'the', 'a', 'an', 'of', 'for', 'in', 'on', 'to', 'at', 'with', 'is', 'are', 'what', 'show', 'tell', 'me', 'get', 'give', 'my', 'please'}
        clean = re.sub(r'[^\w\s]', '', text.lower())
        words = set(clean.split())
        content_words = words - stopwords
        return content_words if content_words else words

    def _similarity_score(self, str1: str, str2: str) -> float:
        """Calculates hybrid Jaccard & sequence overlap similarity score (0.0 to 1.0)."""
        tokens1 = self._tokenize(str1)
        tokens2 = self._tokenize(str2)
        if not tokens1 or not tokens2:
            return 1.0 if str1.strip().lower() == str2.strip().lower() else 0.0
        
        intersection = tokens1.intersection(tokens2)
        union = tokens1.union(tokens2)
        jaccard = len(intersection) / len(union) if union else 0.0
        
        # Keyword sequence bonus
        words1 = [w for w in re.sub(r'[^\w\s]', '', str1.lower()).split() if w not in {'the', 'a', 'an', 'of', 'for', 'is', 'are'}]
        words2 = [w for w in re.sub(r'[^\w\s]', '', str2.lower()).split() if w not in {'the', 'a', 'an', 'of', 'for', 'is', 'are'}]
        common_order = sum(1 for w1, w2 in zip(words1, words2) if w1 == w2)
        seq_ratio = common_order / max(len(words1), len(words2)) if max(len(words1), len(words2)) > 0 else 0
        
        return 0.8 * jaccard + 0.2 * seq_ratio

    def get(self, question: str, context: Optional[str], history: Optional[list]) -> Optional[str]:
        # 1. Fast exact hash check (< 2ms)
        key = self._compute_key(question, context, history)
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    "SELECT generation FROM query_cache WHERE cache_key = ?",
                    (key,)
                )
                row = cursor.fetchone()
                if row:
                    return row[0]
                
                # 2. Semantic similarity scan over existing questions if no exact hash match
                context_str = context or ""
                history_str = json.dumps(history or [], sort_keys=True)
                
                cursor.execute("SELECT question, context, history, generation FROM query_cache")
                rows = cursor.fetchall()
                
                best_score = 0.0
                best_generation = None
                
                norm_q = question.strip().lower()
                for cached_q, cached_ctx, cached_hist, gen in rows:
                    if cached_ctx == context_str and cached_hist == history_str:
                        score = self._similarity_score(norm_q, cached_q)
                        if score > best_score:
                            best_score = score
                            best_generation = gen
                
                if best_score >= self.similarity_threshold and best_generation:
                    return best_generation
        except Exception as e:
            print(f"Cache read error: {e}")
        return None

    def _has_id_col(self, conn) -> bool:
        try:
            cursor = conn.cursor()
            cursor.execute("PRAGMA table_info(query_cache)")
            cols = [row[1] for row in cursor.fetchall()]
            return "id" in cols
        except Exception:
            return False

    def set(self, question: str, context: Optional[str], history: Optional[list], generation: str):
        key = self._compute_key(question, context, history)
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute(
                    """
                    INSERT OR REPLACE INTO query_cache (cache_key, question, context, history, generation)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (key, question.strip().lower(), context or "", json.dumps(history or [], sort_keys=True), generation)
                )
        except Exception as e:
            print(f"Cache write error: {e}")

    def clear(self):
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute("DELETE FROM query_cache")
        except Exception as e:
            print(f"Cache clear error: {e}")

    def get_stats(self) -> dict:
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT COUNT(*) FROM query_cache")
                count = cursor.fetchone()[0]
                return {
                    "persistent_entries": count,
                    "db_path": self.db_path,
                    "similarity_threshold": self.similarity_threshold
                }
        except Exception as e:
            return {"persistent_entries": 0, "error": str(e)}


