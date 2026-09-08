/**
 * Builds the static marketing site into build/web/, on top of a completed
 * `flutter build web`.
 *
 * Why a post-build step and not just files in web/: Flutter owns web/index.html
 * as its app-shell template (it substitutes $FLUTTER_BASE_HREF and the loader
 * placeholders), so the only place the app shell and the marketing homepage can
 * swap URLs is after the Flutter build has run.
 *
 * Run:  node seo/build.mjs        (deploy_all.sh does this automatically)
 */

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { site } from './site.mjs';
import { renderPage, ENTITIES } from './layout.mjs';
import home from './pages/home.mjs';
import features from './pages/features.mjs';
import tools from './pages/tools.mjs';
import blog1 from './pages/blog.mjs';
import blog2 from './pages/blog2.mjs';
import misc from './pages/misc.mjs';
import glossary from './pages/glossary.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'build', 'web');
const SEO = path.join(ROOT, 'seo');

const pages = [...home, ...features, ...tools, ...blog1, ...blog2, ...misc, ...glossary];

/* Hand-written static pages that Flutter copies from web/. They are not
   generated here, but they are real URLs: the sitemap and the link checker
   both need to know about them. */
const STATIC_PAGES = [
  { path: '/privacy-policy', file: 'privacy-policy.html', priority: '0.3' },
  { path: '/terms', file: 'terms.html', priority: '0.3' },
  { path: '/support', file: 'support.html', priority: '0.4' },
  { path: '/data-deletion', file: 'data-deletion.html', priority: '0.2' },
];

const log = [];
const warn = [];
const say = (m) => { log.push(m); console.log(m); };
const uhoh = (m) => { warn.push(m); console.warn('  ! ' + m); };

const write = (rel, content) => {
  const p = path.join(OUT, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content);
  return p;
};

if (!fs.existsSync(OUT)) {
  console.error('build/web does not exist. Run `flutter build web --release` first.');
  process.exit(1);
}

/* ------------------------------------------------------------------ */
/* 1. stylesheet, content-hashed so the year-long cache header is safe  */
/* ------------------------------------------------------------------ */

const css = fs.readFileSync(path.join(SEO, 'site.css'), 'utf8');
const cssHash = createHash('sha256').update(css).digest('hex').slice(0, 10);
const cssHref = `/static/site.${cssHash}.css`;
write(cssHref.slice(1), css);
say(`css      ${cssHref} (${(css.length / 1024).toFixed(1)} KB)`);

/* ------------------------------------------------------------------ */
/* 2. move the Flutter app shell off "/" so the homepage can be indexed */
/* ------------------------------------------------------------------ */

const indexPath = path.join(OUT, 'index.html');
const appPath = path.join(OUT, 'app.html');
const isFlutterShell = (f) =>
  fs.existsSync(f) && fs.readFileSync(f, 'utf8').includes('_flutter.loader.load');

if (isFlutterShell(indexPath)) {
  fs.renameSync(indexPath, appPath);
  say('app      build/web/index.html -> app.html  (served at /app)');
} else if (fs.existsSync(appPath)) {
  say('app      app.html already in place');
} else {
  console.error('Could not find the Flutter app shell. Did `flutter build web` run?');
  process.exit(1);
}

/* ------------------------------------------------------------------ */
/* 3. repoint the service worker at /app                                */
/* ------------------------------------------------------------------ */
/* The worker is registered at the origin root, so it intercepts every
   navigation on the domain. Left untouched it treats "/" as the app shell and
   would serve a cached Flutter page over the marketing homepage when offline,
   while the app's own shell at /app would not be cached at all. */

