"""
LLM factory with cost tiering.

The old `get_active_llm` built a brand new client on every node call and
hardcoded one model for everything — intent classification paid the same price
as multi-step reasoning, and the silent Gemini->Vertex->Tinker fall-through made
it impossible to tell which provider actually served a request.

Three tiers, all env-overridable:

    ROUTER_MODEL  cheap+fast  intent classification, disambiguation, short lookups
    AGENT_MODEL   balanced    analytics, execution, tool calling, chat
    HEAVY_MODEL   strong      opt-in only, genuinely multi-step strategic asks
"""

from __future__ import annotations

import os
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))
load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

ROUTER = "router"
AGENT = "agent"
HEAVY = "heavy"

_MODEL_ENV = {
    ROUTER: ("ROUTER_MODEL", "gemini-2.5-flash-lite"),
    AGENT: ("AGENT_MODEL", "gemini-2.5-flash"),
    HEAVY: ("HEAVY_MODEL", "gemini-2.5-pro"),
}

GCP_PROJECT = os.environ.get("GCP_PROJECT", "stockmanagement-27af8")
GCP_LOCATION = os.environ.get("GCP_LOCATION", "asia-south1")

_PLACEHOLDER_KEYS = {
    "MOCK_KEY_FOR_INIT",
    "your_gemini_api_key_here",
    "YOUR_GEMINI_API_KEY",
    "your_tinker_api_key_here",
    "changeme",
}


def model_for(tier: str) -> str:
    env_name, default = _MODEL_ENV.get(tier, _MODEL_ENV[AGENT])
    return os.environ.get(env_name, default)


def is_valid_api_key(key: Optional[str]) -> bool:
    if not key:
        return False
    k = str(key).strip()
    if k in _PLACEHOLDER_KEYS:
        return False
    return k.startswith("AIza") or k.startswith("tml-") or len(k) >= 20


def _gemini_key() -> Optional[str]:
    key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    return key if is_valid_api_key(key) else None


@dataclass
class LlmUsage:
    """Per-process usage accounting, so cost is attributable to a tier."""

    calls: Dict[str, int] = field(default_factory=dict)
    input_tokens: Dict[str, int] = field(default_factory=dict)
    output_tokens: Dict[str, int] = field(default_factory=dict)
    _lock: threading.Lock = field(default_factory=threading.Lock, repr=False)

    def record(self, tier: str, response: Any = None) -> None:
        with self._lock:
            self.calls[tier] = self.calls.get(tier, 0) + 1
            meta = getattr(response, "usage_metadata", None) or {}
            if isinstance(meta, dict):
                self.input_tokens[tier] = self.input_tokens.get(tier, 0) + int(
                    meta.get("input_tokens", 0) or 0
                )
                self.output_tokens[tier] = self.output_tokens.get(tier, 0) + int(
                    meta.get("output_tokens", 0) or 0
                )

    def snapshot(self) -> Dict[str, Any]:
        with self._lock:
            tiers = set(self.calls) | set(self.input_tokens) | set(self.output_tokens)
            return {
                "by_tier": {
                    t: {
                        "calls": self.calls.get(t, 0),
                        "input_tokens": self.input_tokens.get(t, 0),
                        "output_tokens": self.output_tokens.get(t, 0),
                        "model": model_for(t),
                    }
                    for t in sorted(tiers)
                },
                "total_calls": sum(self.calls.values()),
                "total_input_tokens": sum(self.input_tokens.values()),
                "total_output_tokens": sum(self.output_tokens.values()),
            }


usage = LlmUsage()

_cache: Dict[Tuple[Any, ...], Any] = {}
_cache_lock = threading.Lock()
_active_provider: Optional[str] = None
_provider_logged = False


def active_provider() -> Optional[str]:
    return _active_provider


def _build(tier: str, temperature: float) -> Tuple[Optional[Any], str]:
    """Construct a client for `tier`, returning (client, provider_name)."""
    model = model_for(tier)

    key = _gemini_key()
    if key:
        try:
            from langchain_google_genai import ChatGoogleGenerativeAI

            return (
                ChatGoogleGenerativeAI(
                    model=model,
                    temperature=temperature,
                    google_api_key=key,
                ),
                f"google-genai:{model}",
            )
        except Exception as exc:
            print(f"[LLM] Gemini API init failed for {model}: {exc}")

    # No key: fall back to the Cloud Run service account via Vertex. Same class,
    # `vertexai=True` — ChatVertexAI is deprecated in the installed stack.
    try:
        from langchain_google_genai import ChatGoogleGenerativeAI

        return (
            ChatGoogleGenerativeAI(
                model=model,
                temperature=temperature,
                vertexai=True,
                project=GCP_PROJECT,
                location=GCP_LOCATION,
            ),
            f"vertex:{model}",
        )
    except Exception as exc:
        print(f"[LLM] Vertex AI init failed for {model}: {exc}")

    tinker_key = os.environ.get("TINKER_API_KEY")
    if is_valid_api_key(tinker_key):
        try:
            from langchain_openai import ChatOpenAI

            tinker_model = os.environ.get("TINKER_MODEL", "tinker://default")
            return (
                ChatOpenAI(
                    model=tinker_model,
                    temperature=temperature,
                    openai_api_key=tinker_key,
                    openai_api_base=os.environ.get(
                        "TINKER_BASE_URL",
                        "https://tinker.thinkingmachines.dev/services/tinker-prod/oai/api/v1",
                    ),
                ),
                f"tinker:{tinker_model}",
            )
        except Exception as exc:
            print(f"[LLM] Tinker init failed: {exc}")

    return None, "none"


def get_llm(
    tier: str = AGENT,
    temperature: float = 0.0,
    tools: Optional[List[Any]] = None,
) -> Optional[Any]:
    """Return a cached client for `tier`, optionally bound to `tools`."""
    global _active_provider, _provider_logged

    tool_sig = tuple(sorted(getattr(t, "__name__", str(t)) for t in (tools or [])))
    cache_key = (tier, round(temperature, 3), tool_sig)

    with _cache_lock:
        cached = _cache.get(cache_key)
    if cached is not None:
        return cached

    client, provider = _build(tier, temperature)
    if client is None:
        if not _provider_logged:
            print("[LLM] No provider available — falling back to deterministic answers only.")
            _provider_logged = True
        return None

    _active_provider = provider
    if not _provider_logged:
        print(f"[LLM] Serving via {provider} (router={model_for(ROUTER)}, agent={model_for(AGENT)})")
        _provider_logged = True

    if tools:
        try:
            client = client.bind_tools(tools)
        except Exception as exc:
            print(f"[LLM] bind_tools failed for {provider}: {exc}")
            return None

    with _cache_lock:
        _cache[cache_key] = client
    return client


def available() -> bool:
    return get_llm(ROUTER) is not None


def health() -> Dict[str, Any]:
    return {
        "provider": _active_provider or "uninitialised",
        "models": {t: model_for(t) for t in (ROUTER, AGENT, HEAVY)},
        "gemini_api_key_present": _gemini_key() is not None,
        "usage": usage.snapshot(),
    }
