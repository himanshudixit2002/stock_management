# The marketing site

`smartshelfkart.com` runs a Flutter **CanvasKit** app. Every heading and
paragraph the app draws is a pixel painted into a `<canvas>`, so Googlebot's
renderer finds no text nodes and nothing to index. Before this directory
existed, the entire indexable content of the domain was a `<title>`, one meta
description and a two-line splash — which is why the site did not rank, and
could not rank, for anything at all including its own brand name.

The app cannot be made crawlable without abandoning CanvasKit. So the marketing
site is a separate, hand-authored, static HTML site sharing the domain:

```
/                    static marketing homepage   <- indexable
/features, /pricing, /tools/*, /blog/*, /compare/*
/privacy-policy, /terms, /support, /data-deletion
/app                 the Flutter app shell       <- Disallow in robots.txt
```

## Running it

```bash
flutter build web --release   # must run first
node seo/build.mjs            # or: npm run seo
```

`deploy_all.sh` does both in order. **Deploying without `seo/build.mjs`
publishes a site with no indexable content at all** — `build/web/index.html`
would still be the Flutter shell.

## What the generator does

1. Content-hashes `site.css` into `/static/site.<hash>.css` (safe to cache for
   a year, which is what `firebase.json` does).
2. Moves the Flutter shell from `index.html` to `app.html`, so the crawlable
   homepage can own `/`. `cleanUrls` then serves it at `/app`.
3. Repoints `flutter_service_worker.js` at `/app`: its cache key becomes `app`
   (not `app.html`, which `cleanUrls` 301s — and the Cache API refuses to store
   a redirected response, which would fail the whole install), it stops
   claiming `/`, and generated files are pruned from its manifest so the output
   is identical whether or not `flutter clean` ran.
4. Renders every page from `pages/*.mjs` through `layout.mjs`.
5. Adds canonical, description, Open Graph and a home link to the four
   hand-written legal pages.
6. Writes `sitemap.xml` and `robots.txt`.
7. Checks: every internal link resolves, titles are under 65 chars,
   descriptions are 110–175, no duplicate titles or descriptions, exactly one
   `<h1>` per page. The build prints warnings; it does not fail on them.

## Layout

| File | Purpose |
| --- | --- |
| `site.mjs` | Brand, nav, feature catalogue, and the live bindings the plan catalogue is written into. Features mirror `lib/config/feature_map.dart`. |
| `plans.mjs` | Reads the tier catalogue and the founding-member offer from Firestore, plus every helper that turns them into copy. |
| `layout.mjs` | HTML shell, header, footer, JSON-LD graph, breadcrumbs. |
| `blocks.mjs` | Reusable sections: cards, tables, FAQ, CTA, schema helpers. |
| `site.css` | The whole stylesheet. System fonts only — no webfont request. |
| `pages/*.mjs` | Page content. Each exports an array of page objects. |
| `build.mjs` | The generator. |

## Adding a page

Add a page object to one of `pages/*.mjs`:

```js
{
  path: '/tools/abc-calculator',        // canonical URL
  file: 'tools/abc-calculator.html',    // where it lands in build/web
  title: '…',                           // < 65 chars
  description: '…',                     // 110–175 chars
  trail: [{href:'/',label:'Home'}, …],  // breadcrumbs, visible + schema
  schema: [faqLd(faqs)],                // extra JSON-LD nodes
  body: '…',
}
```

Then link to it from somewhere — the build fails its link check if a page links
to nothing, but it will not tell you about a page nothing links to.

## Pricing comes from the platform console, not from the code

`plans/{id}` and `publicConfig/promo` are world-readable in `firestore.rules`
("a price list is public information, and the signed-out register screen needs
it"), so `seo/plans.mjs` reads them over plain REST with the web API key — no
service account.

This is not optional tidiness. The constants in
`PlanCatalog.seedDefaults` are only a seed; the console had since moved every
tier to a tenth of them, and the site spent its first day quoting ₹999–₹9,999
against a real ₹99–₹999. The same drift had the AI assistant listed as MAX-only
when the console had already unlocked it on Pro.

So: **no page writes a price, a tier name, or which tiers include a feature by
hand.** Everything routes through the helpers in `plans.mjs` —
`priceLabel`, `listLabel`, `listPriceRange`, `aiTiers`, `nonAiTiers`,
`featuredId`. Change a tier in the console, rebuild, and every sentence follows.

Resolution order is Firestore → `seo/assets/plans.json` (the last successful
fetch, committed) → the compiled seeds. **The seed path fails the build**, because
publishing prices that are ten times wrong is worse than not publishing;
override with `ALLOW_SEED_PRICES=1` only if you mean it.

`build.mjs` therefore imports the page modules *dynamically*, after the
catalogue resolves — pages read `plans` at module scope, and a static import
would be hoisted above the fetch and capture the seeds.

The founding-member offer's `claimedCount` is **advisory** (`PromoConfig` says
so outright: nothing counts signups atomically). The site renders the headline
and subtext the console owns and never presents the count as a live countdown
or promises the offer ends at the cap.

## Rules for content here

- **Never claim a feature the app does not have.** `site.mjs` mirrors
  `feature_map.dart`, and the tiers come live from the console, for exactly
  this reason. The
  GST pages say plainly what is *not* supported (no GSTR filing, no CGST/SGST
  split, no HSN master) because discovering that in the last week of a quarter
  is worse than reading it here.
- **Never quote a price the product does not charge.** Every tier is at ₹0
  during launch; the list price is shown struck through.
- Prices, limits and which tiers unlock the AI assistant are read from the
  console at build time — never edit them here. The feature count and the
  feature groups are mirrored from Dart; if you change those, change them here.
