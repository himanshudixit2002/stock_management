import hashlib
import re
import logging
from typing import Optional

from cachetools import TTLCache

logger = logging.getLogger(__name__)

# LRU + TTL cache: max 500 entries, 5 minute TTL
_cache: TTLCache = TTLCache(maxsize=500, ttl=300)

# Intents that should NOT be cached (mutations)
_NO_CACHE_INTENTS = frozenset({"STOCK_UPDATE", "ORDER_MGMT"})


def _normalize(text: str) -> str:
    """Normalize text for consistent cache keys."""
    return re.sub(r"\s+", " ", text.lower().strip())


def _make_key(question: str, context: Optional[str]) -> str:
    """Create a cache key from question and context."""
    norm_q = _normalize(question)
    ctx_hash = hashlib.md5((context or "").encode()).hexdigest()
    combined = f"{norm_q}::{ctx_hash}"
    return hashlib.sha256(combined.encode()).hexdigest()


def should_cache(intent: str) -> bool:
    """Check if responses for this intent should be cached."""
    return intent not in _NO_CACHE_INTENTS


def get_cached(question: str, context: Optional[str] = None) -> Optional[dict]:
    """Retrieve a cached response if available.

    Args:
        question: The user's question.
        context: The provided context string.

    Returns:
        Cached response dict or None if not found.
    """
    key = _make_key(question, context)
    result = _cache.get(key)
    if result is not None:
        logger.info("Cache HIT for key: %.16s...", key)
    return result


def set_cached(
    question: str,
    context: Optional[str],
    response: dict,
) -> None:
    """Store a response in the cache.

    Args:
        question: The user's question.
        context: The provided context string.
        response: The response dict to cache.
    """
    key = _make_key(question, context)
    _cache[key] = response
    logger.info("Cache SET for key: %.16s...", key)
