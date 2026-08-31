"""Invariants for stock arithmetic.

Two rules have to hold on every write, and each was broken in a way that only
showed up on real catalogs:

  * `quantity` always equals the sum of `locationQuantities`. The old code
    clamped a location at zero and dropped the remainder, so a product's total
    and its shelves silently disagreed — and the app reads both.
  * Stock never drops below what is reserved. The app caps dispatch at
    availableQuantity; the assistant used to ignore reservations entirely and
    would happily sell units already promised to an order.
"""

import sys

import testkit  # noqa: F401  (sets OFFLINE_MODE before anything loads)
from writes import _plan_location_changes

_failures = []


def check(label, actual, expected):
    ok = actual == expected
    if not ok:
        _failures.append(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}: {actual!r}")


def refuses(label, result, needle):
    locs, problem = result
    ok = locs is None and problem and needle.lower() in problem.lower()
    if not ok:
        _failures.append(f"{label}: expected refusal mentioning {needle!r}, got {problem!r}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f"  -- {problem}" if problem else ""))


print("\n== Multi-location deduction spills instead of clamping ==")
# The real case: Hide n Seek, {Main: 75, SHELF A: 85}, total 160.
locs, problem = _plan_location_changes({"Main": 75, "SHELF A": 85}, {}, -100, None)
check("no refusal", problem, None)
check("drains the largest first, spills into the next", locs, {"SHELF A": 0, "Main": 60})
check("locations still sum to the new total", sum(locs.values()), 60)

print("\n== The old clamping bug is gone ==")
# Previously: SHELF A clamped to 0 and the remaining 15 vanished, leaving the
# locations summing to 75 while quantity said 60.
check("no units are silently discarded", sum(locs.values()) == 160 - 100, True)

print("\n== Additions land in one place ==")
locs, problem = _plan_location_changes({"Main": 75, "SHELF A": 85}, {}, +40, None)
check("largest holding absorbs it", locs, {"Main": 75, "SHELF A": 125})
check("total is right", sum(locs.values()), 200)

print("\n== A named location is used exactly ==")
locs, problem = _plan_location_changes({"Main": 75, "SHELF A": 85}, {}, -50, "Main")
check("only the named location moves", locs, {"Main": 25, "SHELF A": 85})
locs, problem = _plan_location_changes({"Main": 75, "SHELF A": 85}, {}, +10, "SHELF A")
check("addition to a named location", locs, {"Main": 75, "SHELF A": 95})

print("\n== Reserved units are never taken ==")
# TEST 1: SHELF A holds 100, of which 35 are reserved.
refuses(
    "per-location reservation respected",
    _plan_location_changes({"SHELF A": 100}, {"SHELF A": 35}, -80, "SHELF A"),
    "reserved",
)
locs, problem = _plan_location_changes({"SHELF A": 100}, {"SHELF A": 35}, -65, "SHELF A")
check("deducting exactly the free amount is allowed", locs, {"SHELF A": 35})

refuses(
    "spill also stops at reservations",
    _plan_location_changes({"Main": 75, "SHELF A": 85}, {"SHELF A": 25}, -150, None),
    "free across all locations",
)
locs, problem = _plan_location_changes({"Main": 75, "SHELF A": 85}, {"SHELF A": 25}, -135, None)
check("takes every free unit and no more", sum(locs.values()), 160 - 135)
check("reserved units left in place", locs["SHELF A"], 25)

print("\n== Products with no location tracking still work ==")
locs, problem = _plan_location_changes({}, {}, -20, None)
check("nothing to distribute", locs, {})
check("no refusal", problem, None)

print("\n== A location that doesn't exist yet is created by an addition ==")
locs, problem = _plan_location_changes({"Main": 10}, {}, +5, "Cold Store")
check("new location appears", locs, {"Main": 10, "Cold Store": 5})
refuses(
    "but cannot be deducted from",
    _plan_location_changes({"Main": 10}, {}, -5, "Cold Store"),
    "free at Cold Store",
)

print("\n== Invariant sweep over generated cases ==")
import itertools, random  # noqa: E402

random.seed(7)
bad = 0
for _ in range(300):
    n = random.randint(1, 4)
    loc_map = {f"L{i}": random.randint(0, 200) for i in range(n)}
    held_map = {k: random.randint(0, v) for k, v in loc_map.items() if v and random.random() < 0.5}
    total = sum(loc_map.values())
    delta = random.randint(-250, 250)
    target = random.choice([None] + list(loc_map))
    result, problem = _plan_location_changes(loc_map, held_map, delta, target)
    if problem:
        continue
    if sum(result.values()) != total + delta:
        bad += 1
    if any(v < 0 for v in result.values()):
        bad += 1
    for k, v in result.items():
        if delta < 0 and v < held_map.get(k, 0):
            bad += 1
check("no case broke an invariant", bad, 0)

print("\n" + "=" * 60)
if _failures:
    print(f"{len(_failures)} FAILURE(S):")
    for f in _failures:
        print(f"  - {f}")
    sys.exit(1)
print("All stock-math invariants hold.")
