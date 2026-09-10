"""Runs golden cases against the real compiled graph.

Not against a stub of it. The point of the harness is to catch the pipeline
changing its mind, so it calls ``rag_pipeline.ainvoke`` exactly as
``/api/chat`` does — same state shape, same permission set, same fact layer.

What it deliberately does *not* go through is the HTTP answer cache. A cached
turn is a turn the graph never ran, and grading those would let a broken agent
pass on yesterday's answers.
"""

from __future__ import annotations

import asyncio
import contextlib
import os
import time
import uuid
from typing import Any, Dict, List, Optional

os.environ.setdefault("OFFLINE_MODE", "1")

from . import catalogs
from .dataset import Case, allow_llm, load_suites
from .fake_llm import scripted
from .scorers import BUDGET_SCORERS, SCORERS, ScoreCard

EVAL_COMPANY = "eval_company"


def _seed(catalog_name: str):
    """Replace the offline catalog and return facts read straight back."""
    from facts import fact_store
    from inventory_db import db_instance

    db_instance.replace_user_inventory(
        catalogs.catalog(catalog_name), company_id=EVAL_COMPANY
    )
    fact_store.bump(EVAL_COMPANY)
    return fact_store.get(EVAL_COMPANY, force=True)


def _permissions(case: Case) -> Optional[set]:
    """Which of the three caller shapes this case is about.

    ``unreadable_grants`` -> ``None``, the fail-closed state.
    ``permissions: []``   -> a member holding nothing.
    anything else         -> exactly those grants, or admin when unstated.

    Keeping "no grants" and "grants unknown" apart matters because the graph
    treats them differently on purpose, and collapsing them would let the
    fail-closed branch rot untested.
    """
    if case.unreadable_grants:
        return None
    if case.permissions is None:
        return {"*"}
    return set(case.permissions)


def _usage_snapshot() -> Dict[str, int]:
    import llm as llm_factory

    snap = llm_factory.usage.snapshot()
    return {
        "calls": int(snap.get("total_calls", 0)),
        "input_tokens": int(snap.get("total_input_tokens", 0)),
        "output_tokens": int(snap.get("total_output_tokens", 0)),
    }


async def _walk_turns(case: Case, session_id: str, permissions) -> Dict[str, Any]:
    """Play every turn of the case in one session and return the final state."""
    from facts import fact_store
    from graph import rag_pipeline

    history: List[Dict[str, str]] = list(case.history)
    state: Dict[str, Any] = {}
    for turn in case.turns:
        state = await rag_pipeline.ainvoke(
            {
                "question": turn,
                "retries": 0,
                "provided_context": None,
                "history": list(history),
                "company_id": EVAL_COMPANY,
                "business_type": "retail_store",
                "session_id": session_id,
                "permissions": permissions,
                # Re-read each turn: an earlier turn in the same case may have
                # moved stock, and the next turn has to see that.
                "facts": fact_store.get(EVAL_COMPANY, force=True),
            }
        )
        history.append({"role": "user", "content": turn})
        history.append({"role": "assistant", "content": state.get("generation") or ""})
    return state


async def run_case(case: Case) -> ScoreCard:
    card = ScoreCard(case_id=case.qualified_id)

    if case.requires_llm and not allow_llm():
        card.skipped = "needs a live model; set EVAL_ALLOW_LLM=1"
        return card

    from facts import fact_store
    from pending import pending_actions

    _seed(case.catalog)

    # A fresh session per case: pending actions are keyed by session, and a
    # shared one would let a preview from an earlier case be confirmed by a
    # later "yes".
    session_id = case.session_id or f"eval:{uuid.uuid4().hex[:12]}"
    pending_actions.clear(EVAL_COMPANY, session_id)
    permissions = _permissions(case)

    # A scripted case replays fixed model turns; an unscripted one uses whatever
    # provider the factory finds — in CI that is none, which is fine, because
    # the read path never asks for one.
    scripting = (
        scripted(case.script, case.router_reply)
        if case.script is not None
        else contextlib.nullcontext()
    )

    before = _usage_snapshot()
    started = time.perf_counter()
    try:
        with scripting:
            state = await _walk_turns(case, session_id, permissions)
    except Exception as exc:  # a crash is a failing case, not a broken run
        card.error = f"{type(exc).__name__}: {exc}"
        card.latency_ms = (time.perf_counter() - started) * 1000
        return card
    card.latency_ms = (time.perf_counter() - started) * 1000
    after = _usage_snapshot()

    card.llm_calls = max(0, after["calls"] - before["calls"])
    card.input_tokens = max(0, after["input_tokens"] - before["input_tokens"])
    card.output_tokens = max(0, after["output_tokens"] - before["output_tokens"])
    card.answered_by = state.get("answered_by", "") or ""
    card.intent = state.get("intent", "") or ""

    # Facts are re-read after the turn so a case that legitimately writes is
    # graded against the inventory as it now stands.
    graded_facts = fact_store.get(EVAL_COMPANY, force=True)

    for scorer in SCORERS:
        check = scorer(case, state, graded_facts)
        if check is not None:
            card.checks.append(check)

    latency_check = BUDGET_SCORERS[0](
        case, state, graded_facts, latency_ms=card.latency_ms
    )
    if latency_check is not None:
        card.checks.append(latency_check)
    calls_check = BUDGET_SCORERS[1](
        case, state, graded_facts, llm_calls=card.llm_calls
    )
    if calls_check is not None:
        card.checks.append(calls_check)

    return card


async def run_suite(cases: List[Case]) -> List[ScoreCard]:
    # Sequential on purpose. The offline store and the pending-action registry
    # are process-global; running cases concurrently would have them seeding
    # over each other and produce flaky results that look like agent bugs.
    return [await run_case(case) for case in cases]


async def run_all(only: Optional[List[str]] = None) -> Dict[str, List[ScoreCard]]:
    suites = load_suites(only)
    return {name: await run_suite(cases) for name, cases in suites.items()}


