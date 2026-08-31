"""
Server-side pending-action store for the confirm-before-write flow.

The previous implementation rendered a confirmation table into markdown and
then, on the next turn, scraped its own rendered output back out with regexes
to work out what to execute. That breaks the moment the wording or the table
layout changes, and it silently executed the wrong thing when the scrape
half-matched.

Here the structured action is held server-side and looked up by
(company_id, session_id), so confirming executes exactly what was previewed.

It is also mirrored to Firestore. In-memory alone is correct only while one
container serves both turns; the moment Cloud Run scales past a single
instance, a confirm can land somewhere that never saw the preview and silently
do nothing. Memory stays the fast path; Firestore makes it correct.
"""

from __future__ import annotations

import os
import threading
import time
from datetime import datetime, timezone
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


def _firestore():
    """Shared client, or None when running offline."""
    if os.environ.get("OFFLINE_MODE") == "1":
        return None
    try:
        from inventory_db import db_firestore

        return db_firestore
    except Exception:
        return None


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

    @staticmethod
    def _doc(client, company_id: str, session_id: str):
        safe = (session_id or "default").replace("/", "_")[:200]
        return (
            client.collection("companies")
            .document(company_id)
            .collection("ai_pending")
            .document(safe)
        )

    def _remote_put(self, company_id: str, session_id: str, action: Dict[str, Any]) -> None:
        client = _firestore()
        if client is None:
            return
        try:
            self._doc(client, company_id, session_id).set(
                {"action": action, "created_at": datetime.now(timezone.utc)}
            )
        except Exception as exc:
            print(f"[pending] could not persist action: {exc}")

    def _remote_get(self, company_id: str, session_id: str) -> Optional[Dict[str, Any]]:
        client = _firestore()
        if client is None:
            return None
        try:
            snap = self._doc(client, company_id, session_id).get()
            if not snap.exists:
                return None
            data = snap.to_dict() or {}
            created = data.get("created_at")
            if created is not None:
                if created.tzinfo is None:
                    created = created.replace(tzinfo=timezone.utc)
                if (datetime.now(timezone.utc) - created).total_seconds() > self.ttl:
                    self._remote_clear(company_id, session_id)
                    return None
            return data.get("action")
        except Exception as exc:
            print(f"[pending] could not read persisted action: {exc}")
            return None

    def _remote_clear(self, company_id: str, session_id: str) -> None:
        client = _firestore()
        if client is None:
            return
        try:
            self._doc(client, company_id, session_id).delete()
        except Exception as exc:
            print(f"[pending] could not clear persisted action: {exc}")

    def put(self, company_id: str, session_id: str, action: Dict[str, Any]) -> None:
        with self._lock:
            self._evict()
            self._store[self._key(company_id, session_id)] = {
                "action": action,
                "created_at": time.time(),
            }
        self._remote_put(company_id, session_id, action)

    def get(self, company_id: str, session_id: str) -> Optional[Dict[str, Any]]:
        key = self._key(company_id, session_id)
        with self._lock:
            entry = self._store.get(key)
            if entry and time.time() - entry["created_at"] <= self.ttl:
                return entry["action"]
            if entry:
                del self._store[key]

        # Local miss: another instance may have served the preview.
        action = self._remote_get(company_id, session_id)
        if action is not None:
            with self._lock:
                self._store[key] = {"action": action, "created_at": time.time()}
        return action

    def pop(self, company_id: str, session_id: str) -> Optional[Dict[str, Any]]:
        action = self.get(company_id, session_id)
        if action is not None:
            self.clear(company_id, session_id)
        return action

    def clear(self, company_id: str, session_id: str) -> None:
        with self._lock:
            self._store.pop(self._key(company_id, session_id), None)
        self._remote_clear(company_id, session_id)

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
