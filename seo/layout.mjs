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
/* brand                                                               */
/* ------------------------------------------------------------------ */

/* The real app icon, at the size it is drawn. Explicit width/height and a
   srcset so it is crisp on a 2x screen and reserves its box before it loads —
   a logo in a sticky header is the easiest layout shift on the page to cause
   and the easiest to prevent. */
const logoImg = (px, cls = 'brand__mark', priority = false) =>
  `<img class="${cls}" src="/static/logo-${px}.png" ` +
  `srcset="/static/logo-${px}.png 1x, /static/logo-${px * 2}.png 2x" ` +
  `width="${px}" height="${px}" alt=""${priority ? ' fetchpriority="high" decoding="sync"' : ' loading="lazy" decoding="async"'}>`;

const brandLink = (px, priority) =>
  `<a class="brand" href="/">${logoImg(px, 'brand__mark', priority)}<span class="brand__word">SmartShelf<em>Kart</em></span></a>`;

/* ------------------------------------------------------------------ */
/* chrome                                                              */
/* ------------------------------------------------------------------ */

const themeToggle = `<button class="themebtn" type="button" data-theme-toggle aria-label="Switch colour theme" title="Switch colour theme">
  <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round">
    <g class="ico-sun"><circle cx="12" cy="12" r="4.2"/><path d="M12 2.6v2.2M12 19.2v2.2M2.6 12h2.2M19.2 12h2.2M5.4 5.4l1.6 1.6M17 17l1.6 1.6M18.6 5.4L17 7M7 17l-1.6 1.6"/></g>
    <g class="ico-moon"><path d="M20 13.4A8.2 8.2 0 0 1 10.6 4a8.4 8.4 0 1 0 9.4 9.4Z"/></g>
    <g class="ico-auto"><circle cx="12" cy="12" r="8.4"/><path d="M12 3.6v16.8" /><path d="M12 20.4a8.4 8.4 0 0 0 0-16.8Z" fill="currentColor" stroke="none"/></g>
  </svg>
</button>`;

function header(current) {
  const links = nav
    .map((n) => {
      const on = current === n.href || (n.href !== '/' && current.startsWith(n.href + '/'));
      return `<li><a href="${n.href}"${on ? ' aria-current="page"' : ''}>${esc(n.label)}</a></li>`;
    })
    .join('');
  return `<header class="site-head">
  <div class="wrap site-head__in">
    ${brandLink(32, true)}
    <input type="checkbox" id="navtog" class="navtog" hidden>
    <nav class="site-nav" aria-label="Primary"><ul>${links}</ul></nav>
    <div class="site-head__act">
      ${themeToggle}
      <a class="btn btn--sm" href="${site.appUrl}" data-app-link><span class="lbl-full">Open the app</span><span class="lbl-tight">Open app</span></a>
      <label for="navtog" class="navbtn" aria-hidden="true"><span></span><span></span><span></span></label>
    </div>
  </div>
</header>`;
}

