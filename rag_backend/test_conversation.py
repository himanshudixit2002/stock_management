"""The assistant has to answer the person, not just the query.

Every case here is taken from one real transcript that went badly:

    You: how can i grow my business and what items should i buy that are
         trending in market
    AI:  <growth plan, never mentions the market>
    You: can you chexk with real market trend
    AI:  <inventory snapshot>
    You: are you dumb
    AI:  <the same inventory snapshot>

Three separate failures: a question half-answered, an out-of-scope question
answered with unrelated data, and a complaint answered by repeating the
rejected reply. None of them needs a model to get right.
"""

import asyncio
import sys

sys.path.insert(0, ".")

import testkit  # sets OFFLINE_MODE

import conversation
import deterministic
import verify
from nodes import router_node

CID = testkit.TEST_COMPANY

_failures = []


def check(label, actual, expected):
    ok = actual == expected
    if not ok:
        _failures.append(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}: {actual!r}")


def contains(label, haystack, needle):
    ok = needle.lower() in (haystack or "").lower()
    if not ok:
        _failures.append(f"{label}: {needle!r} missing")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")


def excludes(label, haystack, needle):
    ok = needle.lower() not in (haystack or "").lower()
    if not ok:
        _failures.append(f"{label}: {needle!r} should not be there")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")


facts = testkit.seed()


def ask(question, history=None):
    return deterministic.answer(question, facts, CID, "retail_store", history=history)



print("\n== Normal conversation is answered, not routed to a stock table ==")
# Every one of these used to fall through the answer bank, reach a model with
# nothing to add, and land on `_summary(facts)` — the inventory metrics table.
# Four different questions, four identical tables.
CONVERSATION = {
    "greeting": ("hi", "hello", "hey", "good morning", "how are you", "what's up"),
    "capability": (
        "what can you do", "how can you help me", "how can you help",
        "what are you capable of", "what are your features", "who are you",
        "help me", "i need help", "what should i ask", "why should i use you",
        "what is this", "give me examples",
    ),
    "identity": (
        "are you a bot", "are you human", "who made you", "what model are you",
        "who built this",
    ),
    "trust": ("how do you work", "can i trust these numbers", "do you make things up"),
    "thanks": ("thanks", "thank you", "perfect", "nice work"),
    "goodbye": ("bye", "that's all", "good night"),
    "confused": ("i don't understand", "what do you mean", "explain that", "huh", "what"),
    "smalltalk": ("tell me a joke", "what's your name", "do you sleep"),
    "advice": ("what should i do", "any advice", "where should i start"),
    "external": ("what are the item should i buy accornding to the market trends",),
    "complaint": ("are you dumb", "this is useless", "same answer? are you dumb"),
}

covered = 0
for group, questions in CONVERSATION.items():
    for question in questions:
        reply = ask(question)
        if reply is None:
            _failures.append(f"{group}: {question!r} was not answered at all")
            print(f"  FAIL  {group}: {question!r} fell through")
            continue
        if "| Metric | Value |" in reply.text or "Cost basis" in reply.text:
            _failures.append(f"{group}: {question!r} answered with the metrics table")
            print(f"  FAIL  {group}: {question!r} got the stock dump")
            continue
        covered += 1
print(f"  PASS  {covered} conversational turns answered, none with a metrics table")


print("\n== A bare 'what' is confusion; 'what is low stock' is a question ==")
# These markers are matched on the whole message. As substrings they swallowed
# every "what ..." question in the app.
for question, confused in (
    ("what", True),
    ("huh", True),
    ("what is low stock", False),
    ("what should i order next", False),
    ("what runs out first", False),
):
    reply = ask(question)
    got = reply is not None and "let me try again in plainer terms" in reply.text
    check(f"{question!r}", got, confused)


print("\n== Even a greeting says something true about this shop ==")
hello = ask("hi")
named = [p.name for p in facts.products if p.name in hello.text]
check("names a real product from this catalog", bool(named), True)
contains("and offers a next step", hello.text, "order")
excludes("no metrics table", hello.text, "| Metric | Value |")


print("\n== It can say what it is, and why it can be trusted ==")
bot = ask("are you a bot")
contains("admits it's software", bot.text, "software, not a person")
excludes("does not pretend to be human", bot.text, "I am human")

trust = ask("can i trust these numbers")
contains("says where the numbers come from", trust.text, "read from your live inventory")
contains("names its own weakness", trust.text, "only be as good as what's recorded")
contains("and the confirm-first promise", trust.text, "wait for a yes")


print("\n== 'Help me X' is a request about X, not a request for the menu ==")
for question, is_menu in (
    ("help me", True),
    ("i need help", True),
    ("help me find gauze pads", False),
    ("help me understand my dead stock", False),
):
    reply = ask(question)
    menu = reply is not None and "| What I do |" in reply.text
    check(f"{question!r}", menu, is_menu)


print("\n== Not understanding is something you say, not a table ==")
lost = conversation.fallback("asdkjhasd qwe zxc", facts)
contains("admits it plainly", lost, "didn't quite catch")
contains("still grounded in real counts", lost, "products")
contains("and asks for another try", lost, "another way")
excludes("never the metrics table", lost, "| Metric | Value |")
excludes("and never a cost basis dump", lost, "Cost basis")

