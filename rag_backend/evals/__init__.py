"""Offline evaluation harness for the inventory agent.

The agent is graded the way the app is: against seeded inventory whose every
number is known ahead of time, so a regression shows up as a failed assertion
rather than as a plausible-sounding wrong answer.

Nothing here calls a paid model by default. The pipeline answers most of the
golden set from the deterministic bank and the regex router at zero tokens, and
that coverage is itself a headline metric — when it falls, cost has risen.
Set ``EVAL_ALLOW_LLM=1`` to grade the full model path as well.
"""

from .dataset import Case, Expectation, load_suites
from .runner import run_case, run_suite, run_all
from .scorers import SCORERS, ScoreCard

__all__ = [
    "Case",
    "Expectation",
    "load_suites",
    "run_case",
    "run_suite",
    "run_all",
    "SCORERS",
    "ScoreCard",
]
