# Reporting service

An analytical read model over the operational store, in Spring Boot and
PostgreSQL.

## Why it exists

The financial reports — tax summary, aging, profit and loss, customer exposure —
were computed in memory on the client, over collections loaded in full, with no
pagination anywhere. About two thousand lines of it. That works until a
workspace has a year of invoices, and then it does not work at all.

Those reports are also the wrong shape for a document store. "Group by tax rate
across a quarter", "bucket receivables by age", "join lines to invoices to
payments and subtract" are relational questions. Firestore is a good operational
store and a poor analytical one, and the fix is not to make it into one.

So this is a projection, in a database that answers those questions natively:

```
Firestore (operational, source of truth)
      │  rebuild
      ▼
PostgreSQL (analytical read model)
      │
      ▼
reporting endpoints
```

**This service owns no business truth.** Every row in it is derived and can be
thrown away and rebuilt. Nothing writes back.

## What it does not do

It does not replace anything. The assistant still queries Firestore directly and
should — its questions are about current stock, which is exactly what a document
store is good at. This service exists for the historical, aggregate, multi-table
questions, and no further.

## Endpoints

All under `/api/reports`, all scoped to the caller's own workspace.

| Endpoint | Grant required | Returns |
|---|---|---|
| `GET /tax-summary?from&to` | `canViewTaxReports` | Output and input tax by rate, and the net position |
| `GET /aging?asOf` | `canViewReports` | Receivables in five age buckets |
| `GET /profit-and-loss?from&to` | `canViewReports` | Revenue net of tax, COGS, overhead, what is left |
| `GET /customer-balances?limit` | `canViewCreditControl` | Exposure per customer, worst first |
| `POST /api/sync` | `canManageCompanySettings` | Rebuilds the caller's projection |

The workspace comes from the authenticated principal and is never a parameter,
so there is no code path where a caller can name the company whose revenue they
want to read.

## Authorization

Re-implemented here, deliberately, for the same reason the Python assistant
re-implements it: this service reads through the Firebase Admin SDK, which
bypasses the security rules completely. Whatever the rules withhold has to be
withheld again in Java.

Membership is proved against `companies/{companyId}/members/{uid}` — the header
naming a company proves nothing. Permission is then resolved exactly as the
rules do: owner and admin short-circuit, then the role document, then per-user
overrides. Membership is cached for 300 seconds and grants for 30, because a
stale grant keeps handing out a capability that was just revoked.

Grants that cannot be read at all are a third state, distinct from holding none,
and both deny.

## Design notes

**Money is `BIGINT` minor units, never floating point.** A `DOUBLE` column
accumulates error across a quarter and reports a tax total of 4999.999999997.
The conversion happens once, at the sync boundary, in `Money.toMinor` — which
uses `BigDecimal.valueOf` rather than `new BigDecimal(double)`, because the
constructor takes the exact binary value and turns 19.99 into 1998.

**`company_id` leads every primary key and every index.** Tenancy is the
physical layout rather than a filter the application remembers to apply, so a
query that forgets it is both a tenancy bug and a full table scan.

**The sync is a full rebuild, not an incremental merge.** Incremental sync of a
document store means detecting deletes, which Firestore will not tell you about
after the fact, so a deleted invoice would linger in the projection forever and
quietly inflate every report. A workspace rebuild is a few thousand rows and
runs in one transaction: it either replaces everything or changes nothing.

**The SQL is portable on purpose** — no `date_trunc`, no `FILTER`, no interval
arithmetic. Bucket boundaries are computed in Java and bound as dates. That is
what lets the test suite run on H2 in PostgreSQL mode with no container runtime,
while CI runs the same suite again against real PostgreSQL.

## Running it

```bash
# Tests. No database, no Docker, no configuration.
JAVA_HOME=$(/usr/libexec/java_home -v 17) mvn test

# Locally, against a real PostgreSQL
export DATABASE_URL=jdbc:postgresql://localhost:5432/smartshelfkart_reporting
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
mvn spring-boot:run
```

Requires JDK 17 or newer. The build declares its annotation processor path
explicitly rather than relying on classpath discovery, which JDK 23 turned off
by default — without that, Lombok silently generates nothing and every accessor
fails to resolve.

## Open items

**Cost of goods sold is only as good as the source.** The operational invoice
line records `unitPrice` and `taxRate` but not the cost at the time of sale, so
`cost_price_minor` is zero unless the document happens to carry one. Filling it
from the product's *current* cost was considered and rejected: it would rewrite
the margin on every historical sale each time someone edited a cost price, which
is worse than reporting nothing. The real fix is upstream — the invoice line
should capture cost when the sale is made.

**Purchase bills are summarised at one tax rate.** The rate of the largest line
characterises the bill. Correct for the common single-rate bill, an
approximation for a mixed one, and it wants purchase lines projected the way
sales lines are before a return is ever filed from this data.

**There is no incremental sync.** See above — deliberate, but it does mean a
rebuild is O(workspace) and the scheduled job is off by default.
