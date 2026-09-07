"""Talking, as opposed to querying.

The answer bank in `deterministic.py` is very good at questions that are really
database queries. Everything else — a greeting, "how can you help me", "thanks",
"are you a bot", "I don't understand" — used to fall through it, reach a model
that had nothing useful to add, and land on the same fallback:

    deterministic._summary(facts)

...which is the inventory metrics table. So four different conversational turns
in a row produced four identical tables, and the assistant looked broken. That
default is the single worst thing in the transcript: it answers nothing, it is
the same every time, and it is *confidently* the same every time.

Three rules here:

* **Never a metrics table.** If the assistant did not understand, it says so
  and asks. A wall of numbers is not a way of saying "pardon?".
* **Always grounded.** Even "hello" reports something true about this
  workspace, so the answer could not have come from any other shop.
* **Never word-for-word twice.** Replies rotate on how far into the
  conversation we are, and a repeat of the same intent changes shape.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence

from facts import InventoryFacts


@dataclass
class Reply:
    text: str
    kind: str = "prose"


# ---------------------------------------------------------------------------
# Matching
# ---------------------------------------------------------------------------

def _norm(text: str) -> str:
    return " ".join((text or "").lower().replace("?", " ").replace("!", " ").split())


def _has(q: str, phrases: Sequence[str]) -> bool:
    return any(p in q for p in phrases)


GREETING_EXACT = {
    "hi", "hii", "hiii", "hey", "heya", "hello", "helo", "yo", "sup", "hola",
    "namaste", "hi there", "hello there", "hey there", "good morning",
    "good afternoon", "good evening", "morning", "gm", "greetings", "howdy",
    "hi ai", "hello ai", "hey ai",
}
GREETING_PHRASES = (
    "how are you", "how r u", "how's it going", "hows it going", "what's up",
    "whats up", "you there", "are you there", "you awake",
)

# Deliberately generous. "How can you help me" reaching the fallback instead of
# this list is exactly the bug that produced four identical stock tables.
CAPABILITY_PHRASES = (
    "what can you do", "what can u do", "what do you do", "what are you capable",
    "what are your capabilities", "your capabilities", "capabilities",
    "how can you help", "how can u help", "how do you help", "can you help",
    "what can you help", "how can you assist", "what can you offer",
    "what are your features", "your features", "what features",
    "who are you", "what are you", "tell me about yourself", "about yourself",
    "introduce yourself", "what is this", "what's this app", "whats this app",
    "what should i ask", "what can i ask", "give me examples", "show me examples",
    "examples of what you can do", "what are you for", "why should i use you",
    "what's the point of you", "how are you useful", "use of you", "your job",
    "your purpose",
)

# A bare "help me" is a request for the menu. "Help me find gauze pads" is a
# lookup with manners on it, so these only count on a short message.
CAPABILITY_WEAK = ("help me", "i need help", "need help", "can you help", "help")

IDENTITY_PHRASES = (
    "are you a bot", "are you human", "are you real", "are you ai", "are you an ai",
    "who made you", "who built you", "who built this", "who created you",
    "who developed", "who owns you", "which model",
    "what model", "are you chatgpt", "are you gemini", "are you claude",
    "do you use ai", "are you a robot", "are you a person",
)

HOW_PHRASES = (
    "how do you work", "how does this work", "how do you know", "where do you get",
    "how are you calculating", "how do you calculate", "can i trust", "are you accurate",
    "are you sure", "is this accurate", "is this correct", "how reliable",
    "do you make things up", "do you hallucinate", "is this real data",
)

THANKS_PHRASES = (
    "thank", "thanks", "thx", "ty", "appreciate", "well done", "good job",
    "nice work", "great work", "perfect", "awesome", "brilliant", "helpful",
    "you're the best", "youre the best", "love it", "good bot", "nice one",
)

BYE_PHRASES = (
    "bye", "goodbye", "see you", "see ya", "later", "that's all", "thats all",
    "that is all", "i'm done", "im done", "nothing else", "no more questions",
    "good night", "goodnight", "catch you later",
)

CONFUSED_PHRASES = (
    "i don't understand", "i dont understand", "don't understand",
    "dont understand", "what do you mean", "what does that mean", "confusing",
    "explain that", "explain this", "explain it", "in simple words",
    "simpler", "i'm lost", "im lost", "come again", "say that again",
    "what does this mean", "not clear", "unclear", "makes no sense", "lost me",
)

# Whole-message only. As substrings these would swallow every "what ..."
# question in the app.
CONFUSED_EXACT = {"huh", "what", "eh", "sorry", "wdym", "?", "come again"}

ADVICE_PHRASES = (
    "what should i do", "what do you suggest", "any advice", "give me advice",
    "advise me", "what would you do", "your suggestion", "suggest something",
    "where should i start", "what's my next step", "whats my next step",
    "what next", "help me improve", "make it better", "what's wrong",
    "whats wrong", "anything i should know", "anything wrong",
)

SMALLTALK_PHRASES = (
    "tell me a joke", "joke", "sing", "poem", "who is your favourite",
    "do you sleep", "do you get tired", "are you happy", "do you like",
    "what's your name", "whats your name", "your name", "how old are you",
    "where are you from", "do you have feelings",
)

# Unambiguous: these are aimed at the assistant and nothing else.
_FRUSTRATION_DIRECT = (
    "are you dumb", "you are dumb", "you're dumb", "so dumb", "are you stupid",
    "you are stupid", "you're stupid", "you suck", "you are useless",
    "you're useless", "not helping", "you are not helping", "you're not helping",
    "waste of time", "you don't understand", "you dont understand",
    "you didn't understand", "you didnt understand", "not what i asked",
    "i didn't ask", "i didnt ask", "read my question", "same answer",
    "same thing again", "same reply", "you repeat", "stop repeating",
    "repeating yourself", "be more advanced", "understand my question",
    "answer my question", "wrong answer", "that's not what i meant",
    "thats not what i meant", "you keep giving", "again the same",
)

# Bare complaints. "My dead stock situation is terrible" is a data question,
# not a complaint about me, so these only count when the message is short and
# actually pointed at the assistant.
_FRUSTRATION_VAGUE = (
    "useless", "rubbish", "nonsense", "garbage", "terrible", "this sucks",
    "pointless", "hopeless", "awful",
)
_AIMED_AT_ME = ("you", "your", "this", "that", "it")


def is_frustrated(question: str) -> bool:
    q = _norm(question)
    if _has(q, _FRUSTRATION_DIRECT):
        return True
    if not _has(q, _FRUSTRATION_VAGUE):
        return False
    words = q.split()
    return len(words) <= 8 and any(w.strip(".,") in _AIMED_AT_ME for w in words)


# Things outside this workspace entirely: no feed, no scrape, no browsing.
_EXTERNAL_TOPICS = (
    ("market trends", (
        "market trend", "market trends", "trending", "trend in market", "trends in market",
        "whats trending", "what's trending", "in demand right now", "hot selling",
        "hot in market", "market demand", "popular right now", "viral", "google trend",
        "according to the market", "as per market", "market research", "what sells well",
        "selling well in market", "demand in market",
    )),
    ("competitor and market pricing", (
        "competitor", "competition price", "market price", "market rate",
        "what others charge", "other shops", "amazon price", "flipkart price",
        "cheapest supplier online", "find me a supplier", "wholesale rate online",
    )),
    ("news and outside events", (
        "the news", "weather", "festival calendar", "gst rate", "tax rate",
        "government scheme", "import duty", "stock market", "share price",
    )),
)


def external_topic(question: str) -> Optional[str]:
    """The outside-world thing a question asks for, if any."""
    q = _norm(question)
    for label, phrases in _EXTERNAL_TOPICS:
        if _has(q, phrases):
            return label
    return None


# ---------------------------------------------------------------------------
# Variation
# ---------------------------------------------------------------------------

def _turns(history: Optional[List[Dict[str, str]]]) -> int:
    return len(history or [])


def _pick(options: Sequence[str], history) -> str:
    """Rotate through phrasings so two turns never read identically."""
    return options[_turns(history) // 2 % len(options)]


def said_before(history, marker: str) -> bool:
    """Has the assistant already said this, anywhere in this conversation?

    The whole window is searched, not the last turn or two: the transcript that
    prompted this had the identical capability table printed at turn one and
    again at turn five. The client already caps what it sends, so there is
    nothing to scan past.
    """
    if not history:
        return False
    for turn in history:
        if not isinstance(turn, dict):
            continue
        if turn.get("role") in ("user", "human"):
            continue
        if marker.lower() in str(turn.get("content", "")).lower():
            return True
    return False


# ---------------------------------------------------------------------------
# The one live detail that proves this is their shop
# ---------------------------------------------------------------------------

def _hook(facts: InventoryFacts) -> str:
    """A true, specific sentence about this workspace, right now."""
    s = facts.summary()
    out = facts.out_of_stock
    low = facts.low_stock
    if out:
        name = out[0].name
        return (
            f"Right now **{len(out)}** of your products are at zero — "
            f"**{name}** among them."
        )
    if low:
        name = sorted(low, key=lambda p: p.quantity)[0].name
        return (
            f"Right now **{len(low)}** products are below their threshold, and "
            f"**{name}** is the thinnest."
        )
    if s["total_products"]:
        return (
            f"Right now all **{s['total_products']}** of your products are above "
            f"their thresholds — nothing needs rescuing today."
        )
    return "Your catalog is empty so far, so there's nothing for me to watch yet."


def _next_step(facts: InventoryFacts) -> str:
    """The most useful thing this workspace could do next, as an invitation."""
    s = facts.summary()
    if s["reorder_count"]:
        return (
            f"Try *order what each low stock item needs* — I'll draft all "
            f"**{s['reorder_count']}** purchase orders for you to check before "
            f"anything is sent."
        )
    if s["low_stock_count"]:
        return (
            "Try *restock all low stock items to their minimum* — I'll show you "
            "the whole list before a single number moves."
        )
    if s["history_coverage_pct"] < 25:
        return (
            "The one thing that would unlock the rest: record stock going out as "
            "you sell. Do that for a few weeks and I can tell you what's actually "
            "moving, what's dead, and what to reorder."
        )
    return "Try *what should I order next?* and I'll work from your real burn rate."


# ---------------------------------------------------------------------------
# The replies
# ---------------------------------------------------------------------------

def _greeting(facts: InventoryFacts, business_type: str, history) -> str:
    openers = (
        "Hello. I'm already looking at your shelves.",
        "Hi — good timing, I've got your numbers open.",
        "Hey. Straight to it, then.",
    )
    return (
        f"{_pick(openers, history)}\n\n{_hook(facts)}\n\n{_next_step(facts)}"
    )


def _capabilities(facts: InventoryFacts, business_type: str, history, repeat: bool) -> str:
    s = facts.summary()
    if repeat:
        # They have read the menu and are telling me it didn't help. Asking is
        # more useful than printing it again.
        return (
            "I've already shown you the menu, so let me skip it and just ask: "
            "what are you actually trying to get done?\n\n"
            f"Off the top of my head I could reorder the **{s['reorder_count']}** "
            f"products sitting below their reorder point, top up the "
            f"**{s['low_stock_count']}** running low, or walk you through how "
            f"your **{s['total_products']}** products are organised. Say which — "
            "or just describe the problem in your own words and I'll work the "
            "rest out."
        )

    biz = business_type.replace("_", " ").lower()
    rows = [
        "| **Find anything** | *How many gauze pads do I have?* |",
        "| **Change one product** | *Add 50 units of Cannula 18G* |",
        "| **Change hundreds at once** | *Add 10 units to every low stock item* |",
        "| **Top everything back up** | *Restock all low stock items to their minimum* |",
        "| **Order what's needed** | *Order what each low stock item needs* |",
        "| **See what's at risk** | *What runs out first?* |",
        "| **Find trapped cash** | *What isn't selling?* |",
        "| **Audit the whole shop** | *Run an inventory audit* |",
        "| **Explain your setup** | *How is my inventory configured?* |",
    ]
    return (
        f"I'm **Ask AI** — I keep an eye on the {biz} side of things with you. "
        f"I can read all **{s['total_products']}** of your products and, with your "
        f"say-so, change them.\n\n"
        + _table(["What I do", "Just say"], rows)
        + f"\n\n{_hook(facts)}\n\n"
        "Two things I'm **not**: a window on the outside world (no market trends, "
        "no competitor prices, no web), and a guesser — every number above comes "
        "from your live stock, and I'd rather ask than invent one."
    )


def _identity(facts: InventoryFacts, history) -> str:
    openers = (
        "Yes — I'm software, not a person.",
        "Bot, through and through.",
    )
    return (
        f"{_pick(openers, history)} I'm the assistant built into this app: a "
        "language model wired directly to your inventory, so I can look things up "
        "and make changes you approve.\n\n"
        "The useful part isn't the model — it's that I'm not guessing. I read your "
        "actual products and transactions, and I check my own answers against them "
        "before you see them.\n\n"
        f"{_next_step(facts)}"
    )


def _how_it_works(facts: InventoryFacts, history) -> str:
    s = facts.summary()
    coverage = s["history_coverage_pct"]
    return (
        "Fair question — here's the honest version.\n\n"
        f"Every figure I give you is read from your live inventory: "
        f"**{s['total_products']}** products and the stock movements recorded "
        f"against them over the last **{facts.window_days}** days. Nothing is "
        "estimated and nothing comes from outside your workspace. The counts I "
        "report are the same ones your Reports screen shows — if they ever "
        "disagree, trust the screen and tell me.\n\n"
        "Where I'm weak: I can only be as good as what's recorded. "
        f"Right now **{coverage}%** of your catalog has any movement history, so "
        + (
            "demand, burn rate and dead stock are real numbers I can stand behind."
            if coverage >= 25
            else "I can tell you what you *hold*, but not yet what *sells*."
        )
        + "\n\nAnd before I change anything, I show you exactly what will change "
        "and wait for a yes."
    )


def _thanks(facts: InventoryFacts, history) -> str:
    return _pick(
        (
            f"Any time. {_next_step(facts)}",
            f"Glad it landed. {_hook(facts)}",
            "That's what I'm here for — shout when you need the next one.",
        ),
        history,
    )


def _goodbye(facts: InventoryFacts, history) -> str:
    low = facts.low_stock + facts.out_of_stock
    tail = (
        f" I'll keep an eye on the **{len(low)}** products running thin while "
        "you're gone."
        if low
        else " Everything's above its threshold, so nothing should surprise you."
    )
    return _pick(("See you.", "Right — until next time.", "Cheers."), history) + tail


def _confused(facts: InventoryFacts, history) -> str:
    return (
        "That's on me, not you — let me try again in plainer terms.\n\n"
        "Tell me which bit lost you and I'll unpack just that. Or start somewhere "
        "concrete and I'll follow: *what's running low?*, *what should I order "
        "next?*, or *how is my inventory configured?*\n\n"
        f"{_hook(facts)}"
    )


def _smalltalk(facts: InventoryFacts, history) -> str:
    return (
        "I'll be honest: I'm a poor conversationalist and a decent stock clerk. "
        "Inventory is genuinely the only thing I'm good at, and I'd rather be "
        f"useful than charming.\n\n{_hook(facts)}\n\n{_next_step(facts)}"
    )


def _own_trend_offer(facts: InventoryFacts) -> str:
    """What can honestly stand in for market data: their own sales."""
    if facts.history_is_reliable:
        movers = sorted(
            (p for p in facts.products if p.units_out_window > 0),
            key=lambda p: -p.units_out_window,
        )[:3]
        if movers:
            named = ", ".join(f"**{p.name}**" for p in movers)
            return (
                f"What I *can* read is your own demand, which is the trend that "
                f"actually pays you: {named} are moving fastest right now. Ask me "
                f"*what sells fastest* or *what should I order next* and I'll work "
                f"from that."
            )
    return (
        "Your own sales are the better signal anyway — that's the trend that "
        f"actually pays you. Right now only "
        f"{facts.summary()['history_coverage_pct']}% of your catalog has any "
        "recorded movement, so I can't read it yet. Record stock going out as you "
        "sell, and within a few weeks I can tell you what's trending **in your "
        "shop** — which beats a national average you can't act on."
    )


def out_of_scope(topic: str, facts: InventoryFacts) -> str:
    return (
        f"Straight answer: I can't see {topic}. There's no feed of the outside "
        f"world reaching me — no market data, no competitor prices, no browsing. "
        f"Everything I say comes from your own stock and your own transactions.\n\n"
        + _own_trend_offer(facts)
    )


def scope_note(topic: str) -> str:
    """Appended when a question asks for one thing I have and one I don't."""
    return (
        f"\n\n> On {topic}: I can't see those — no outside feed reaches me, only "
        f"your own stock and sales. Say the word and I'll show you what's moving "
        f"in your shop instead."
    )