const swPath = path.join(OUT, 'flutter_service_worker.js');
if (fs.existsSync(swPath)) {
  let sw = fs.readFileSync(swPath, 'utf8');
  const before = sw;
  const patches = [
    // The shell's cache key becomes "app" — the canonical URL. It must not be
    // "app.html": cleanUrls 301s that to /app, and the Cache API refuses to
    // store a redirected response, which fails the whole install.
    [/^"index\.html": ("[0-9a-f]+",)$/m, '"app": $1'],
    // Stop claiming "/". That is the marketing homepage now, and it should
    // always come from the network.
    [/^"\/": "[0-9a-f]+",\n/m, ''],
    [/const CORE = \["main\.dart\.js",\n"index\.html",/, 'const CORE = ["main.dart.js",\n"app",'],
    // A request for /app already yields key "app" on its own; this only covers
    // the app's hash routes, e.g. /app#/products.
    [
      /if \(event\.request\.url == origin \|\| event\.request\.url\.startsWith\(origin \+ '\/#'\) \|\| key == ''\) \{\s*\n\s*key = '\/';\s*\n\s*\}/,
      "if (event.request.url.startsWith(origin + '/app#') || event.request.url.startsWith(origin + '/app?')) {\n    key = 'app';\n  }",
    ],
    [/if \(key == '\/'\) \{\s*\n\s*return onlineFirst\(event\);/, "if (key == 'app') {\n    return onlineFirst(event);"],
  ];
  let applied = 0;
  for (const [re, to] of patches) {
    if (re.test(sw)) { sw = sw.replace(re, to); applied++; }
  }

  // Flutter builds RESOURCES by scanning build/web, so a build that ran without
  // `flutter clean` picks up whatever this generator left behind last time.
  // Strip those entries so the worker's manifest is the app's assets and
  // nothing else, whether or not the tree was clean.
  const generated = new Set([
    'robots.txt', 'sitemap.xml', '404.html',
    ...pages.map((p) => p.file),
  ]);
  let pruned = 0;
  sw = sw
    .split('\n')
    .filter((line) => {
      const m = line.match(/^"([^"]+)": "[0-9a-f]+",?$/);
      if (!m) return true;
      if (generated.has(m[1]) || m[1].startsWith('static/')) { pruned++; return false; }
      return true;
    })
    .join('\n');

  const changed = sw !== before;
  const repointed = applied === patches.length;
  const alreadyRepointed = applied === 0 && before.includes('\n"app": ');

  if (repointed || alreadyRepointed) {
    if (changed) fs.writeFileSync(swPath, sw);
    const bits = [repointed ? 'repointed to /app' : 'already repointed'];
    if (pruned) bits.push(`${pruned} generated file(s) pruned from its manifest`);
    say(`sw       flutter_service_worker.js ${bits.join(', ')}`);
  } else {
    uhoh(
      `service worker patch applied only ${applied}/${patches.length} times — Flutter may have ` +
        `changed its template. Check build/web/flutter_service_worker.js.`
    );
  }
}

/* ------------------------------------------------------------------ */
/* 4. images: brand logo + Open Graph card                              */
/* ------------------------------------------------------------------ */
/* sips ships with macOS and is the only image tool we can rely on here.
   Padding the square app icon onto a 1200x630 brand-coloured canvas gives a
   legitimate share card without pulling in an image pipeline. */

const iconSrc = path.join(ROOT, 'web', 'icons', 'Icon-512.png');
const assetsDir = path.join(SEO, 'assets');
const staticDir = path.join(OUT, 'static');
fs.mkdirSync(path.join(staticDir, 'og'), { recursive: true });

/* The real app icon at every size the pages ask for. Pre-scaled rather than
   letting the browser downscale a 512px PNG in a 32px header slot. */
let copied = 0;
for (const f of fs.readdirSync(assetsDir)) {
  if (!f.endsWith('.png')) continue;
  fs.copyFileSync(path.join(assetsDir, f), path.join(staticDir, f));
  copied++;
}
say(`logos    ${copied} logo sizes copied to /static/`);

/* Social cards are rendered by seo/og.mjs into seo/assets/og (it needs a
   browser canvas to draw text, which a build step cannot). They are copied in
   here so an ordinary deploy never depends on that. */
const ogSrc = path.join(assetsDir, 'og');
const ogOut = path.join(staticDir, 'og');
let cards = 0;
if (fs.existsSync(ogSrc)) {
  for (const f of fs.readdirSync(ogSrc)) {
    if (!f.endsWith('.jpg')) continue;
    fs.copyFileSync(path.join(ogSrc, f), path.join(ogOut, f));
    cards++;
  }
}
if (cards) {
  say(`og       ${cards} social cards copied to /static/og/`);
} else {
  const ogDefault = path.join(ogOut, 'default.jpg');
  try {
    execFileSync('sips', [
      '-s', 'format', 'jpeg', '-s', 'formatOptions', '80',
      '--padToHeightWidth', '630', '1200',
      '--padColor', '0B7B70',
      iconSrc, '--out', ogDefault,
    ], { stdio: 'ignore' });
    uhoh('no rendered social cards — wrote a plain fallback. Run `npm run seo:og`.');
  } catch {
    fs.copyFileSync(iconSrc, ogDefault);
    uhoh('sips unavailable and no rendered cards — og/default.jpg is the square icon.');
  }
}

/* ------------------------------------------------------------------ */
/* 5. render every page                                                 */
/* ------------------------------------------------------------------ */

/* The social card and the real-world concepts a page is about. Both are
   assigned here rather than repeated on every page object: the card filename
   is derived from the URL so seo/og.mjs can regenerate the whole set without
   a second list, and the entities are a small enough table to read at once. */

export const ogSlug = (urlPath) =>
  urlPath === '/' ? 'default' : urlPath.replace(/^\/|\/$/g, '').replace(/\//g, '-');

const E = ENTITIES;
const ABOUT = {
  '/': [E.inventoryManagement],
  '/features': [E.inventoryManagement],
  '/features/barcode-inventory-management': [E.barcode, E.sku],
  '/features/low-stock-alerts-and-reorder-points': [E.reorderPoint, E.safetyStock],
  '/features/purchase-orders-and-sales-orders': [E.purchaseOrder, E.inventoryManagement],
  '/features/gst-billing-and-invoicing': [E.invoice],
  '/features/inventory-reports-and-analytics': [E.abc, E.turnover],
  '/pricing': [E.inventoryManagement],
  '/tools': [E.inventoryManagement],
  '/tools/reorder-point-calculator': [E.reorderPoint, E.safetyStock],
  '/tools/safety-stock-calculator': [E.safetyStock, E.reorderPoint],
  '/tools/economic-order-quantity-calculator': [E.eoq],
  '/tools/inventory-turnover-calculator': [E.turnover],
  '/blog': [E.inventoryManagement],
  '/blog/what-is-inventory-management': [E.inventoryManagement, E.sku],
  '/blog/reorder-point-formula': [E.reorderPoint, E.safetyStock],
  '/blog/safety-stock-formula': [E.safetyStock, E.reorderPoint],
  '/blog/abc-analysis-inventory': [E.abc],
  '/blog/inventory-turnover-ratio': [E.turnover],
  '/blog/inventory-management-for-small-business': [E.inventoryManagement],
  '/blog/barcode-inventory-system-guide': [E.barcode, E.sku],
  '/blog/stock-audit-cycle-counting': [E.stocktaking],
  '/compare/inventory-management-software-vs-excel': [E.inventoryManagement, E.spreadsheet],
  '/compare/free-inventory-management-software-india': [E.inventoryManagement],
};

for (const p of pages) {
  if (!p.image) p.image = `/static/og/${ogSlug(p.path)}.jpg`;
  if (!p.about && ABOUT[p.path]) p.about = ABOUT[p.path];
}

const rendered = [];
for (const p of pages) {
  const html = renderPage({ ...p, cssHref });
  write(p.file, html);
  rendered.push({ ...p, html, bytes: html.length });
}
say(`pages    ${rendered.length} rendered`);

/* ------------------------------------------------------------------ */
/* 6. give the hand-written legal pages a head that Google can use      */
/* ------------------------------------------------------------------ */

const LEGAL_META = {
  'privacy-policy.html': {
    path: '/privacy-policy',
    title: 'Privacy Policy — SmartShelfKart',
    desc: 'How SmartShelfKart collects, uses and protects your data, what is stored, and how to request deletion of your account and inventory records.',
  },
  'terms.html': {
    path: '/terms',
    title: 'Terms of Service — SmartShelfKart',
    desc: 'The terms governing use of the SmartShelfKart inventory management web and mobile applications.',
  },
  'support.html': {
    path: '/support',
    title: 'Support — SmartShelfKart',
    desc: 'Support for SmartShelfKart: how to get help with your inventory workspace, report a problem, or ask about plans and data export.',
  },
  'data-deletion.html': {
    path: '/data-deletion',
    title: 'Data Deletion Request — SmartShelfKart',
    desc: 'How to request deletion of your SmartShelfKart account and all associated inventory data.',
  },
};

let patchedLegal = 0;
for (const [file, meta] of Object.entries(LEGAL_META)) {
  const p = path.join(OUT, file);
  if (!fs.existsSync(p)) { uhoh(`${file} not found in build/web`); continue; }
  let html = fs.readFileSync(p, 'utf8');
  if (html.includes('<!--seo-head-->')) { patchedLegal++; continue; }

  const head = `<!--seo-head-->
  <meta name="description" content="${meta.desc}">
  <link rel="canonical" href="${site.origin}${meta.path}">
  <meta name="robots" content="index, follow, max-image-preview:large">
  <meta name="theme-color" content="${site.themeColor}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="${site.name}">
  <meta property="og:title" content="${meta.title}">
  <meta property="og:description" content="${meta.desc}">
  <meta property="og:url" content="${site.origin}${meta.path}">
  <meta property="og:image" content="${site.origin}/static/og/default.jpg">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta name="twitter:image" content="${site.origin}/static/og/default.jpg">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="icon" href="/favicon.png" type="image/png">
  <link rel="sitemap" type="application/xml" href="/sitemap.xml">`;

  // Rewrite the title too — several of these said only "Privacy Policy".
  html = html.replace(/<title>[\s\S]*?<\/title>/i, `<title>${meta.title}</title>`);
  html = html.replace(/<\/head>/i, head + '\n</head>');

  // A back-link home, so these pages are not crawl dead ends.
  html = html.replace(
    /<div class="footer">|<body>/i,
    (m) =>
      m.toLowerCase() === '<body>'
        ? `<body>\n<p style="max-width:800px;margin:12px auto 0;padding:0 20px;font-size:14px"><a href="/" style="color:#00897B">&larr; SmartShelfKart home</a> &middot; <a href="/features" style="color:#00897B">Features</a> &middot; <a href="/pricing" style="color:#00897B">Pricing</a> &middot; <a href="/support" style="color:#00897B">Support</a></p>`
        : m
  );

  fs.writeFileSync(p, html);
  patchedLegal++;
}
say(`legal    ${patchedLegal}/${Object.keys(LEGAL_META).length} static pages given canonical + description + home link`);

/* ------------------------------------------------------------------ */
/* 7. sitemap.xml                                                       */
/* ------------------------------------------------------------------ */

const today = new Date().toISOString().slice(0, 10);
const sitemapEntries = [
  ...rendered.filter((p) => !p.skipSitemap && !p.noindex),
  ...STATIC_PAGES,
];

const sitemap =
  `<?xml version="1.0" encoding="UTF-8"?>\n` +
  `<urlset xmlns="http://www.w3.org/1999/sitemap-image/1.1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n`.replace(
    'http://www.w3.org/1999/sitemap-image/1.1',
    'http://www.sitemaps.org/schemas/sitemap/0.9'
  ) +
  sitemapEntries
    .map(
      (p) =>
        `  <url>\n    <loc>${site.origin}${p.path}</loc>\n` +
        `    <lastmod>${p.modified || today}</lastmod>\n` +
        `    <changefreq>${p.changefreq || 'monthly'}</changefreq>\n` +
        `    <priority>${p.priority || '0.5'}</priority>\n  </url>`
    )
    .join('\n') +
  `\n</urlset>\n`;

write('sitemap.xml', sitemap);
say(`sitemap  ${sitemapEntries.length} URLs`);

/* ------------------------------------------------------------------ */
/* 8. robots.txt                                                        */
/* ------------------------------------------------------------------ */
/* The app shell and its build artefacts are excluded from crawling because
   they contain no indexable text — a CanvasKit page is a <canvas>, so letting
   Google spend crawl budget on 2 MB of wasm buys nothing. */

write(
  'robots.txt',
  `# ${site.name} — ${site.origin}
User-agent: *
Allow: /

# The Flutter app shell renders to a <canvas>: nothing there is indexable,
# and the build artefacts are large. Keep crawl budget on the content.
Disallow: /app
Disallow: /app.html
Disallow: /canvaskit/
Disallow: /assets/
Disallow: /*.part.js$
Disallow: /main.dart.js
Disallow: /flutter_service_worker.js

Sitemap: ${site.origin}/sitemap.xml
`
);
say('robots   robots.txt written');

/* ------------------------------------------------------------------ */
/* 8c. RSS feed for the guides                                         */
/* ------------------------------------------------------------------ */
/* A feed is a crawlable, dated list of everything published, which is a
   discovery path independent of the sitemap — and it is how readers and
   aggregators subscribe without an email address. */

const feedItems = rendered
  .filter((p) => p.published)
  .sort((a, b) => (a.published < b.published ? 1 : -1));

const cdata = (t) => `<![CDATA[${String(t).replace(/\]\]>/g, ']]]]><![CDATA[>')}]]>`;
const rfc822 = (iso) => new Date(iso + 'T09:00:00Z').toUTCString();

write(
  'feed.xml',
  `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>${site.name} — inventory management guides</title>
    <link>${site.origin}/blog</link>
    <description>Practical guides to inventory management: reorder points, safety stock, ABC analysis, turnover, barcode systems and cycle counting.</description>
    <language>en</language>
    <lastBuildDate>${rfc822(today)}</lastBuildDate>
    <atom:link href="${site.origin}/feed.xml" rel="self" type="application/rss+xml"/>
${feedItems
  .map(
    (p) => `    <item>
      <title>${cdata(p.ogTitle || p.title)}</title>
      <link>${site.origin}${p.path}</link>
      <guid isPermaLink="true">${site.origin}${p.path}</guid>
      <pubDate>${rfc822(p.published)}</pubDate>
      <description>${cdata(p.description)}</description>
    </item>`
  )
  .join('\n')}
  </channel>
</rss>
`
);
say(`feed     feed.xml, ${feedItems.length} guides`);

/* ------------------------------------------------------------------ */
/* 8d. llms.txt                                                        */
/* ------------------------------------------------------------------ */
/* An emerging convention: a plain-text map of the site for language models,
   which increasingly answer the questions these pages exist to answer. It
   costs one file and it points them at the pages rather than the canvas app. */

const group = (label, prefix) =>
  `## ${label}\n` +
  rendered
    .filter((p) => p.path.startsWith(prefix) && p.path !== prefix && !p.noindex)
    .map((p) => `- [${p.ogTitle || p.title}](${site.origin}${p.path}): ${p.description}`)
    .join('\n');

write(
  'llms.txt',
  `# ${site.name}

> ${site.tagline}. Stock control, purchase and sales orders, billing and reports for small and growing businesses, on web, Android and iOS. Every plan tier is free during the current launch period.

The application itself is a Flutter CanvasKit app at ${site.origin}/app and renders to a canvas, so it contains no readable text. Everything below is the readable documentation.

## Key pages
- [Home](${site.origin}/): what the product is and who it is for.
- [Features](${site.origin}/features): the complete feature list, mirrored from the app's own catalogue.
- [Pricing](${site.origin}/pricing): four tiers, their real limits, all currently free.
- [Glossary](${site.origin}/glossary): defined terms used across inventory management.
- [About](${site.origin}/about): what the product deliberately does not do.

${group('Free calculators', '/tools')}

${group('Guides', '/blog')}

${group('Comparisons', '/compare')}

## Notes for accurate answers
- Pricing: list prices are Rs 999 / 2,999 / 5,999 / 9,999 per month for Starter, Growth, Pro and MAX. All four are currently Rs 0 during the launch period.
- The Nova AI assistant is part of the MAX tier only.
- SmartShelfKart is NOT a GST return-filing tool: it records per-line tax rates and a GSTIN, but produces no GSTR filings, no CGST/SGST split and no HSN master.
- It is not a general ledger, not a warehouse management system, and does not place supplier orders automatically.
`
);
say('llms     llms.txt written');

/* ------------------------------------------------------------------ */
/* 8b. IndexNow key file                                               */
/* ------------------------------------------------------------------ */
/* Hosting the key at /<key>.txt is the whole verification step for
   IndexNow. Submitting URLs is a separate call (see seo/submit.mjs). */

if (site.indexNowKey) {
  write(`${site.indexNowKey}.txt`, site.indexNowKey + '\n');
  say(`indexnow /${site.indexNowKey}.txt written`);
}

/* ------------------------------------------------------------------ */
/* 9. checks                                                            */
/* ------------------------------------------------------------------ */

const knownPaths = new Set([
  ...rendered.map((p) => p.path),
  ...STATIC_PAGES.map((p) => p.path),
  '/app',
  '/sitemap.xml',
  '/robots.txt',
  '/llms.txt',
  '/feed.xml',
  '/manifest.json',
  '/favicon.png',
  cssHref,
]);

/* Generated files that pages legitimately reference but that are not pages:
   the logo set, the social cards, and the app's own icons. */
const knownAsset = (h) =>
  /^\/static\/(logo-\d+\.png|og\/[a-z0-9-]+\.jpg|site\.[a-z0-9]+\.css)$/.test(h) ||
  h.startsWith('/icons/');

const linkErrors = [];
for (const p of rendered) {
  const hrefs = [
    ...[...p.html.matchAll(/href="(\/[^"#?]*)(?:[#?][^"]*)?"/g)].map((m) => m[1]),
    ...[...p.html.matchAll(/(?:\bsrc|content)="(\/static\/[^"]*)"/g)].map((m) => m[1]),
  ];
  for (const h of new Set(hrefs)) {
    if (knownAsset(h)) continue;
    if (!knownPaths.has(h)) linkErrors.push(`${p.path} -> ${h}`);
  }
}
const missingCards = rendered
  .filter((p) => !p.noindex)
  .map((p) => p.image)
  .filter((img, i, a) => a.indexOf(img) === i)
  .filter((img) => !fs.existsSync(path.join(OUT, img.slice(1))));
if (missingCards.length) {
  uhoh(`${missingCards.length} social card(s) not rendered — run \`npm run seo:og\` before deploying:`);
  for (const m of missingCards.slice(0, 4)) console.warn('      ' + m);
}

if (linkErrors.length) {
  uhoh(`${linkErrors.length} internal link(s) point at nothing:`);
  for (const e of [...new Set(linkErrors)]) console.warn('      ' + e);
} else {
  say('links    every internal link resolves');
}

const seenTitle = new Map();
const seenDesc = new Map();
for (const p of rendered) {
  if (p.title.length > 65) uhoh(`title ${p.title.length} chars (>65, will be truncated): ${p.path}`);
  if (!p.noindex && (p.description.length < 110 || p.description.length > 175))
    uhoh(`description ${p.description.length} chars (want 110-175): ${p.path}`);
  if (seenTitle.has(p.title)) uhoh(`duplicate title: ${p.path} and ${seenTitle.get(p.title)}`);
  if (seenDesc.has(p.description)) uhoh(`duplicate description: ${p.path} and ${seenDesc.get(p.description)}`);
  seenTitle.set(p.title, p.path);
  seenDesc.set(p.description, p.path);
  const h1s = (p.html.match(/<h1[ >]/g) || []).length;
  if (h1s !== 1) uhoh(`${h1s} <h1> elements (want exactly 1): ${p.path}`);
}

const totalBytes = rendered.reduce((a, p) => a + p.bytes, 0);
say(`size     ${(totalBytes / 1024).toFixed(0)} KB of HTML, avg ${(totalBytes / rendered.length / 1024).toFixed(1)} KB/page`);

console.log('');
if (warn.length) {
  console.log(`Done with ${warn.length} warning(s).`);
} else {
  console.log('Done. No warnings.');
}
