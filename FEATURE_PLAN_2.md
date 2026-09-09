# Feature Plan 2 — ten more modules

The first ten (see [FEATURE_PLAN.md](FEATURE_PLAN.md)) closed the gaps in *what
stock is*: what it is made of, which unit it is, where it is between two
locations, who approved buying it, what it cost to land.

These ten close the gaps in *what the business does with it*: the quote before
the order, the pick and pack before the dispatch, the cash drawer behind the
counter, the money going out rather than in, the limit on what a customer may
owe, whether a supplier actually delivers, what the person who sold it earns,
what was planned versus spent, the repair after the sale, and the work sent out
to somebody else's workshop.

Every one sits on products, transactions, orders, invoices, customers, vendors
or serials that are already modelled. None of them introduces a second source of
truth, and none needs a new dependency or a backend.

## What "synced" means here

Unchanged from the first wave, and worth restating because it is the whole
reason these are specified as verticals rather than screens:

| Surface | File | What breaks if skipped |
|---|---|---|
| Route constant | `lib/config/routes.dart` | Nothing can name the destination |
| Route case | `lib/config/router.dart` | Deep links and pushes fall through |
| Permission keys + defs | `lib/config/permissions.dart` | Role editor cannot grant it; staff get it unconditionally |
| Catalog entry | `lib/config/feature_map.dart` | Missing from Home, tab headers, Plan & Features, tier editor, reports index |
| Provider registration | `lib/app.dart` | `context.read` throws; state survives sign-out into the next tenant |
| Collection + CRUD | `lib/services/database_service.dart` | No tenant scoping, no plan caps, no audit trail |
| Security rules | `firestore.rules` | The permission key is decoration — the server allows anything |
| Composite indexes | `firestore.indexes.json` | Ordered/filtered queries fail in production only |
| Tests | `test/` | Regressions land silently |

---

## 1. Sales Quotations

**Collection:** `companies/{id}/quotations`

The sales funnel currently starts at a confirmed sales order, so everything
before the customer says yes happens outside the app. A quotation is a priced
offer with a validity date that moves `draft → sent → accepted / declined /
expired → converted`, and converting it writes a real sales order from the same
lines.

- **Model:** `QuotationModel`, `QuotationLine`
- **Screens:** list (with a pipeline header), editor, detail (send / accept /
  decline / convert)
- **Permissions:** `canViewQuotations`, `canManageQuotations`,
  `canConvertQuotations`
- **Reuse:** lines are priced through `PriceListResolver`, so a quote to a
  wholesale customer carries wholesale prices without anyone retyping them
- **Why it matters:** the win rate, the value of open offers, and the reason a
  deal was lost are all business facts the app throws away today.

## 2. Pick, Pack & Ship

**Collection:** `companies/{id}/shipments`

A sales order today goes from confirmed to dispatched in one action, which is
one action too few: somebody has to walk the warehouse with a list, and somebody
has to put the units in boxes. A shipment is that document — ordered vs picked
vs packed per line, package count, weight, carrier and tracking — moving
`draft → picking → packed → dispatched → delivered`.

- **Model:** `ShipmentModel`, `ShipmentLine`
- **Screens:** list, create-from-order, detail (pick / pack / dispatch / deliver)
- **Permissions:** `canViewShipments`, `canManageShipments`,
  `canDispatchShipments`
- **Stock:** *none of its own.* Dispatching a shipment calls the existing sales
  order dispatch path, which already consumes this order's reserved holds from
  the exact locations they were held at. A second implementation would
  double-deduct or leak holds; there is one, and shipments drive it.
- **Why it matters:** picking errors are the most common warehouse error, and
  nothing in the app currently records what was actually picked.

## 3. Operating Expenses

**Collection:** `companies/{id}/expenses`

Profit & Loss is gross margin wearing the word "profit": it sees purchases and
sales and nothing else. Rent, salaries, freight-out, utilities and the rest never
enter the app, so no figure it reports is a net profit. An expense is a dated,
categorised amount with an optional vendor, tax component and payment state.

- **Model:** `ExpenseModel`, with a fixed set of heads (`ExpenseCategory`)
- **Service:** `ExpenseSummaryService` — pure, unit-testable: totals by head, by
  month, unpaid exposure
- **Screens:** expense list (month scoped, totals by head), expense editor
- **Permissions:** `canViewExpenses`, `canManageExpenses`
- **Integration:** the Profit & Loss report gains an operating-expense block and
  a true net profit line beneath its gross margin
