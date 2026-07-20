import logging
from typing import List, Optional
from pydantic import BaseModel, Field
from langchain_google_genai import ChatGoogleGenerativeAI

logger = logging.getLogger(__name__)

# Valid intent categories
INTENT_CATEGORIES = [
    "GREETING",
    "NAVIGATION",
    "STOCK_QUERY",
    "STOCK_UPDATE",
    "ANALYTICS",
    "ORDER_MGMT",
    "REPORT",
    "GENERAL",
]


class IntentResult(BaseModel):
    """Structured output for intent classification."""
    intent: str = Field(
        description="The classified intent category.",
        json_schema_extra={"enum": INTENT_CATEGORIES},
    )


# Singleton classifier LLM
_classifier_llm = ChatGoogleGenerativeAI(
    model="gemini-2.0-flash-lite",
    temperature=0,
)
_structured_classifier = _classifier_llm.with_structured_output(IntentResult)

_SYSTEM_PROMPT = (
    "Classify the user's intent into exactly one category.\n"
    "Categories: GREETING (hi/hello/thanks), NAVIGATION (go to/open/show screen), "
    "STOCK_QUERY (check stock/quantity/availability), STOCK_UPDATE (add/remove/update stock), "
    "ANALYTICS (analyze/trend/forecast), ORDER_MGMT (purchase order/sales order/create order), "
    "REPORT (generate report/summary), GENERAL (anything else).\n"
    "Return only the category name."
)


def classify_intent(
    question: str,
    chat_history: Optional[List[dict]] = None,
) -> str:
    """Classify a user question into an intent category.

    Args:
        question: The user's question text.
        chat_history: Optional previous conversation turns.

    Returns:
        One of the INTENT_CATEGORIES strings.
    """
    try:
        messages = [{"role": "system", "content": _SYSTEM_PROMPT}]

        # Add last 2 turns of chat history for context (cost-efficient)
        if chat_history:
            for turn in chat_history[-4:]:
                role = "user" if turn.get("role") == "user" else "assistant"
                messages.append({"role": role, "content": turn.get("content", "")})

        messages.append({"role": "user", "content": question})

        result = _structured_classifier.invoke(messages)

        if result and result.intent in INTENT_CATEGORIES:
            logger.info("Intent classified: %s for question: %.50s...", result.intent, question)
            return result.intent

        logger.warning("Invalid intent '%s', defaulting to GENERAL", getattr(result, 'intent', None))
        return "GENERAL"

    except Exception as e:
        logger.error("Intent classification failed: %s. Defaulting to GENERAL.", str(e))
        return "GENERAL"