function footer() {
  const col = (title, items) =>
    `<div class="site-foot__col"><h2>${esc(title)}</h2><ul>${items
      .map(([href, label]) => `<li><a href="${href}">${label}</a></li>`)
      .join('')}</ul></div>`;

  return `<footer class="site-foot">
  <div class="wrap">
    <div class="site-foot__grid">
      <div class="site-foot__brand">
        ${brandLink(36)}
        <p>Inventory, orders, billing and reports for small teams — on the web, Android and iOS, sharing one live database.</p>
        <p class="site-foot__made">Built with Flutter and Firebase in India.</p>
        <div class="site-foot__links">
          <a href="${site.playStoreUrl}" rel="noopener">Google Play</a>
          <a href="${site.appUrl}" data-app-link>Web app</a>
          <a href="/feed.xml">RSS</a>
        </div>
      </div>
      ${col('Product', [
        ['/features', 'All features'],
        ['/features/barcode-inventory-management', 'Barcode inventory'],
        ['/features/low-stock-alerts-and-reorder-points', 'Low-stock alerts'],
        ['/features/purchase-orders-and-sales-orders', 'Purchase &amp; sales orders'],
        ['/features/gst-billing-and-invoicing', 'Billing &amp; invoicing'],
        ['/features/inventory-reports-and-analytics', 'Reports'],
        ['/features/ai-inventory-assistant', 'Nova AI assistant'],
        ['/pricing', 'Pricing'],
      ])}
      ${col('Free tools', [
        ['/tools/reorder-point-calculator', 'Reorder point calculator'],
        ['/tools/safety-stock-calculator', 'Safety stock calculator'],
        ['/tools/economic-order-quantity-calculator', 'EOQ calculator'],
        ['/tools/inventory-turnover-calculator', 'Turnover calculator'],
        ['/glossary', 'Inventory glossary'],
        ['/compare/inventory-management-software-vs-excel', 'vs. Excel &amp; Sheets'],
        ['/compare/free-inventory-management-software-india', 'Free inventory software'],
      ])}
      ${col('Guides', [
        ['/blog', 'All guides'],
        ['/blog/what-is-inventory-management', 'What is inventory management?'],
        ['/blog/reorder-point-formula', 'Reorder point formula'],
        ['/blog/safety-stock-formula', 'Safety stock formula'],
        ['/blog/abc-analysis-inventory', 'ABC analysis'],
        ['/blog/inventory-turnover-ratio', 'Inventory turnover'],
      ])}
      ${col('Company', [
        ['/about', 'About'],
        ['/contact', 'Contact'],
        ['/support', 'Support'],
        ['/privacy-policy', 'Privacy policy'],
        ['/terms', 'Terms'],
        ['/data-deletion', 'Delete my data'],
      ])}
    </div>
    <div class="site-foot__bar">
      <p>&copy; ${new Date().getFullYear()} SmartShelfKart. All rights reserved.</p>
      <p>Free on every plan tier during the launch period.</p>
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
    contentUrl: site.origin + '/static/logo-512.png',
    width: 512,
    height: 512,
    caption: site.name,
  },
  image: { '@id': site.origin + '/#logo' },
  description:
    'SmartShelfKart makes inventory management software for small and growing businesses, covering stock control, purchase and sales orders, billing and reporting on web, Android and iOS.',
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
  description: site.tagline,
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

/**
 * Well-known encyclopaedia entries for the concepts these pages are about.
 * Naming the entity a page covers — rather than only the words on it — is what
 * lets a search engine connect "reorder point" here to the same concept
 * elsewhere, instead of treating it as an unfamiliar string.
 */
export const ENTITIES = {
  inventoryManagement: { name: 'Inventory management', sameAs: 'https://en.wikipedia.org/wiki/Inventory_management' },
  reorderPoint: { name: 'Reorder point', sameAs: 'https://en.wikipedia.org/wiki/Reorder_point' },
  safetyStock: { name: 'Safety stock', sameAs: 'https://en.wikipedia.org/wiki/Safety_stock' },
  eoq: { name: 'Economic order quantity', sameAs: 'https://en.wikipedia.org/wiki/Economic_order_quantity' },
  turnover: { name: 'Inventory turnover', sameAs: 'https://en.wikipedia.org/wiki/Inventory_turnover' },
  abc: { name: 'ABC analysis', sameAs: 'https://en.wikipedia.org/wiki/ABC_analysis' },
  barcode: { name: 'Barcode', sameAs: 'https://en.wikipedia.org/wiki/Barcode' },
  stocktaking: { name: 'Stocktaking', sameAs: 'https://en.wikipedia.org/wiki/Stocktaking' },
  purchaseOrder: { name: 'Purchase order', sameAs: 'https://en.wikipedia.org/wiki/Purchase_order' },
  invoice: { name: 'Invoice', sameAs: 'https://en.wikipedia.org/wiki/Invoice' },
  sku: { name: 'Stock keeping unit', sameAs: 'https://en.wikipedia.org/wiki/Stock_keeping_unit' },
  spreadsheet: { name: 'Spreadsheet', sameAs: 'https://en.wikipedia.org/wiki/Spreadsheet' },
};

export const thing = (e) => ({ '@type': 'Thing', name: e.name, sameAs: e.sameAs });

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

/* Runs before first paint so a chosen theme never flashes the other one.
   Three states, matching how the CSS is written: an explicit choice stamps the
   root element; "system" stamps nothing and lets prefers-color-scheme decide. */
const themeBoot = `<script>(function(){try{var t=localStorage.getItem('ssk-theme');if(t==='dark'||t==='light')document.documentElement.setAttribute('data-theme',t);}catch(e){}})();</script>`;

const themeScript = `<script>
(function(){
  var order=['system','light','dark'];
  var root=document.documentElement;
  function current(){try{return localStorage.getItem('ssk-theme')||'system';}catch(e){return 'system';}}
  function apply(v){
    if(v==='system'){root.removeAttribute('data-theme');}else{root.setAttribute('data-theme',v);}
    root.setAttribute('data-theme-pref',v);
    var m=v==='system'?'Colour theme: match system':'Colour theme: '+v;
    [].forEach.call(document.querySelectorAll('[data-theme-toggle]'),function(b){
      b.setAttribute('title',m);b.setAttribute('aria-label',m+'. Click to change.');});
  }
  apply(current());
  document.addEventListener('click',function(e){
    var b=e.target.closest && e.target.closest('[data-theme-toggle]');
    if(!b)return;
    var next=order[(order.indexOf(current())+1)%order.length];
    try{next==='system'?localStorage.removeItem('ssk-theme'):localStorage.setItem('ssk-theme',next);}catch(err){}
    apply(next);
  });
})();
</script>`;

/**
 * @param {object} p
 * @param {string} p.path        canonical path
 * @param {string} p.title       <title>; under ~62 chars
 * @param {string} p.description meta description; 110-175 chars
 * @param {string} p.body        page HTML (inside <main>)
 * @param {Array}  [p.trail]     breadcrumb trail
 * @param {Array}  [p.schema]    extra JSON-LD nodes
 * @param {Array}  [p.about]     ENTITIES this page is about
 * @param {string} [p.image]     OG image path
 */
export function renderPage(p) {
  const canonical = abs(p.path);
  const ogImage = abs(p.image || '/static/og/default.jpg');
  const graph = [organizationLd, websiteLd];

  /* A WebPage node ties the page to the site, its image and its dates, and
     carries the entities it is about. Without it each page's Article or FAQ
     floats free of the organisation that published it. */
  const webPage = {
    '@type': p.pageType || 'WebPage',
    '@id': canonical + '#webpage',
    url: canonical,
    name: p.ogTitle || p.title,
    description: p.description,
    isPartOf: { '@id': site.origin + '/#website' },
    about: (p.about || []).map(thing),
    primaryImageOfPage: { '@type': 'ImageObject', url: ogImage, width: 1200, height: 630 },
    inLanguage: 'en',
    ...(p.published ? { datePublished: p.published } : {}),
    ...(p.modified || p.published ? { dateModified: p.modified || p.published } : {}),
    ...(p.trail && p.trail.length > 1 ? { breadcrumb: { '@id': canonical + '#breadcrumbs' } } : {}),
  };
  if (!webPage.about.length) delete webPage.about;
  graph.push(webPage);

  if (p.trail && p.trail.length > 1) {
    graph.push({ ...breadcrumbLd(p.trail), '@id': canonical + '#breadcrumbs' });
  }
  for (const node of p.schema || []) graph.push(node);

  const ld = { '@context': 'https://schema.org', '@graph': graph };

  return `<!DOCTYPE html>
<html lang="${site.lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
${themeBoot}
<title>${esc(p.title)}</title>
<meta name="description" content="${esc(p.description)}">
<link rel="canonical" href="${canonical}">
${p.noindex ? '<meta name="robots" content="noindex, follow">' : '<meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1">'}
<meta name="theme-color" content="#0B7B70" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#08100F" media="(prefers-color-scheme: dark)">
<meta name="color-scheme" content="light dark">
<meta property="og:type" content="${p.ogType || 'website'}">
<meta property="og:site_name" content="${site.name}">
<meta property="og:locale" content="${site.locale}">
<meta property="og:title" content="${esc(p.ogTitle || p.title)}">
<meta property="og:description" content="${esc(p.description)}">
<meta property="og:url" content="${canonical}">
<meta property="og:image" content="${ogImage}">
<meta property="og:image:type" content="image/jpeg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="${esc(p.ogTitle || p.title)} — ${esc(site.name)}">
${p.published ? `<meta property="article:published_time" content="${p.published}">` : ''}
${p.modified ? `<meta property="article:modified_time" content="${p.modified}">` : ''}
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(p.ogTitle || p.title)}">
<meta name="twitter:description" content="${esc(p.description)}">
<meta name="twitter:image" content="${ogImage}">
<link rel="icon" href="/favicon.png" type="image/png">
<link rel="apple-touch-icon" href="/icons/Icon-192.png">
<link rel="sitemap" type="application/xml" href="/sitemap.xml">
<link rel="alternate" type="application/rss+xml" title="SmartShelfKart guides" href="/feed.xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="preload" as="image" href="/static/logo-32.png" imagesrcset="/static/logo-32.png 1x, /static/logo-64.png 2x" fetchpriority="high">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Sora:wght@600;700;800&family=Inter:wght@400;500;600&family=IBM+Plex+Mono:wght@500&display=swap">
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
${themeScript}
${p.script || ''}
</body>
</html>
`;
}