def repair(question: str, facts: InventoryFacts, history=None) -> str:
    """Own it, say what went wrong, and offer something concrete.

    Repeating the previous answer here is what turned one bad reply into an
    argument.
    """
    topic = external_topic(question)
    opening = _pick(
        (
            "Fair enough — that wasn't the answer you asked for.",
            "You're right, and I'll stop doing that.",
            "Fair hit. Let me actually answer you.",
        ),
        history,
    )

    if topic:
        return (
            f"{opening} You asked about {topic}, and I kept handing you a stock "
            f"table.\n\nThe reason is dull but honest: I can't see outside your "
            f"shop. No market feed, no competitor prices, no web. "
            f"{_own_trend_offer(facts)}"
        )

    s = facts.summary()
    rows = [
        f"| **What's low** | {s['low_stock_count']} need attention | *what's running low?* |",
        f"| **What to order** | {s['reorder_count']} below reorder point | *what should I order next?* |",
        "| **Change stock** | One product, or all of them | *add 10 units to every low stock item* |",
        f"| **Your setup** | {s['total_products']} products, how they're filed | *how is my inventory configured?* |",
    ]
    return (
        f"{opening} Let me be concrete about what I'm actually good for — all of "
        f"this is your live data, one message away:\n\n"
        + _table(["I can", "Right now", "Just say"], rows)
        + "\n\nAnd if I've misread you, say the question again however you like — "
        "I'd rather ask than guess."
    )


