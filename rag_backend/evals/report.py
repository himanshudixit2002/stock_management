"""Turns score cards into something a person and a CI job can both read.

The headline is not the pass rate. A suite that passes is the floor, not the
news. The two numbers worth watching over time are **deterministic coverage**
— what share of the golden set was answered without a model — and the token
spend behind the rest, because those are what silently regress when someone
routes one more question through the agent for convenience.
"""

from __future__ import annotations

import json
from dataclasses import asdict
from typing import Any, Dict, List

from .scorers import ScoreCard


def summarise(results: Dict[str, List[ScoreCard]]) -> Dict[str, Any]:
    cards = [c for cards in results.values() for c in cards]
    graded = [c for c in cards if not c.skipped]
    passed = [c for c in graded if c.passed]
    zero_token = [c for c in graded if c.zero_token]
    latencies = sorted(c.latency_ms for c in graded) or [0.0]

    return {
        "cases": len(cards),
        "graded": len(graded),
        "skipped": len(cards) - len(graded),
        "passed": len(passed),
        "failed": len(graded) - len(passed),
        "pass_rate_pct": round(100 * len(passed) / len(graded), 1) if graded else 0.0,
        # The cost metric. Every point lost here is a question that used to be
        # free and now is not.
        "deterministic_coverage_pct": (
            round(100 * len(zero_token) / len(graded), 1) if graded else 0.0
        ),
        "llm_calls": sum(c.llm_calls for c in graded),
        "input_tokens": sum(c.input_tokens for c in graded),
        "output_tokens": sum(c.output_tokens for c in graded),
        "latency_p50_ms": round(latencies[len(latencies) // 2], 1),
        "latency_p95_ms": round(latencies[max(0, int(len(latencies) * 0.95) - 1)], 1),
        "by_suite": {
            name: {
                "cases": len(cards_),
                "passed": sum(1 for c in cards_ if c.passed and not c.skipped),
                "failed": sum(1 for c in cards_ if not c.passed),
                "skipped": sum(1 for c in cards_ if c.skipped),
            }
            for name, cards_ in results.items()
        },
    }


def to_json(results: Dict[str, List[ScoreCard]]) -> str:
    return json.dumps(
        {
            "summary": summarise(results),
            "results": {
                name: [asdict(c) for c in cards] for name, cards in results.items()
            },
        },
        indent=2,
        default=str,
    )


def to_text(results: Dict[str, List[ScoreCard]], verbose: bool = False) -> str:
    lines: List[str] = []
    for name, cards in results.items():
        lines.append(f"\n{name}")
        lines.append("-" * (len(name) + 2))
        for card in cards:
            if card.skipped:
                lines.append(f"  SKIP  {card.case_id}  ({card.skipped})")
                continue
            mark = "pass" if card.passed else "FAIL"
            cost = "free" if card.zero_token else f"{card.llm_calls} call(s)"
            lines.append(
                f"  {mark}  {card.case_id}  "
                f"[{card.intent or '-'}/{card.answered_by or '-'}, "
                f"{card.latency_ms:.0f}ms, {cost}]"
            )
            if card.error:
                lines.append(f"          error: {card.error}")
            for check in card.checks if verbose else card.failures:
                lines.append(f"          {check}")

    s = summarise(results)
    lines.append("\n" + "=" * 72)
    lines.append(
        f"{s['passed']}/{s['graded']} passed ({s['pass_rate_pct']}%)"
        + (f", {s['skipped']} skipped" if s["skipped"] else "")
    )
    zero = sum(1 for cards in results.values() for c in cards if not c.skipped and c.zero_token)
    lines.append(
        f"deterministic coverage {s['deterministic_coverage_pct']}% "
        f"({zero} of {s['graded']} cases answered with no model call)"
    )
    lines.append(
        f"tokens in/out {s['input_tokens']}/{s['output_tokens']}, "
        f"latency p50 {s['latency_p50_ms']}ms p95 {s['latency_p95_ms']}ms"
    )
    return "\n".join(lines)
