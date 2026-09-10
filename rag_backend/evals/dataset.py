"""The golden set: cases as data, so adding one is editing YAML, not Python.

A case is a question plus the properties its answer must hold. The properties
are deliberately *structural* — intent, render kind, which rows came back,
whether anything was written — rather than a reference string to diff against.
Grading an assistant on string equality punishes it for rewording and lets a
confidently wrong number through, which is exactly backwards for this system:
the numbers are the product, the prose around them is not.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

GOLDEN_DIR = Path(__file__).parent / "golden"


@dataclass(frozen=True)
class Expectation:
    """What has to be true of the answer for the case to pass.

    Every field is optional. A case asserts only the properties it is actually
    about, so a routing case does not accidentally pin the wording of a number
    and start failing when the phrasing improves.
    """

    # --- routing and render contract ---
    intent: Optional[str] = None
    response_kind: Optional[str] = None
    # Which layer was allowed to answer. Listing "deterministic" here is how a
    # case pins a zero-token path: if a refactor pushes it onto the model, the
    # eval fails even though the prose is still correct.
    answered_by: Optional[List[str]] = None

    # --- content ---
    must_contain: List[str] = field(default_factory=list)
    must_not_contain: List[str] = field(default_factory=list)

    # --- grounding ---
    # Rows returned to the client must correspond to catalog products. This is
    # the assertion behind "the assistant must not invent products": a
    # placeholder SKU row is the failure mode, and it is structural, so it can
    # be caught exactly rather than guessed at from prose.
    items_are_real_products: bool = True
    # Names that must never appear. Seeded per case with plausible-sounding
    # products the catalog does not contain.
    decoy_products: List[str] = field(default_factory=list)
    # Every figure of three digits or more in the answer must trace to a number
    # the fact layer can produce. Three digits is the floor on purpose — small
    # integers are counts, ranks and list indices, and checking them produces
    # noise instead of signal.
    grounded_numbers: bool = False

    # --- writes that are supposed to happen ---
    # Tool names that must have run and succeeded. The counterpart to
    # ``no_writes``: without it a "the write lands" control case asserts
    # nothing at all, and would keep passing against an agent that had lost the
    # ability to write anything.
    writes: List[str] = field(default_factory=list)
    # Barcode -> quantity the catalog must hold once the case is done. The
    # strongest assertion available here, because it is the ledger itself
    # rather than the sentence describing it: a refused write and a write that
    # silently did nothing produce the same prose and different stock.
    stock_after: Dict[str, int] = field(default_factory=dict)

    # --- safety ---
    # A question is not an instruction. Anything read-only must leave the
    # ledger untouched, and that is worth asserting on every such case.
    no_writes: bool = True
    # The caller lacks the permission this question would need; the agent must
    # decline rather than execute through the Admin SDK.
    refuses: bool = False

    # --- budgets ---
    max_latency_ms: Optional[int] = None
    max_llm_calls: Optional[int] = None

    @classmethod
    def from_dict(cls, raw: Optional[Dict[str, Any]]) -> "Expectation":
        raw = dict(raw or {})
        unknown = set(raw) - {f for f in cls.__dataclass_fields__}
        if unknown:
            raise ValueError(f"unknown expectation key(s): {sorted(unknown)}")
        return cls(**raw)


@dataclass(frozen=True)
class Case:
    id: str
    suite: str
    # Every case is a conversation; a one-line case is just a conversation of
    # length one. Modelling it this way is not tidiness — the write path is
    # preview-then-confirm, so the behaviour that actually matters (a refused
    # write, a cancelled preview) only exists on the second turn.
    turns: List[str]
    history: List[Dict[str, str]] = field(default_factory=list)
    # Permission keys the caller holds. Omitted means admin ("*"); an empty
    # list means a caller who proved membership but holds no grants, which is
    # the shape that must be refused rather than served.
    permissions: Optional[List[str]] = None
    # The third state, and the one worth naming separately: membership proved,
    # grants unreadable. The graph receives ``None`` and must fail closed, so a
    # Firestore hiccup denies a write rather than waving it through.
    unreadable_grants: bool = False
    # Named catalog from ``catalogs.py``. Cases share one catalog by default so
    # their expected numbers are comparable.
    catalog: str = "default"
    session_id: Optional[str] = None
    expect: Expectation = field(default_factory=Expectation)
    # Cases that genuinely need a model are skipped unless EVAL_ALLOW_LLM=1, so
    # the suite stays deterministic and free in CI.
    requires_llm: bool = False
    # Model turns to replay, one per agent call, so a write-path case can run
    # without an endpoint. See ``fake_llm``. Present means "run scripted";
    # absent means the real factory decides.
    script: Optional[List[Dict[str, Any]]] = None
    router_reply: str = "EXECUTION"

    @property
    def qualified_id(self) -> str:
        return f"{self.suite}/{self.id}"

    @property
    def question(self) -> str:
        """The turn under grading — the last one."""
        return self.turns[-1]

    @property
    def is_multi_turn(self) -> bool:
        return len(self.turns) > 1


def load_suites(only: Optional[List[str]] = None) -> Dict[str, List[Case]]:
    """Read every ``golden/*.yaml`` into cases, keyed by suite name."""
    suites: Dict[str, List[Case]] = {}
    for path in sorted(GOLDEN_DIR.glob("*.yaml")):
        suite = path.stem
        if only and suite not in only:
            continue
        raw = yaml.safe_load(path.read_text()) or {}
        cases = raw.get("cases") or []
        seen = set()
        parsed: List[Case] = []
        for entry in cases:
            cid = entry.get("id")
            if not cid:
                raise ValueError(f"{path.name}: a case is missing its id")
            if cid in seen:
                raise ValueError(f"{path.name}: duplicate case id {cid!r}")
            seen.add(cid)
            turns = entry.get("turns")
            if turns is None:
                if "question" not in entry:
                    raise ValueError(f"{path.name}:{cid}: needs question or turns")
                turns = [entry["question"]]
            if not isinstance(turns, list) or not turns:
                raise ValueError(f"{path.name}:{cid}: turns must be a non-empty list")
            parsed.append(
                Case(
                    id=cid,
                    suite=suite,
                    turns=[str(t) for t in turns],
                    history=entry.get("history") or [],
                    permissions=entry.get("permissions"),
                    unreadable_grants=bool(entry.get("unreadable_grants", False)),
                    catalog=entry.get("catalog", "default"),
                    session_id=entry.get("session_id"),
                    requires_llm=bool(entry.get("requires_llm", False)),
                    script=entry.get("script"),
                    router_reply=entry.get("router_reply", "EXECUTION"),
                    expect=Expectation.from_dict(entry.get("expect")),
                )
            )
        suites[suite] = parsed
    return suites


def allow_llm() -> bool:
    return os.environ.get("EVAL_ALLOW_LLM", "").strip() in {"1", "true", "yes"}