- **Why it matters:** a business that knows its gross margin and not its net
  profit does not know whether it is making money.

## 4. POS Register Sessions

**Collection:** `companies/{id}/registerSessions`

Fast POS takes cash and never counts it. A register session is the shift: an
opening float, cash movements (drops and payouts) during it, every sale stamped
with the session it belongs to, and a blind close where the operator counts the
drawer before the app reveals what it expected — because a count shown the
expected figure first is not a count.

- **Model:** `RegisterSessionModel`, `CashMovement`
- **Service:** `RegisterTallyService` — pure: expected cash, takings by payment
  method, variance, the Z-report figures
- **Screens:** session list/history, open-session sheet, cash-up (blind count)
  with the Z-report
- **Permissions:** `canViewRegisterSessions`, `canManageRegisterSessions`
- **Integration:** `InvoiceModel` gains `registerSessionId`; Fast POS stamps it
  on every sale and shows the open session in its header
- **One open session per register** is enforced through a lock document in the
  same collection, read and written inside one transaction. Firestore
  transactions cannot run a query, so a lock document is the only way to make
  "no second session" an invariant rather than a hope.
- **Why it matters:** cash businesses reconcile the drawer every day, and doing
  it on paper next to an app that knows every sale is absurd.

## 5. Customer Credit Control

**Derived — no new collection.** Reads invoices; adds three fields to customers.

Credit is extended today by whoever is standing at the counter. This adds a
limit and payment terms per customer, computes live exposure from unpaid
invoices, and checks it at the two places credit is actually granted.

- **Model:** `CustomerModel` gains `creditLimit`, `paymentTermDays`,
  `creditHold`
- **Service:** `CreditControlService` — pure: exposure, overdue split,
  utilisation, and a verdict (`ok` / `warning` / `blocked`) with the reason
- **Screens:** credit control dashboard (exposure ranked, over-limit, on hold);
  terms editable on the customer form
- **Permissions:** `canViewCreditControl`, `canManageCreditLimits`
- **Integration:** the invoice editor and Fast POS both consult the verdict
  before a credit sale — a hold or an over-limit sale is refused, an
  approaching limit warns
- **Why it matters:** the aging report tells you who owes you too much after it
  has already happened.

## 6. Vendor Performance Scorecard

**Derived — no new collection.** Reads purchase orders.

Every fact needed to judge a supplier is already in the purchase orders: when
delivery was expected, when it arrived, how much of it arrived, and what it
cost. Nothing computes it. This ranks vendors on on-time delivery, fill rate,
average lead time against their promised lead time, and price movement, and
grades them A–D.

- **Service:** `VendorScorecardService` — pure, unit-testable
- **Screen:** scorecard report, with a per-vendor breakdown
- **Permissions:** `canViewVendorScorecard`
- **Why it matters:** the vendor list has a `rating` field somebody types in by
  hand and a `leadTimeDays` nobody checks against reality.

## 7. Sales Commissions

**Collection:** `companies/{id}/commissionPlans`

Who sold it is recorded on every invoice (`createdBy`) and used for nothing. A
commission plan names a basis (revenue or margin), a rate, optional per-category
rates, and the people it applies to; the statement computes what each of them
earned in a period.

- **Model:** `CommissionPlanModel`, `CommissionRate`
- **Service:** `CommissionCalculator` — pure: per-person statements, per-invoice
  lines, margin basis using product cost prices
- **Screens:** plan list, plan editor, commission statement (period + person)
- **Permissions:** `canViewCommissions`, `canManageCommissions`
- **Decision:** unpaid invoices are excluded unless the plan says otherwise —
  paying commission on money not yet collected is how commission schemes go
  wrong.
- **Why it matters:** every workspace with a sales team computes this in a
  spreadsheet, from data this app already holds.

## 8. Budgets & Variance

**Collection:** `companies/{id}/budgets`

A period budget with lines per head — revenue, purchases, and each expense
category — measured against actuals drawn from the invoices, purchase orders and
expenses already in the workspace, with over-budget lines flagged.

- **Model:** `BudgetModel`, `BudgetLine`
- **Service:** `BudgetVarianceService` — pure: actual vs budget per line, pace
  against the elapsed share of the period
- **Screens:** budget list, budget editor, variance detail
- **Permissions:** `canViewBudgets`, `canManageBudgets`
- **Decision:** pace matters as much as total. A line 60% spent is fine in
  month eight and a problem in month two, so the variance carries both.
