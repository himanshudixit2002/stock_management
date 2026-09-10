"""Tracing, metrics and cost accounting for the agent.

The eval harness grades the agent before it ships. This is the other half: what
it actually did once it was live. Both exist because "the assistant feels slow
and the bill went up" is not a debuggable statement, and neither is "someone
said it gave a wrong number yesterday".

Three deliberate choices.

**Spans follow the OpenTelemetry GenAI semantic conventions** (``gen_ai.*``)
rather than a bespoke attribute naming. It costs nothing to use the standard
names and it means any backend that understands LLM traces — and increasingly
they all do — renders these without a custom mapping.

**No tenant data leaves the process.** A trace is exported to a third party;
inventory is not. Company ids are hashed to a stable short digest, and question
text is captured only when ``OTEL_CAPTURE_PROMPTS=1`` is set explicitly, which
is a thing you turn on to debug your own workspace and off again.

**Telemetry never breaks the request.** Every public function here swallows its
own exceptions. A misconfigured collector endpoint should make the dashboards
empty, not the API 500.
"""

from __future__ import annotations

import hashlib
import json
import os
import threading
import time
from collections import defaultdict
from contextlib import contextmanager
from typing import Any, Dict, Iterator, Optional

SERVICE_NAME = os.environ.get("OTEL_SERVICE_NAME", "inventory-agent")
OTLP_ENDPOINT = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "").strip()
CAPTURE_PROMPTS = os.environ.get("OTEL_CAPTURE_PROMPTS", "").strip() in {"1", "true", "yes"}
CONSOLE_TRACES = os.environ.get("OTEL_CONSOLE_TRACES", "").strip() in {"1", "true", "yes"}

_tracer = None
_configured = False
_configure_lock = threading.Lock()


# ---------------------------------------------------------------------------
# Cost
# ---------------------------------------------------------------------------

# USD per million tokens, as a snapshot. Model pricing changes without warning,
# so this is env-overridable per tier and the numbers here are a starting point
# to be re-checked against the provider's current published rates — not a
# quotation. `cost_usd` is an internal budgeting signal, not a billing figure.
#
#   MODEL_PRICE_ROUTER="0.10,0.40"   # input,output USD per 1M tokens
_DEFAULT_PRICES = {
    "router": (0.10, 0.40),
    "agent": (0.30, 2.50),
    "heavy": (1.25, 10.00),
}


def _prices(tier: str) -> tuple:
    raw = os.environ.get(f"MODEL_PRICE_{tier.upper()}", "").strip()
    if raw:
        try:
            inp, out = (float(x) for x in raw.split(",", 1))
            return (inp, out)
        except Exception:
            pass
    return _DEFAULT_PRICES.get(tier, _DEFAULT_PRICES["agent"])


def cost_usd(tier: str, input_tokens: int, output_tokens: int) -> float:
    inp, out = _prices(tier)
    return round(
        (input_tokens / 1_000_000.0) * inp + (output_tokens / 1_000_000.0) * out, 6
    )


# ---------------------------------------------------------------------------
# Privacy
# ---------------------------------------------------------------------------

_SALT = os.environ.get("TELEMETRY_SALT", "inventory-agent")


def tenant_digest(company_id: Optional[str]) -> str:
    """A stable, non-reversible handle for a workspace.

    Enough to say "this tenant's p95 doubled"; not enough for whoever runs the
    tracing backend to learn who the tenant is.
    """
    raw = f"{_SALT}:{(company_id or 'unknown')}".encode("utf-8")
    return hashlib.sha256(raw).hexdigest()[:12]


# ---------------------------------------------------------------------------
# Tracing
# ---------------------------------------------------------------------------


