import re
import logging
from typing import List, Tuple

logger = logging.getLogger(__name__)


def _parse_products(raw_context: str) -> Tuple[str, List[dict]]:
    """Parse the Flutter context format into structured product data.

    The raw_context format:
    [SYSTEM: ...instructions...] Product1(BC:xxx,Qty:N,Min:M) | Product2(BC:yyy,Qty:N,Min:M) | ...

    Returns:
        Tuple of (system_instructions, list of product dicts)
    """
    system_text = ""
    product_text = raw_context

    # Extract system instructions block
    sys_match = re.match(r"\[SYSTEM:\s*(.*?)\]\s*(.*)", raw_context, re.DOTALL)
    if sys_match:
        system_text = sys_match.group(1).strip()
        product_text = sys_match.group(2).strip()

    products = []
    # Split by pipe separator
    segments = [s.strip() for s in product_text.split("|") if s.strip()]

    for segment in segments:
        # Match: ProductName(BC:xxx,Qty:N,Min:M)
        match = re.match(r"(.+?)\(BC:([^,]+),Qty:(\d+),Min:(\d+)\)", segment.strip())
        if match:
            products.append({
                "name": match.group(1).strip(),
                "barcode": match.group(2).strip(),
                "qty": int(match.group(3)),
                "min": int(match.group(4)),
            })

    return system_text, products


def _format_products(products: List[dict], system_text: str = "") -> str:
    """Re-format product list back to the compact context string."""
    if not products and not system_text:
        return ""

    parts = []
    if system_text:
        parts.append(f"[SYSTEM: {system_text}]")

    product_strs = [
        f"{p['name']}(BC:{p['barcode']},Qty:{p['qty']},Min:{p['min']})"
        for p in products
    ]
    if product_strs:
        parts.append(" | ".join(product_strs))

    return " ".join(parts)


def _get_summary_stats(products: List[dict]) -> str:
    """Generate summary statistics from product list."""
    if not products:
        return ""

    total = len(products)
    low_stock = [p for p in products if p["qty"] <= p["min"] and p["qty"] > 0]
    out_of_stock = [p for p in products if p["qty"] == 0]

    return (
        f"Total:{total}, LowStock:{len(low_stock)}, OutOfStock:{len(out_of_stock)}"
    )


def filter_context(intent: str, question: str, raw_context: str) -> str:
    """Filter context based on intent for cost-efficient LLM calls.

    Args:
        intent: Classified intent category.
        question: The user's question.
        raw_context: Raw context string from Flutter frontend.

    Returns:
        Filtered context string optimized for the intent.
    """
    if not raw_context:
        return ""

    # No context needed for these intents
    if intent in ("GREETING", "NAVIGATION"):
        return ""

    try:
        system_text, products = _parse_products(raw_context)
    except Exception as e:
        logger.error("Failed to parse context: %s. Returning raw.", str(e))
        return raw_context

    if not products:
        return raw_context

    q_lower = question.lower()

    if intent == "STOCK_QUERY":
        # Check for low/out of stock queries
        if any(kw in q_lower for kw in ["low stock", "out of stock", "restock", "below minimum"]):
            filtered = [p for p in products if p["qty"] <= p["min"]]
            summary = _get_summary_stats(products)
            result = _format_products(filtered, system_text)
            return f"{result} | Summary: {summary}" if summary else result

        # Try to find specific product mention
        matched = _match_products_by_question(q_lower, products)
        if matched:
            return _format_products(matched, system_text)

        # Default: return all with summary
        summary = _get_summary_stats(products)
        result = _format_products(products[:20], system_text)
        return f"{result} | Summary: {summary}" if summary else result

    elif intent == "STOCK_UPDATE":
        # Extract only the specific product being updated
        matched = _match_products_by_question(q_lower, products)
        if matched:
            return _format_products(matched, system_text)
        # If no match, return all (LLM will figure it out)
        return _format_products(products, system_text)

    elif intent == "ANALYTICS":
        summary = _get_summary_stats(products)
        # Keep top 10 + summary stats
        top_products = sorted(products, key=lambda p: p["qty"])[:10]
        result = _format_products(top_products, system_text)
        return f"{result} | Summary: {summary}"

    elif intent == "ORDER_MGMT":
        # Keep mentioned products + low stock items
        matched = _match_products_by_question(q_lower, products)
        low_stock = [p for p in products if p["qty"] <= p["min"]]
        # Merge without duplicates
        seen_barcodes = set()
        combined = []
        for p in matched + low_stock:
            if p["barcode"] not in seen_barcodes:
                seen_barcodes.add(p["barcode"])
                combined.append(p)
        return _format_products(combined[:20], system_text)

    elif intent == "REPORT":
        summary = _get_summary_stats(products)
        result = _format_products(products[:20], system_text)
        return f"{result} | Summary: {summary}"

    else:  # GENERAL
        summary = _get_summary_stats(products)
        result = _format_products(products[:15], system_text)
        return f"{result} | Summary: {summary}" if summary else result


def _match_products_by_question(q_lower: str, products: List[dict]) -> List[dict]:
    """Find products mentioned in the question by name or barcode."""
    matched = []
    for p in products:
        name_lower = p["name"].lower()
        # Check if product name appears in question (fuzzy: check individual words)
        name_words = name_lower.split()
        if any(word in q_lower for word in name_words if len(word) > 2):
            matched.append(p)
        elif p["barcode"].lower() in q_lower:
            matched.append(p)
    return matched