- **Why it matters:** the reports are all backward-looking; this is the only one
  that compares what happened to what was supposed to happen.

## 9. Warranty & Service Jobs

**Collection:** `companies/{id}/serviceJobs`

Serial tracking exists so that a unit can be identified after it is sold, and
then nothing consumes it. A service job is the after-sale lifecycle: a customer
brings a unit back, it is diagnosed, parts are fitted, and it is returned —
`received → diagnosed → inProgress → awaitingParts → resolved → closed`, with
warranty state decided from the serial's warranty date rather than from memory.

- **Model:** `ServiceJobModel`, `ServicePart`, `ServiceCharge`
- **Screens:** job list (aging, SLA), create (customer + serial + fault), detail
  (advance status, fit parts, charge, resolve)
- **Permissions:** `canViewServiceJobs`, `canManageServiceJobs`,
  `canCloseServiceJobs`
- **Stock:** fitting parts issues them for real — a `stockOut` row per part
  inside one transaction, reason `Service job <number>`. Parts consumed off the
  books is how a service department loses stock.
- **Integration:** the serial detail sheet raises a job and lists that unit's
  job history
- **Why it matters:** warranty claims and repairs are the reason serial numbers
  are worth tracking at all.

## 10. Subcontracting (Job Work)

**Collection:** `companies/{id}/jobWorkOrders`

Assembly assumes the work happens here. Plenty of it does not: components go to
a plating shop, a tailor, a machinist, and come back as something else. A job
work order issues components to a vendor, holds them in an explicit *At vendor*
bucket while they are gone, and receives finished goods against a BOM or an
explicit output line, with the job charge folded into what the output cost.

- **Model:** `JobWorkOrderModel`, `JobWorkComponent`
- **Screens:** list, create (from a BOM or by hand), detail (issue / receive /
  close / cancel)
- **Permissions:** `canViewJobWork`, `canManageJobWork`, `canIssueJobWork`,
  `canReceiveJobWork`
- **Stock:** the same principle as in-transit — *at a vendor* is a location, not
  a state. Issued components stay in `locationQuantities` under `At vendor`, so
  total on-hand is constant while the work is out and valuation still
  reconciles. Receiving consumes from that bucket and creates the output in one
  transaction.
- **Costing:** the output's cost is the components it consumed plus the job
  charge, spread over the units received. Writing it to the product also writes
  a `priceHistory` row, exactly as a landed cost sheet does.
- **Why it matters:** without it, sending work out looks like stock vanishing
  and coming back as a different product nobody paid for.

---

## Plan tiering

All ten are catalogued in `FeatureMap`, so the console's tier editor can lock any
of them per plan with no code change. The compiled seed tiers lock the modules a
smaller workspace would not use:

- **Starter** additionally locks: shipments, register sessions, credit control,
  vendor scorecard, commissions, budgets, service jobs, job work
- **Growth** additionally locks: commissions, budgets, job work
- **Pro / MAX**: everything

Quotations and expenses stay unlocked on every tier: a single-location shop
quotes work and pays rent like everybody else.

## Rollout order

1. Pure services and models first (3, 5, 6, 7, 8) — no schema, no rules,
   unit-testable on their own.
2. Then the collection-backed lifecycles (1, 2, 4, 9, 10).
3. Wiring last, in one pass across the nine surfaces above.
4. Integrations after wiring, because each one touches a screen that already
   works: Profit & Loss, the invoice editor, Fast POS, the sales order detail,
   the serial sheet, the customer form.

---

## What landed

All ten, wired across every surface in the table above, plus the six
integrations. Notes on the decisions that were made while building rather than
while planning:

**At a vendor is a location, not a state.** Issuing job work moves components
into an `At vendor` bucket in `locationQuantities` rather than removing them, so
a product's total on-hand is unchanged while the work is out and valuation keeps
reconciling — the same principle the first wave used for `In transit`. Closing a
job returns whatever the vendor still holds to the shelf, because the
alternative is components counted as on-hand and findable nowhere.

**One implementation of dispatch.** Shipments move no stock of their own.
Dispatching one calls the sales order path, which already consumes that order's
reserved holds from the exact locations they were held at. A second
implementation would have double-deducted or stranded holds. It is also why the
stock moves *before* the shipment is stamped: the order caps a repeat attempt at
zero remaining units, so a retry after a timeout re-stamps rather than
re-dispatches.