def configure() -> None:
    """Install a tracer provider. Safe to call repeatedly; only the first wins."""
    global _tracer, _configured
    with _configure_lock:
        if _configured:
            return
        _configured = True
        try:
            from opentelemetry import trace
            from opentelemetry.sdk.resources import Resource
            from opentelemetry.sdk.trace import TracerProvider
            from opentelemetry.sdk.trace.export import BatchSpanProcessor

            provider = TracerProvider(
                resource=Resource.create(
                    {
                        "service.name": SERVICE_NAME,
                        "service.version": os.environ.get("SERVICE_VERSION", "dev"),
                        "deployment.environment": os.environ.get("ENVIRONMENT", "local"),
                    }
                )
            )

            if OTLP_ENDPOINT:
                from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import (
                    OTLPSpanExporter,
                )

                provider.add_span_processor(
                    BatchSpanProcessor(OTLPSpanExporter(endpoint=OTLP_ENDPOINT))
                )
            if CONSOLE_TRACES:
                from opentelemetry.sdk.trace.export import (
                    ConsoleSpanExporter,
                    SimpleSpanProcessor,
                )

                provider.add_span_processor(SimpleSpanProcessor(ConsoleSpanExporter()))

            trace.set_tracer_provider(provider)
            _tracer = trace.get_tracer(SERVICE_NAME)
        except Exception as exc:  # tracing is optional; the service is not
            print(f"[telemetry] tracing disabled: {exc}")
            _tracer = None


def _span(name: str):
    if _tracer is None:
        configure()
    if _tracer is None:
        return None
    try:
        return _tracer.start_as_current_span(name)
    except Exception:
        return None


class _NullSpan:
    """Stands in when tracing is off, so callers need no branch."""

    def set(self, key: str, value: Any) -> None:  # noqa: D102
        pass

    def error(self, exc: BaseException) -> None:  # noqa: D102
        pass


class _Span:
    def __init__(self, span: Any):
        self._span = span

    def set(self, key: str, value: Any) -> None:
        try:
            if value is not None:
                self._span.set_attribute(key, value)
        except Exception:
            pass

    def error(self, exc: BaseException) -> None:
        try:
            from opentelemetry.trace import Status, StatusCode

            self._span.record_exception(exc)
            self._span.set_status(Status(StatusCode.ERROR, str(exc)))
        except Exception:
            pass


@contextmanager
def turn_span(
    operation: str,
    company_id: Optional[str] = None,
    question: Optional[str] = None,
    **attrs: Any,
) -> Iterator[Any]:
    """Wrap one assistant turn.

    Yields a small handle rather than the raw span so the call sites stay clean
    and so a tracing-disabled process runs the same code path.
    """
    ctx = _span(f"agent.{operation}")
    started = time.perf_counter()
    if ctx is None:
        handle: Any = _NullSpan()
        try:
            yield handle
        finally:
            metrics.observe(f"agent.{operation}", (time.perf_counter() - started) * 1000)
        return

    with ctx as raw:
        handle = _Span(raw)
        handle.set("gen_ai.operation.name", operation)
        handle.set("gen_ai.system", os.environ.get("GEN_AI_SYSTEM", "gcp.gemini"))
        handle.set("inventory.tenant", tenant_digest(company_id))
        if question and CAPTURE_PROMPTS:
            handle.set("gen_ai.prompt", question[:2000])
        for key, value in attrs.items():
            handle.set(key, value)
        try:
            yield handle
        except Exception as exc:
            handle.error(exc)
            metrics.increment(f"agent.{operation}.errors")
            raise
        finally:
            elapsed_ms = (time.perf_counter() - started) * 1000
            handle.set("duration_ms", round(elapsed_ms, 2))
            metrics.observe(f"agent.{operation}", elapsed_ms)


def record_turn(handle: Any, state: Dict[str, Any], usage_delta: Dict[str, int]) -> None:
    """Stamp a finished turn onto its span, and count it.

    The interesting attributes are the routing ones. Latency tells you a turn
    was slow; ``route_source`` and ``answered_by`` tell you *why* — a question
    that used to be served from the deterministic bank and is now going to the
    model shows up here long before it shows up on the bill.
    """
    try:
        intent = str(state.get("intent") or "unknown")
        answered_by = str(state.get("answered_by") or "unknown")
        route_source = str(state.get("route_source") or "unknown")
        tier = "agent"
        inp = int(usage_delta.get("input_tokens", 0))
        out = int(usage_delta.get("output_tokens", 0))
        calls = int(usage_delta.get("calls", 0))

        handle.set("agent.intent", intent)
        handle.set("agent.answered_by", answered_by)
        handle.set("agent.route_source", route_source)
        handle.set("agent.response_kind", str(state.get("response_kind") or "prose"))
        handle.set("agent.llm_calls", calls)
        handle.set("gen_ai.usage.input_tokens", inp)
        handle.set("gen_ai.usage.output_tokens", out)
        handle.set("agent.executed_actions", len(state.get("executed_actions") or []))
        handle.set("agent.cost_usd", cost_usd(tier, inp, out))

        metrics.increment("agent.turns")
        metrics.increment(f"agent.intent.{intent.lower()}")
        metrics.increment(f"agent.answered_by.{answered_by.lower()}")
        metrics.add("agent.tokens.input", inp)
        metrics.add("agent.tokens.output", out)
        metrics.add_float("agent.cost_usd", cost_usd(tier, inp, out))
        if calls == 0:
            metrics.increment("agent.zero_token_turns")
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------


