import { site, nav } from './site.mjs';

/* ------------------------------------------------------------------ */
/* escaping                                                            */
/* ------------------------------------------------------------------ */

export const esc = (s) =>
  String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

/** JSON-LD must not be able to close its own <script> tag. */
const jsonSafe = (obj) =>
  JSON.stringify(obj, null, 0).replace(/</g, '\\u003c').replace(/>/g, '\\u003e');

export const abs = (path) =>
  path.startsWith('http') ? path : site.origin + (path.startsWith('/') ? path : '/' + path);

/* ------------------------------------------------------------------ */
/* brand marks (inline SVG — no request, sharp at any DPR, themeable)  */
/* ------------------------------------------------------------------ */

const logoMark = `<svg class="brand__mark" viewBox="0 0 32 32" width="28" height="28" aria-hidden="true" focusable="false"><rect width="32" height="32" rx="8" fill="url(#sskg)"/><path d="M8 11h16M8 16h16M8 21h10" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/><defs><linearGradient id="sskg" x1="0" y1="0" x2="32" y2="32" gradientUnits="userSpaceOnUse"><stop stop-color="#0F766E"/><stop offset="1" stop-color="#0891B2"/></linearGradient></defs></svg>`;

/* ------------------------------------------------------------------ */
/* chrome                                                              */
/* ------------------------------------------------------------------ */

function header(current) {
  const links = nav
    .map((n) => {
      const on = current === n.href || (n.href !== '/' && current.startsWith(n.href));
      return `<li><a href="${n.href}"${on ? ' aria-current="page"' : ''}>${esc(n.label)}</a></li>`;
    })
    .join('');
  return `<header class="site-head">
  <div class="wrap site-head__in">
    <a class="brand" href="/">${logoMark}<span>SmartShelf<b>Kart</b></span></a>
    <input type="checkbox" id="navtog" class="navtog" hidden>
    <label for="navtog" class="navbtn" aria-hidden="true"><span></span><span></span><span></span></label>
    <nav class="site-nav" aria-label="Primary"><ul>${links}</ul></nav>
    <a class="btn btn--sm" href="${site.appUrl}" data-app-link>Open the app</a>
  </div>
</header>`;
}

function footer() {
  return `<footer class="site-foot">
  <div class="wrap">
    <div class="site-foot__grid">
      <div class="site-foot__brand">
        <a class="brand" href="/">${logoMark}<span>SmartShelf<b>Kart</b></span></a>
        <p>Inventory, orders, billing and reports for small teams — on the web, Android and iOS, sharing one live database.</p>
        <p class="site-foot__made">Built with Flutter and Firebase in India.</p>
      </div>
      <div>
        <h2>Product</h2>
        <ul>
          <li><a href="/features">All features</a></li>
          <li><a href="/features/barcode-inventory-management">Barcode inventory</a></li>
          <li><a href="/features/low-stock-alerts-and-reorder-points">Low-stock alerts</a></li>
          <li><a href="/features/purchase-orders-and-sales-orders">Purchase &amp; sales orders</a></li>
          <li><a href="/features/gst-billing-and-invoicing">Billing &amp; invoicing</a></li>
          <li><a href="/features/inventory-reports-and-analytics">Reports</a></li>
          <li><a href="/features/ai-inventory-assistant">Nova AI assistant</a></li>
          <li><a href="/pricing">Pricing</a></li>
        </ul>
      </div>
      <div>
        <h2>Free tools</h2>
        <ul>
          <li><a href="/tools/reorder-point-calculator">Reorder point calculator</a></li>
          <li><a href="/tools/safety-stock-calculator">Safety stock calculator</a></li>
          <li><a href="/tools/economic-order-quantity-calculator">EOQ calculator</a></li>
          <li><a href="/tools/inventory-turnover-calculator">Inventory turnover calculator</a></li>
        </ul>
        <h2>Compare</h2>
        <ul>
          <li><a href="/compare/inventory-management-software-vs-excel">vs. Excel &amp; Google Sheets</a></li>
          <li><a href="/compare/free-inventory-management-software-india">Free inventory software in India</a></li>
        </ul>
      </div>
      <div>
        <h2>Guides</h2>
        <ul>
          <li><a href="/blog">All guides</a></li>
          <li><a href="/blog/what-is-inventory-management">What is inventory management?</a></li>
          <li><a href="/blog/reorder-point-formula">Reorder point formula</a></li>
          <li><a href="/blog/safety-stock-formula">Safety stock formula</a></li>
          <li><a href="/blog/abc-analysis-inventory">ABC analysis</a></li>
          <li><a href="/blog/inventory-turnover-ratio">Inventory turnover ratio</a></li>
        </ul>
        <h2>Company</h2>
        <ul>
          <li><a href="/about">About</a></li>
          <li><a href="/contact">Contact</a></li>
          <li><a href="/privacy-policy">Privacy policy</a></li>
          <li><a href="/terms">Terms</a></li>
        </ul>
      </div>
    </div>
    <div class="site-foot__bar">
      <p>&copy; ${new Date().getFullYear()} SmartShelfKart. All rights reserved.</p>
      <p><a href="${site.playStoreUrl}" rel="noopener">Android app on Google Play</a> &middot; <a href="${site.appUrl}" data-app-link>Web app</a></p>
    </div>
  </div>
</footer>`;
}

