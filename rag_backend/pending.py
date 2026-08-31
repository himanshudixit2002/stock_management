"""
Server-side pending-action store for the confirm-before-write flow.

The previous implementation rendered a confirmation table into markdown and
then, on the next turn, scraped its own rendered output back out with regexes
to work out what to execute. That breaks the moment the wording or the table
layout changes, and it silently executed the wrong thing when the scrape
half-matched.

Here the structured action is held server-side and looked up by
(company_id, session_id), so confirming executes exactly what was previewed.
"""

from __future__ import annotations

import threading
import time
from typing import Any, Dict, Optional

TTL_SECONDS = 600.0
MAX_ENTRIES = 2000

CONFIRM_WORDS = {
    "confirm", "yes", "yeah", "yep", "y", "ok", "okay", "sure", "proceed",
    "do it", "apply", "approve", "go ahead", "confirmed", "please do",
    "yes please", "yes do it", "correct", "right",
}

CANCEL_WORDS = {
    "no", "nope", "cancel", "stop", "abort", "nevermind", "never mind",
    "don't", "dont", "forget it", "no thanks",
}


def _norm(text: str) -> str:
    return " ".join((text or "").lower().replace("!", " ").replace(".", " ").split())


def is_confirmation(text: str) -> bool:
    t = _norm(text)
    if not t or len(t) > 40:
        return False
    return t in CONFIRM_WORDS or any(
        t.startswith(w + " ") or t.endswith(" " + w) for w in CONFIRM_WORDS
    )


def is_cancellation(text: str) -> bool:
    t = _norm(text)
    if not t or len(t) > 40:
        return False
    return t in CANCEL_WORDS or any(t.startswith(w + " ") for w in CANCEL_WORDS)


class PendingActionStore:
    def __init__(self, ttl_seconds: float = TTL_SECONDS):
        self.ttl = ttl_seconds
        self._lock = threading.RLock()
        self._store: Dict[str, Dict[str, Any]] = {}

    @staticmethod
    def _key(company_id: Optional[str], session_id: Optional[str]) -> str:
        cid = (company_id or "default").strip() or "default"
        sid = (session_id or "default").strip() or "default"
        return f"{cid}::{sid}"

    def put(self, company_id: str, session_id: str, action: Dict[str, Any]) -> None:
        with self._lock:
            self._evict()
            self._store[self._key(company_id, session_id)] = {
                "action": action,
                "created_at": time.time(),
            }

    def get(self, company_id: str, session_id: str) -> Optional[Dict[str, Any]]:
        key = self._key(company_id, session_id)
        with self._lock:
            entry = self._store.get(key)
            if not entry:
                return None
            if time.time() - entry["created_at"] > self.ttl:
                del self._store[key]
                return None
            return entry["action"]

    def pop(self, company_id: str, session_id: str) -> Optional[Dict[str, Any]]:
        action = self.get(company_id, session_id)
        if action is not None:
            self.clear(company_id, session_id)
        return action

    def clear(self, company_id: str, session_id: str) -> None:
        with self._lock:
            self._store.pop(self._key(company_id, session_id), None)

    def _evict(self) -> None:
        now = time.time()
        stale = [k for k, v in self._store.items() if now - v["created_at"] > self.ttl]
        for k in stale:
            del self._store[k]
        if len(self._store) > MAX_ENTRIES:
            oldest = sorted(self._store.items(), key=lambda kv: kv[1]["created_at"])
            for k, _ in oldest[: len(self._store) - MAX_ENTRIES]:
                del self._store[k]


pending_actions = PendingActionStore()