**A lock document, because a transaction cannot query.** "One open shift per
register" has to be an invariant, not a hope, and Firestore transactions can
only read documents by id. The lock lives in `registerSessions` alongside the
shifts, carries no `openedAt`, and is therefore excluded from the shift stream
by the `orderBy` itself.

**The blind close.** The counted figure is entered before the expected one is
revealed, and both are stamped onto the shift at close rather than recomputed on
read. A count taken with the answer on screen is a confirmation, not a count —
and a refund next week must not rewrite the history of a drawer that was counted
and signed off today.

**Credit control is scoped at the server, not just in the UI.** Setting a limit
writes to the customer document, which is governed by `canEditCustomers`. Rather
than hand a credit controller a full update right — which would also let them
rewrite an address — the rule's second branch accepts `canManageCreditLimits`
only when the write touches nothing but `creditLimit`, `paymentTermDays`,
`creditHold` and `updatedAt`.

**Credit is checked where credit is granted.** `CreditControlService` is
consulted by the invoice editor and by Fast POS before the sale is written, not
only by the dashboard that reports exposure afterwards. Both call
`exposureAfterSale`, because a customer exactly at their limit is fine until
somebody tries to sell them more.

**Commission is paid on collection by default.** An invoice contributes its
collected share unless the plan says otherwise, and a loss-making margin sale
earns zero rather than clawing back against another sale. Both are the failure
modes that make commission schemes cost more than the sales they rewarded.

**Pace, not just totals.** Budget variance carries the elapsed share of the
period on every line, so "60% spent" is reported as fine in month eight and as a
problem in month two.

**Warranty is decided as at the day the unit came in.** A job copies the
serial's warranty date rather than reading it live, so a warranty lapsing while
the unit sits on the bench cannot turn a free repair into a billable one.

**Atomicity where a half-write would destroy stock.** `issueServiceParts`,
`issueJobWork`, `receiveJobWork` and `closeJobWorkOrder` each do all their reads
before any write inside one `runTransaction`. A receipt that created finished
goods but failed before consuming the components would invent stock out of
nothing.

**Idempotence where a repeat tap costs stock.** The `issued` flag on each
service part is what makes "Issue parts" safe to press twice — an already-issued
part is skipped rather than taken out of stock again.

**No composite indexes were needed.** Every query these modules make is a
single-field `orderBy`, all covered by Firestore's automatic single-field
indexes, so `firestore.indexes.json` is unchanged.

**The platform console manages all of it.** Per-plan locks were already
data-driven off `FeatureMap`, so the ten new modules appeared in the tier editor
the moment they were catalogued. The data side was not: `companySubcollections`
in `SuperAdminService` was purge-only and had drifted, so the seven collections
the *first* wave added were silently left behind by a purge that reported
success — a workspace deleted on request kept its price lists and landed costs in
Firestore for ever. That list is now one catalog of `CompanyCollection` entries
with three consumers: the purge iterates it, the console counts from it, and a
new **Modules** tab in the workspace inspector renders it — usage counts per
module plus a generic read-only browser over any of the fifteen module
collections. Generic on purpose: the next module is browsable the moment it is
listed, with no new stream, provider field or tab.
`test/config/company_collections_contract_test.dart` reads the app source for
every `.collection('x')` under a company and fails if the catalog is missing one,
which is the guard that was absent when this drifted the first time. Plan locks
also render through the catalog now, so a tier shows "No Register Shifts" rather
than "No registerSessions".

**Integrations.** Profit & Loss gained an operating-expense block and a true net
profit line; the invoice editor and Fast POS check credit before writing; Fast
POS stamps every sale with its shift and shows which one; the sales order detail
raises a pick list; the serial sheet shows that unit's repair history and raises
a job; and the customer form carries limits, terms and holds behind
`canManageCreditLimits`.

**Verification.**

- `flutter analyze lib` — clean; the six remaining infos all pre-date this work.
- `flutter test` — 765 passing, including ~100 new tests across the six pure
  services and the four new lifecycle models, and six pinning the console's
  collection catalog against what the app actually writes.
- The Firestore rules suite against the emulator: **176 passing, 0 failing** (57
  new), covering cross-tenant reads on all eight new collections,
  view-without-write, the three act-on-it carve-outs (convert, close, receive),
  the register lock document, admin-only deletion of a cashed-up shift,
  suspension, and the platform admin's read-but-never-write boundary.
- `flutter build web --release` — `main.dart.js` grows 126 KB (+2.6%); the rest
  lands in 98 new deferred chunks that load only on navigation.