/* ------------------------------------------------------------------ */
/* structured data                                                     */
/* ------------------------------------------------------------------ */

export const organizationLd = {
  '@type': 'Organization',
  '@id': site.origin + '/#organization',
  name: site.name,
  url: site.origin + '/',
  logo: {
    '@type': 'ImageObject',
    '@id': site.origin + '/#logo',
    url: site.origin + '/static/logo-512.png',
    width: 512,
    height: 512,
  },
  sameAs: [site.playStoreUrl, site.github],
  contactPoint: [
    {
      '@type': 'ContactPoint',
      contactType: 'customer support',
      email: site.email,
      availableLanguage: ['English', 'Hindi'],
    },
  ],
};

export const websiteLd = {
  '@type': 'WebSite',
  '@id': site.origin + '/#website',
  url: site.origin + '/',
  name: site.name,
  publisher: { '@id': site.origin + '/#organization' },
  inLanguage: 'en',
};

export function breadcrumbLd(trail) {
  return {
    '@type': 'BreadcrumbList',
    '@id': '#breadcrumbs',
    itemListElement: trail.map((t, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: t.label,
      item: abs(t.href),
    })),
  };
}

export function faqLd(faqs) {
  return {
    '@type': 'FAQPage',
    mainEntity: faqs.map((f) => ({
      '@type': 'Question',
      name: f.q,
      acceptedAnswer: { '@type': 'Answer', text: f.a.replace(/<[^>]+>/g, '') },
    })),
  };
}

/* ------------------------------------------------------------------ */
/* visible breadcrumbs                                                 */
/* ------------------------------------------------------------------ */

function breadcrumbNav(trail) {
  if (!trail || trail.length < 2) return '';
  const items = trail
    .map((t, i) =>
      i === trail.length - 1
        ? `<li><span aria-current="page">${esc(t.label)}</span></li>`
        : `<li><a href="${t.href}">${esc(t.label)}</a></li>`
    )
    .join('');
  return `<nav class="crumbs" aria-label="Breadcrumb"><div class="wrap"><ol>${items}</ol></div></nav>`;
}

/* ------------------------------------------------------------------ */
/* the shell                                                           */
/* ------------------------------------------------------------------ */

/**
 * @param {object} p
 * @param {string} p.path       canonical path, e.g. "/tools/eoq-calculator"
 * @param {string} p.title      <title>; keep under ~60 chars
 * @param {string} p.description meta description; 140-160 chars
 * @param {string} p.body       page HTML (inside <main>)
 * @param {Array}  [p.trail]    breadcrumb trail
 * @param {Array}  [p.schema]   extra JSON-LD nodes
 * @param {string} [p.cssHref]  hashed stylesheet path
 * @param {boolean}[p.noindex]
 * @param {string} [p.head]     extra head markup
 * @param {string} [p.script]   extra end-of-body script
 * @param {string} [p.ogType]
 */
export function renderPage(p) {
  const canonical = abs(p.path);
  const ogImage = abs(p.image || '/static/og-default.png');
  const graph = [organizationLd, websiteLd];
  if (p.trail && p.trail.length > 1) graph.push(breadcrumbLd(p.trail));
  for (const node of p.schema || []) graph.push(node);

  const ld = { '@context': 'https://schema.org', '@graph': graph };

  return `<!DOCTYPE html>
<html lang="${site.lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(p.title)}</title>
<meta name="description" content="${esc(p.description)}">
<link rel="canonical" href="${canonical}">
${p.noindex ? '<meta name="robots" content="noindex, follow">' : '<meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1">'}
<meta name="theme-color" content="${site.themeColor}">
<meta name="color-scheme" content="light dark">
<meta property="og:type" content="${p.ogType || 'website'}">
<meta property="og:site_name" content="${site.name}">
<meta property="og:locale" content="${site.locale}">
<meta property="og:title" content="${esc(p.ogTitle || p.title)}">
<meta property="og:description" content="${esc(p.description)}">
<meta property="og:url" content="${canonical}">
<meta property="og:image" content="${ogImage}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="${esc(site.name)} — inventory management software">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(p.ogTitle || p.title)}">
<meta name="twitter:description" content="${esc(p.description)}">
<meta name="twitter:image" content="${ogImage}">
<link rel="icon" href="/favicon.png" type="image/png">
<link rel="apple-touch-icon" href="/icons/Icon-192.png">
<link rel="sitemap" type="application/xml" href="/sitemap.xml">
<link rel="stylesheet" href="${p.cssHref}">
${p.head || ''}
<script type="application/ld+json">${jsonSafe(ld)}</script>
</head>
<body>
<a class="skip" href="#main">Skip to content</a>
${header(p.path)}
${breadcrumbNav(p.trail)}
<main id="main">
${p.body}
</main>
${footer()}
${p.script || ''}
</body>
</html>
`;
}