# The same three unanswerable turns in a row must not read identically.
variants = {
    conversation.fallback("zzz", facts, [{"role": "user", "content": "x"}] * n)
    for n in (0, 2, 4)
}
check("consecutive fallbacks differ", len(variants), 3)


print("\n== No path in the graph answers with the metrics table any more ==")
import nodes as _nodes
import inspect

source = inspect.getsource(_nodes)
check("no _summary fallback left", "deterministic._summary(facts)" in source, False)

print("\n== A good answer is never thrown away for saying 'SKUs' ==")
# The placeholder guard matched the plain word "SKUs" and the phrase "the item
# I would reorder", so real answers were replaced by a stock summary — and the
# replacement announced itself to the user.
for text in (
    "Growth plan for your **200 SKUs** (**872,037.58** retail value)",
    "Personalized Watch is the item I would reorder first.",
    "Every product I stock in Watches is moving slowly.",
    "Part 2 of the plan: tighten reorder points.",
):
    flagged = any(i.kind == "placeholder" for i in verify.check_answer(text, facts)[1])
    check(f"kept: {text[:40]!r}", flagged, False)

for text in ("| SKU 1 | 20 |\n| SKU 2 | 5 |", "Restock <product name> this week."):
    flagged = any(i.kind == "placeholder" for i in verify.check_answer(text, facts)[1])
    check(f"caught: {text[:28]!r}", flagged, True)


print("\n== The machinery never explains itself to the user ==")
from nodes import _real_data_answer

replacement = _real_data_answer("anything", facts, CID, {"business_type": "retail_store"})
excludes("no mention of a dropped draft", replacement, "dropped my first draft")
excludes("no apology for its own internals", replacement, "first draft")


print("\n== Asked only about the outside world, it says so ==")
out = ask("can you chexk with real market trend")
contains("admits it plainly", out.text, "can't see market trends")
contains("says why", out.text, "no market data")
contains("offers what it can do instead", out.text, "your own")
excludes("does not dump a stock table", out.text, "| Metric | Value |")
check("and it is prose, not a report", out.kind, "prose")


print("\n== A two-part question gets both parts answered ==")
mixed = ask(
    "tell me how can i grow my business and what are the items i have to buy "
    "which are trending in market"
)
contains("answers the growth half", mixed.text, "growth")
contains("names a real product", mixed.text, "Fresh Apples")
contains("and addresses the market half", mixed.text, "on market trends")
contains("rather than ignoring it", mixed.text, "no outside feed")


print("\n== Being told the answer was bad changes the answer ==")
annoyed = ask("are you dumb")
contains("owns it", annoyed.text, "wasn't the answer you asked for")
contains("offers something concrete", annoyed.text, "what's running low")
excludes("does not reprint the snapshot", annoyed.text, "Cost basis")

# The complaint that carries the real question gets the real answer.
pointed = ask("be more advanced understand my question how can i grow my business with market trend")
contains("names what went wrong", pointed.text, "market trends")
contains("explains the limit", pointed.text, "can't see outside your shop")


print("\n== The same question twice does not get the same wall of text ==")
first = ask("what can you do")
history = [
    {"role": "user", "content": "what can you do"},
    {"role": "model", "content": first.text},
]
second = ask("what are you capability and you can gelp me to grow my business", history)
check("the first time it lists what it does", "| What I do |" in first.text, True)
check("the second time it asks instead", "| What I do |" in second.text, False)
contains("and asks what they actually want", second.text, "what are you actually trying to get done")

grow_first = ask("how can i grow my business")
grow_history = [
    {"role": "user", "content": "how can i grow my business"},
    {"role": "model", "content": grow_first.text},
]
grow_again = ask("how can i grow my business", grow_history)
contains("a repeat leads with the action", grow_again.text, "rather than list them again")
contains("and offers to do it", grow_again.text, "draft all")


print("\n== It admits it has no window on the outside world, up front ==")
contains("the capability card says so", first.text, "not**: a window on the outside world")


print("\n== A complaint about the data is not a complaint about me ==")
# "My dead stock is terrible" is a question about stock, not an insult.
for question, frustrated in (
    ("are you dumb", True),
    ("this is useless", True),
    ("my dead stock situation is terrible and i need to clear it", False),
    ("which products have terrible margins", False),
):
    check(f"{question[:44]!r}", deterministic.is_frustrated(question), frustrated)


print("\n== Neither case burns a model call to get there ==")
for question in ("are you dumb", "what's trending in the market right now"):
    state = asyncio.run(
        router_node({"question": question, "company_id": CID, "session_id": "s"})
    )
    check(f"routed by rule: {question[:32]!r}", state.get("route_source"), "regex")


print("\n" + "=" * 60)
if _failures:
    print(f"{len(_failures)} FAILURE(S):")
    for f in _failures:
        print(" -", f)
    sys.exit(1)
print("All conversation tests passed.")
