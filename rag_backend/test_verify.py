"""The self-check on model-authored answers."""

import sys

import testkit
from verify import check_answer, describe

_failures = []


def check(label, actual, expected):
    ok = actual == expected
    if not ok:
        _failures.append(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}: {actual!r}")


facts = testkit.seed()          # Fresh Apples 15, Pro Laptops 100, Water 200, Milk 8

print("\n== A wrong stock figure is corrected, not shipped ==")
out, issues = check_answer("You have **Fresh Apples (kg)** with 250 units on hand.", facts)
check("one issue found", len(issues), 1)
check("kind", issues[0].kind, "wrong_quantity")
check("number replaced with the truth", "15 units" in out, True)
check("invented number is gone", "250" in out, False)

print("\n== A correct figure is left alone ==")
out, issues = check_answer("**Pro Laptops 15-inch** currently has 100 units.", facts)
check("nothing flagged", issues, [])
check("text untouched", out, "**Pro Laptops 15-inch** currently has 100 units.")

print("\n== 'Not found' about something that exists is flagged ==")
# The exact failure seen in production: a barcode listed, then denied.
out, issues = check_answer("Product with barcode 89010001 not found.", facts)
check("flagged", len(issues), 1)
check("kind", issues[0].kind, "false_not_found")

print("\n== Genuinely unknown products are not flagged ==")
out, issues = check_answer("Product with barcode 99999999 not found.", facts)
check("nothing flagged", issues, [])

print("\n== Ambiguity is left alone rather than guessed at ==")
dupes = testkit.seed([
    {"id": "a", "barcode": "1", "name": "Cotton Roll Basic", "stock": 90, "min_threshold": 5},
    {"id": "b", "barcode": "2", "name": "Cotton Roll Basic", "stock": 16, "min_threshold": 5},
])
out, issues = check_answer("**Cotton Roll Basic** has 40 units.", dupes)
check("duplicate names are not rewritten", issues, [])

print("\n== Prose without checkable claims passes through ==")
text = "Order more soon; your fastest movers will run out within the week."
out, issues = check_answer(text, facts)
check("untouched", out, text)
check("nothing flagged", issues, [])

print("\n== Degrades safely ==")
check("no facts", check_answer("anything", None)[0], "anything")
check("empty answer", check_answer("", facts)[0], "")

print("\n" + "=" * 60)
if _failures:
    print(f"{len(_failures)} FAILURE(S):")
    for f in _failures:
        print(f"  - {f}")
    sys.exit(1)
print("All self-check tests passed.")