def fallback(question: str, facts: InventoryFacts, history=None) -> str:
    """What to say when nothing understood the question.

    Never the metrics table. That table was the old default, and printing it
    for four unrelated questions in a row is what made the assistant look
    broken. Not understanding is a thing you *say*.
    """
    opening = _pick(
        (
            "I didn't quite catch what you're after.",
            "That one got past me — I'm not sure what you're asking for.",
            "I don't want to guess at that one and give you a confident wrong answer.",
        ),
        history,
    )
    topic = external_topic(question)
    if topic:
        return out_of_scope(topic, facts)

    s = facts.summary()
    return (
        f"{opening}\n\nHere's what I'm certain about, though: you have "
        f"**{s['total_products']}** products, **{s['low_stock_count']}** are "
        f"running low and **{s['reorder_count']}** are below their reorder point. "
        f"I can dig into any of that, change stock on one product or hundreds at "
        f"once, or draft the purchase orders.\n\n"
        f"Try putting it another way, or start with *{_example(facts)}* — I'll "
        "follow from there."
    )


def _example(facts: InventoryFacts) -> str:
    if facts.summary()["reorder_count"]:
        return "what should I order next?"
    if facts.low_stock or facts.out_of_stock:
        return "what's running low?"
    return "how is my inventory configured?"


