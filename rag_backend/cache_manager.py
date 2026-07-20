import sqlite3
import hashlib
import json
import os
from typing import Optional

class CacheManager:
    def __init__(self, db_path: str = "rag_backend/cache.db"):
        self.db_path = db_path
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
        # Sort keys to ensure stable JSON serialization of history
        history_str = json.dumps(history or [], sort_keys=True)
        context_str = context or ""
        raw_str = f"q:{question}|c:{context_str}|h:{history_str}"
        return hashlib.sha256(raw_str.encode("utf-8")).hexdigest()

    def get(self, question: str, context: Optional[str], history: Optional[list]) -> Optional[str]:
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
        except Exception as e:
            print(f"Cache read error: {e}")
        return None

    def set(self, question: str, context: Optional[str], history: Optional[list], generation: str):
        key = self._compute_key(question, context, history)
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute(
                    """
                    INSERT OR REPLACE INTO query_cache (cache_key, question, context, history, generation)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (key, question, context or "", json.dumps(history or []), generation)
                )
        except Exception as e:
            print(f"Cache write error: {e}")

    def clear(self):
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute("DELETE FROM query_cache")
        except Exception as e:
            print(f"Cache clear error: {e}")
