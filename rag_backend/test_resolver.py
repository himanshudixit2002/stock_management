"""Product resolution tests — the ambiguity cases are the point.

The old matcher picked the first product whose name contained a query word,
which is how "add 50 cannula" silently updated Cannula 18G when the user meant
20G. Resolution must return `ambiguous` there, not a guess.
"""

import sys

sys.path.insert(0, ".")

from resolver import ProductResolver, strip_command_words

_failures = []


def check(label, actual, expected):
    ok = actual == expected
    if not ok:
        _failures.append(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}: {actual!r}")


class P:
    def __init__(self, name, barcode, quantity=25):
        self.name = name
        self.barcode = barcode
        self.id = "doc_" + barcode
        self.quantity = quantity
        self.available_qty = quantity


CATALOG = [
    P("Cannula 18G", "1001"),
    P("Cannula 20G", "1002"),
    P("Fresh Apples (kg)", "89010001"),
    P("Pro Laptops 15-inch", "89010002"),
    P("Sparkling Water Pack of 12", "89010003"),
    P("Organic Whole Milk 1L", "89010004"),
    P("Standard Bandage Roll", "2001"),
    P("Standard Gauze Pad", "2002"),
    P("Standard Syringe 5ml", "2003"),
]
R = ProductResolver(CATALOG)


def status(query):
    return R.resolve(query).status


def name(query):
    res = R.resolve(query)
    return res.product.name if res.product else None


print("\n== Ambiguity is reported, not guessed ==")
check("'add 50 cannula' is ambiguous", status("add 50 cannula"), "ambiguous")
check("both cannulas offered", len(R.resolve("add 50 cannula").candidates), 2)
check("'add 10 standard' is ambiguous", status("add 10 standard"), "ambiguous")

print("\n== A qualified query resolves cleanly ==")
check("'cannula 20g' resolves", status("add 5 cannula 20g"), "resolved")
check("...to the 20G", name("add 5 cannula 20g"), "Cannula 20G")
check("'cannula 18g' -> 18G", name("deduct 3 cannula 18g"), "Cannula 18G")

print("\n== Barcodes win outright ==")
check("barcode resolves", status("restock 20 of 89010002"), "resolved")
check("barcode picks the right product", name("restock 20 of 89010002"), "Pro Laptops 15-inch")
check("barcode confidence is 1.0", R.resolve("add 5 1002").confidence, 1.0)

print("\n== Natural phrasing ==")
check("'fresh apples'", name("add 50 units of fresh apples"), "Fresh Apples (kg)")
check("'organic whole milk'", name("how many organic whole milk do i have"), "Organic Whole Milk 1L")
check("'sparkling water'", name("deduct 5 sparkling water"), "Sparkling Water Pack of 12")
check("'bandage'", name("add 30 bandage"), "Standard Bandage Roll")

print("\n== Nonsense is rejected rather than force-matched ==")
check("unknown product", status("add 5 zzz widget"), "not_found")
check("empty query", status(""), "not_found")
check("pure command words", status("add units of"), "not_found")

print("\n== Command words are stripped before matching ==")
check("strip verbs/quantities", strip_command_words("add 50 units of fresh apples"), "fresh apples")
check("strip question form", strip_command_words("how many bandage rolls do i have"), "bandage rolls")
check("keeps a bare product name", strip_command_words("cannula 20g"), "cannula 20g")

print("\n== Small catalogs still resolve (document frequency needs volume) ==")
# Every distinguishing word appears in 50% of a two-product catalog. Treating
# those as generic filler made the resolver reject valid matches outright.
tiny = ProductResolver([P("Cannula 18G", "1001"), P("Cannula 20G", "1002")])
check("shared word still matches on a 2-product catalog",
      tiny.resolve("deduct 5 cannula").status, "ambiguous")
check("...offering both", len(tiny.resolve("deduct 5 cannula").candidates), 2)
check("qualified request still resolves",
      tiny.resolve("deduct 5 cannula 20g").product.name, "Cannula 20G")
# The generic-word penalty must still apply once the catalog is big enough.
check("'standard' is still rejected as filler on a large catalog",
      status("add 10 standard"), "ambiguous")

print("\n== Empty catalog degrades safely ==")
check("no products", ProductResolver([]).resolve("anything").status, "not_found")

print("\n== Numbers inside a product name survive ==")
# "deduct 80 units of TEST 1" used to strip both numbers, leaving only "test",
# which matches TEST2 and TEST3 better than the product actually named.
numbered = ProductResolver([
    P("TEST 1", "1001", 100), P("TEST2", "1002", 200), P("TEST3", "1003", 300),
])
check("the named product wins",
      numbered.resolve("deduct 80 units of TEST 1").product.name, "TEST 1")
check("quantity is still discarded", strip_command_words("deduct 80 units of TEST 1"), "test 1")
check("a name that is just digits+word still resolves",
      numbered.resolve("add 5 TEST2").product.name, "TEST2")
check("a bare number is treated as an answer, not a name",
      strip_command_words("50"), "50")

print("\n== Duplicate names are separable only by barcode ==")
# Real catalogs contain several products sharing a name. The barcode is the
# only thing telling them apart, so a request naming one must resolve — and it
# must survive being embedded in a full sentence.
dupes = ProductResolver([
    P("Cotton Roll Basic", "353013617355", 94),
    P("Cotton Roll Basic", "331766491619", 16),
    P("Cotton Roll Premium", "999000111222", 5),
])
check("bare name is ambiguous", dupes.resolve("add 10 units of Cotton Roll Basic").status, "ambiguous")
r = dupes.resolve("add 10 units of barcode 353013617355")
check("barcode in a sentence resolves", r.status, "resolved")
check("...to the right duplicate", r.product.barcode, "353013617355")
check("bare barcode resolves", dupes.resolve("353013617355").product.barcode, "353013617355")
check("the other duplicate is reachable too",
      dupes.resolve("add 5 331766491619").product.barcode, "331766491619")

print("\n== Clarification text lists the options ==")
text = R.resolve("add 50 cannula").clarification()
check("mentions 18G", "Cannula 18G" in text, True)
check("mentions 20G", "Cannula 20G" in text, True)

print("\n" + "=" * 60)
if _failures:
    print(f"{len(_failures)} FAILURE(S):")
    for f in _failures:
        print(f"  - {f}")
    sys.exit(1)
print("All resolver tests passed.")