def _table(headers: List[str], rows: List[str]) -> str:
    head = "| " + " | ".join(headers) + " |"
    sep = "| " + " | ".join([":---"] * len(headers)) + " |"
    return "\n".join([head, sep] + rows)


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

def reply(
    question: str,
    facts: InventoryFacts,
    business_type: str = "retail_store",
    history: Optional[List[Dict[str, str]]] = None,
) -> Optional[Reply]:
    """A conversational answer, or None to let the data layer take the question."""
    q = _norm(question)
    if not q:
        return None

    # Being told the answer was bad outranks everything. Running the normal
    # dispatch here is what printed the same rejected table a third time.
    if is_frustrated(q):
        return Reply(repair(question, facts, history))

    if q in GREETING_EXACT or _has(q, GREETING_PHRASES):
        return Reply(_greeting(facts, business_type, history))

    if _has(q, IDENTITY_PHRASES):
        return Reply(_identity(facts, history))

    if _has(q, HOW_PHRASES):
        return Reply(_how_it_works(facts, history))

    if _has(q, CAPABILITY_PHRASES) or (
        len(q.split()) <= 4 and _has(q, CAPABILITY_WEAK)
    ):
        return Reply(
            _capabilities(
                facts,
                business_type,
                history,
                repeat=said_before(history, "I'm **Ask AI**"),
            )
        )

    # Thanks and goodbyes are short by nature; a long message that merely
    # contains "thanks" is usually a real question with manners attached.
    if len(q.split()) <= 6:
        if _has(q, THANKS_PHRASES):
            return Reply(_thanks(facts, history))
        if _has(q, BYE_PHRASES):
            return Reply(_goodbye(facts, history))

    if q in CONFUSED_EXACT or _has(q, CONFUSED_PHRASES):
        return Reply(_confused(facts, history))

    if _has(q, SMALLTALK_PHRASES):
        return Reply(_smalltalk(facts, history))

    # Asked *only* about the outside world. Mixed questions fall through to the
    # data layer and pick up `scope_note` at the end instead.
    topic = external_topic(q)
    if topic and not _has(q, (
        "grow", "growth", "my stock", "my inventory", "reorder", "order next",
        "low stock", "what should i buy", "my business", "my shop",
    )):
        return Reply(out_of_scope(topic, facts))

    return None
