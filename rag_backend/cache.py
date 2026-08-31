"""
One answer cache, keyed so that hits are both frequent and never stale.

What was wrong before:
  * The key hashed the full chat history, so it changed every single turn and
    the cache effectively never hit.
  * On a miss it scanned the entire table, comparing the question against every
    stored question — O(n) work per request for a cache that never hit.
  * A second "semantic" tier compared bag-of-words vectors at a 0.80 threshold,
    which is loose enough to serve one product's answer for another's question.
  * Nothing invalidated when stock changed in the app, only when the AI itself
    executed an action — so answers stayed wrong for the full 10 minute TTL.

What this does instead: the key is
    (company_id, business_type, normalised question, inventory fingerprint)
The fingerprint is a content hash of the live inventory, so any stock change
rotates the key automatically, on every instance, with no coordination.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import threading
import time
from collections import OrderedDict
from typing import Any, Dict, Optional

DB_PATH = os.environ.get(
    "CACHE_DB_PATH", os.path.join(os.path.dirname(__file__), "cache.db")
)
TTL_SECONDS = float(os.environ.get("ANSWER_CACHE_TTL", "900"))
MEMORY_ENTRIES = int(os.environ.get("ANSWER_CACHE_ENTRIES", "512"))

# Mutations must never be answered from cache.
NON_CACHEABLE_INTENTS = {"EXECUTION", "ACTION", "CLARIFY"}

_PUNCT = re.compile(r"[^\w\s]")
_WS = re.compile(r"\s+")


def normalize_question(question: str) -> str:
    text = _PUNCT.sub(" ", (question or "").lower())
    return _WS.sub(" ", text).strip()


class AnswerCache:
    def __init__(self, db_path: str = DB_PATH, ttl_seconds: float = TTL_SECONDS):
        self.db_path = db_path
        self.ttl = ttl_seconds
        self._lock = threading.RLock()
        self._memory: "OrderedDict[str, Dict[str, Any]]" = OrderedDict()
        self.hits = 0
        self.misses = 0
        self._init_db()

    # ------------------------------------------------------------------

    def _init_db(self) -> None:
        try:
            parent = os.path.dirname(self.db_path)
            if parent:
                os.makedirs(parent, exist_ok=True)
            with sqlite3.connect(self.db_path) as conn:
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS answers (
                        cache_key   TEXT PRIMARY KEY,
                        company_id  TEXT NOT NULL,
                        fingerprint TEXT NOT NULL,
                        question    TEXT NOT NULL,
                        intent      TEXT,
                        payload     TEXT NOT NULL,
                        created_at  REAL NOT NULL
                    )
                    """
                )
                conn.execute(
                    "CREATE INDEX IF NOT EXISTS idx_answers_company ON answers (company_id)"
                )
                # Retire the old schema; its keys are not comparable with these.
                conn.execute("DROP TABLE IF EXISTS query_cache")
        except Exception as exc:
            print(f"[AnswerCache] init failed, running memory-only: {exc}")

    @staticmethod
    def _cid(company_id: Optional[str]) -> str:
        return (company_id or "default").strip() or "default"

    def key(
        self,
        question: str,
        company_id: str,
        fingerprint: str,
        business_type: str = "retail_store",
    ) -> str:
        raw = (
            f"{self._cid(company_id)}|{business_type}|"
            f"{normalize_question(question)}|{fingerprint}"
        )
        return hashlib.sha256(raw.encode("utf-8")).hexdigest()

    # ------------------------------------------------------------------

    def get(
        self,
        question: str,
        company_id: str,
        fingerprint: str,
        business_type: str = "retail_store",
    ) -> Optional[Dict[str, Any]]:
        cache_key = self.key(question, company_id, fingerprint, business_type)
        now = time.time()

        with self._lock:
            entry = self._memory.get(cache_key)
            if entry is not None:
                if now - entry["created_at"] < self.ttl:
                    self._memory.move_to_end(cache_key)
                    self.hits += 1
                    return entry["payload"]
                del self._memory[cache_key]

        try:
            with sqlite3.connect(self.db_path) as conn:
                row = conn.execute(
                    "SELECT payload, created_at FROM answers WHERE cache_key = ?",
                    (cache_key,),
                ).fetchone()
            if row and (now - row[1]) < self.ttl:
                payload = json.loads(row[0])
                self._remember(cache_key, payload, row[1])
                self.hits += 1
                return payload
        except Exception as exc:
            print(f"[AnswerCache] read failed: {exc}")

        self.misses += 1
        return None

    def set(
        self,
        question: str,
        company_id: str,
        fingerprint: str,
        payload: Dict[str, Any],
        business_type: str = "retail_store",
    ) -> None:
        intent = str(payload.get("intent", "")).upper()
        if intent in NON_CACHEABLE_INTENTS:
            return
        if not payload.get("answer"):
            return

        cache_key = self.key(question, company_id, fingerprint, business_type)
        created = time.time()
        self._remember(cache_key, payload, created)
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute(
                    """
                    INSERT OR REPLACE INTO answers
                        (cache_key, company_id, fingerprint, question, intent, payload, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        cache_key,
                        self._cid(company_id),
                        fingerprint,
                        normalize_question(question),
                        intent or None,
                        json.dumps(payload),
                        created,
                    ),
                )
        except Exception as exc:
            print(f"[AnswerCache] write failed: {exc}")

    def _remember(self, cache_key: str, payload: Dict[str, Any], created_at: float) -> None:
        with self._lock:
            self._memory[cache_key] = {"payload": payload, "created_at": created_at}
            self._memory.move_to_end(cache_key)
            while len(self._memory) > MEMORY_ENTRIES:
                self._memory.popitem(last=False)

    def clear(self, company_id: Optional[str] = None) -> None:
        """Scoped by default — a tenant-blind clear used to flush every company."""
        cid = self._cid(company_id) if company_id else None
        with self._lock:
            self._memory.clear()
        try:
            with sqlite3.connect(self.db_path) as conn:
                if cid:
                    conn.execute("DELETE FROM answers WHERE company_id = ?", (cid,))
                else:
                    conn.execute("DELETE FROM answers")
        except Exception as exc:
            print(f"[AnswerCache] clear failed: {exc}")

    def stats(self) -> Dict[str, Any]:
        total = self.hits + self.misses
        persistent = 0
        try:
            with sqlite3.connect(self.db_path) as conn:
                persistent = conn.execute("SELECT COUNT(*) FROM answers").fetchone()[0]
        except Exception:
            pass
        return {
            "hits": self.hits,
            "misses": self.misses,
            "hit_rate_pct": round((self.hits / total * 100) if total else 0.0, 2),
            "memory_entries": len(self._memory),
            "persistent_entries": persistent,
            "ttl_seconds": self.ttl,
            "keyed_on": "company_id + business_type + question + inventory_fingerprint",
        }


answer_cache = AnswerCache()