class Metrics:
    """In-process counters and latency buckets, rendered for Prometheus.

    Deliberately not the ``prometheus_client`` library: this needs four
    primitives, the service already ships a slim image, and a scrape endpoint is
    thirty lines. Per-instance, like the rate limiter — Prometheus aggregates
    across instances, which is where that sum belongs anyway.
    """

    _BUCKETS_MS = (5, 25, 100, 250, 500, 1000, 2500, 5000, 10000)

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._counters: Dict[str, int] = defaultdict(int)
        self._floats: Dict[str, float] = defaultdict(float)
        self._hist: Dict[str, Dict[str, Any]] = {}

    def increment(self, name: str, by: int = 1) -> None:
        with self._lock:
            self._counters[name] += by

    def add(self, name: str, value: int) -> None:
        self.increment(name, int(value))

    def add_float(self, name: str, value: float) -> None:
        with self._lock:
            self._floats[name] += float(value)

    def observe(self, name: str, millis: float) -> None:
        with self._lock:
            h = self._hist.setdefault(
                name, {"count": 0, "sum": 0.0, "buckets": defaultdict(int)}
            )
            h["count"] += 1
            h["sum"] += millis
            for edge in self._BUCKETS_MS:
                if millis <= edge:
                    h["buckets"][edge] += 1

    def snapshot(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "counters": dict(self._counters),
                "totals": {k: round(v, 6) for k, v in self._floats.items()},
                "latency_ms": {
                    name: {
                        "count": h["count"],
                        "sum": round(h["sum"], 2),
                        "avg": round(h["sum"] / h["count"], 2) if h["count"] else 0.0,
                    }
                    for name, h in self._hist.items()
                },
            }

    def render_prometheus(self) -> str:
        """Text exposition format, so a stock Prometheus scrape just works."""
        out = []
        with self._lock:
            for name, value in sorted(self._counters.items()):
                metric = _safe_metric(name) + "_total"
                out.append(f"# TYPE {metric} counter")
                out.append(f"{metric} {value}")
            for name, value in sorted(self._floats.items()):
                metric = _safe_metric(name)
                out.append(f"# TYPE {metric} counter")
                out.append(f"{metric} {value:.6f}")
            for name, h in sorted(self._hist.items()):
                metric = _safe_metric(name) + "_duration_ms"
                out.append(f"# TYPE {metric} histogram")
                cumulative = 0
                for edge in self._BUCKETS_MS:
                    cumulative = h["buckets"].get(edge, 0)
                    out.append(f'{metric}_bucket{{le="{edge}"}} {cumulative}')
                out.append(f'{metric}_bucket{{le="+Inf"}} {h["count"]}')
                out.append(f"{metric}_sum {h['sum']:.2f}")
                out.append(f"{metric}_count {h['count']}")
        return "\n".join(out) + "\n"


def _safe_metric(name: str) -> str:
    return "".join(c if c.isalnum() else "_" for c in name).strip("_").lower()


metrics = Metrics()


# ---------------------------------------------------------------------------
# Structured logging
# ---------------------------------------------------------------------------


def log(event: str, **fields: Any) -> None:
    """One JSON object per line, with the trace id already in it.

    Cloud Run's log viewer, and every log backend after it, parses JSON lines
    into queryable fields. Carrying ``trace_id`` means a slow turn found on a
    dashboard opens straight onto its log lines.
    """
    payload: Dict[str, Any] = {"event": event, "ts": round(time.time(), 3)}
    try:
        from opentelemetry import trace

        span = trace.get_current_span()
        ctx = span.get_span_context() if span else None
        if ctx and getattr(ctx, "trace_id", 0):
            payload["trace_id"] = format(ctx.trace_id, "032x")
            payload["span_id"] = format(ctx.span_id, "016x")
    except Exception:
        pass
    payload.update(fields)
    try:
        print(json.dumps(payload, default=str))
    except Exception:
        print(json.dumps({"event": event, "error": "unserialisable log fields"}))
