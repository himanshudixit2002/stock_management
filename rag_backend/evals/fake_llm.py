"""A scripted stand-in for the model, so the write path can be graded in CI.

The read path answers from the deterministic bank at zero tokens, so it grades
itself. The write path does not: every stock change starts with the agent
choosing a tool, and that choice is the model's. Left as-is, the cases that
matter most — a write refused for want of a permission, a preview cancelled
before it lands — could only run against a paid endpoint, which means in
practice they would not run at all.

So the model's *decision* is scripted and everything downstream of it is real.
The tool call is fabricated; the permission check, the resolver, the pending
store, the ledger write and the arithmetic are the shipping code. That is the
half worth testing, and it is the half a mocked-out test usually loses.

The interface is deliberately the narrow one ``nodes.stream_message`` needs:

* ``astream`` yields nothing, which is the documented path back to ``ainvoke``
  (raising instead would be re-raised and land the node in its fallback branch).
* ``ainvoke`` pops the next scripted turn.
* ``bind_tools`` is a no-op — there is no schema to bind to a fixed answer.
"""

from __future__ import annotations

import contextlib
from collections import deque
from typing import Any, Dict, Iterator, List, Optional

from langchain_core.messages import AIMessage


def _tool_call(raw: Dict[str, Any], index: int) -> Dict[str, Any]:
    return {
        "name": raw["name"],
        "args": dict(raw.get("args") or {}),
        "id": raw.get("id") or f"scripted_{index}",
        "type": "tool_call",
    }


class ScriptedLLM:
    """Replays a fixed list of model turns, then stops asking for tools.

    Running off the end of the script is not an error: it returns a plain
    content message, which is how the agent loop is told the model is done. A
    script therefore describes the tool calls a case cares about and stays
    silent about the wrap-up.
    """

    def __init__(
        self,
        script: Optional[List[Dict[str, Any]]] = None,
        tier: str = "agent",
        router_reply: str = "EXECUTION",
        closing_text: str = "Done.",
    ):
        self._queue = deque(script or [])
        self._tier = tier
        self._router_reply = router_reply
        self._closing_text = closing_text
        self.calls: List[str] = []

    # The router asks a different question — one word, no tools — so it is
    # answered separately rather than eating a scripted tool call.
    def _is_router(self) -> bool:
        return self._tier == "router"

    def bind_tools(self, tools: Any) -> "ScriptedLLM":
        return self

    async def astream(self, messages: Any) -> Iterator[Any]:
        # Intentionally empty: `stream_message` treats "no chunks" as its cue to
        # fall through to `ainvoke`.
        return
        yield  # pragma: no cover - makes this an async generator

    async def ainvoke(self, messages: Any = None, **kwargs: Any) -> AIMessage:
        self.calls.append(self._tier)

        if self._is_router():
            return AIMessage(content=self._router_reply)

        if not self._queue:
            return AIMessage(content=self._closing_text)

        turn = self._queue.popleft()
        raw_calls = turn.get("tool_calls") or []
        return AIMessage(
            content=turn.get("content", ""),
            tool_calls=[_tool_call(c, i) for i, c in enumerate(raw_calls)],
        )


@contextlib.contextmanager
def scripted(script: List[Dict[str, Any]], router_reply: str = "EXECUTION"):
    """Serve every ``llm.get_llm`` from one script for the duration of the block.

    Patched at the module attribute because that is how the nodes reach it
    (``llm_factory.get_llm(...)``), so no node needs to know it is under test.
    One ``ScriptedLLM`` is shared across the agent tiers: the queue is the
    conversation, and handing each tier its own copy would let a case replay the
    same tool call twice without noticing.
    """
    import llm as llm_factory

    original = llm_factory.get_llm
    agent = ScriptedLLM(script, tier="agent")
    router = ScriptedLLM(tier="router", router_reply=router_reply)

    def fake_get_llm(tier: str = "agent", temperature: float = 0.0, tools=None):
        return router if tier == "router" else agent

    llm_factory.get_llm = fake_get_llm
    try:
        yield agent
    finally:
        llm_factory.get_llm = original
