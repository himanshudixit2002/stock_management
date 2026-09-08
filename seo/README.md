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
| `site.mjs` | Brand, nav, plan tiers, feature catalogue. **Mirrors real app data** — plans come from `lib/models/company_plan_model.dart`, features from `lib/config/feature_map.dart`. |
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

## Rules for content here

- **Never claim a feature the app does not have.** `site.mjs` mirrors
  `feature_map.dart` and `company_plan_model.dart` for exactly this reason. The
  GST pages say plainly what is *not* supported (no GSTR filing, no CGST/SGST
  split, no HSN master) because discovering that in the last week of a quarter
  is worse than reading it here.
- **Never quote a price the product does not charge.** Every tier is at ₹0
  during launch; the list price is shown struck through.
- Prices, limits and the feature count are the app's real values. If you change
  them in Dart, change them here.
