import { esc } from './layout.mjs';
import { site } from './site.mjs';

export const wrap = (inner, cls = '') =>
  `<div class="wrap${cls ? ' ' + cls : ''}">${inner}</div>`;

export function section({ id, eyebrow, title, lead, body, alt = false, tight = false }) {
  const head =
    title || lead
      ? `<div class="sec__head">${eyebrow ? `<p class="eyebrow">${esc(eyebrow)}</p>` : ''}${
          title ? `<h2>${title}</h2>` : ''
        }${lead ? `<p>${lead}</p>` : ''}</div>`
      : '';
  return `<section class="sec${alt ? ' sec--alt' : ''}${tight ? ' sec--tight' : ''}"${
    id ? ` id="${id}"` : ''
  }>${wrap(head + body)}</section>`;
}

export const cards = (items) =>
  `<div class="grid">${items
    .map(
      (c) =>
        `${c.href ? `<a class="card card--link" href="${c.href}">` : '<div class="card">'}` +
        `${c.icon ? icon(c.icon) : ''}` +
        `<h3>${esc(c.title)}</h3><p>${c.body}</p>` +
        `${c.href ? `<span class="card__more">${esc(c.more || 'Read more')} &rarr;</span></a>` : '</div>'}`
    )
    .join('')}</div>`;

export const featureList = (pairs) =>
  `<ul class="featlist">${pairs
    .map(([b, s]) => `<li><b>${esc(b)}</b><span>${esc(s)}</span></li>`)
    .join('')}</ul>`;

export const table = (headers, rows) =>
  `<div class="tablewrap"><table><thead><tr>${headers
    .map((h) => `<th scope="col">${h}</th>`)
    .join('')}</tr></thead><tbody>${rows
    .map((r) => `<tr>${r.map((c, i) => (i === 0 ? `<th scope="row">${c}</th>` : `<td>${c}</td>`)).join('')}</tr>`)
    .join('')}</tbody></table></div>`;

export const faqBlock = (faqs) =>
  `<div class="faq">${faqs
    .map(
      (f) =>
        `<details><summary>${esc(f.q)}</summary>${
          f.a.startsWith('<') ? f.a : `<p>${f.a}</p>`
        }</details>`
    )
    .join('')}</div>`;

export function cta({
  title = 'Start running your stock on something that adds up',
  body = `Open the web app in your browser, or install the Android app. The same workspace, the same live data, no card required.`,
  primary = { href: site.appUrl, label: 'Open the web app' },
  secondary = { href: site.playStoreUrl, label: 'Get it on Google Play' },
} = {}) {
  return `<section class="sec">${wrap(
    `<div class="cta"><h2>${esc(title)}</h2><p>${body}</p><div class="btnrow" style="justify-content:center">` +
      `<a class="btn" href="${primary.href}"${primary.href === site.appUrl ? ' data-app-link' : ''}>${esc(primary.label)}</a>` +
      (secondary
        ? `<a class="btn btn--ghost" href="${secondary.href}" rel="noopener">${esc(secondary.label)}</a>`
        : '') +
      `</div></div>`
  )}</section>`;
}

export const related = (title, links) =>
  `<nav class="related" aria-label="${esc(title)}"><h2>${esc(title)}</h2><ul>${links
    .map((l) => `<li><a href="${l.href}">${esc(l.label)}</a></li>`)
    .join('')}</ul></nav>`;

export const toc = (items) =>
  `<nav class="toc" aria-label="On this page"><h2>On this page</h2><ol>${items
    .map((i) => `<li><a href="#${i.id}">${esc(i.label)}</a></li>`)
    .join('')}</ol></nav>`;

/** ISO date -> "12 March 2026", for visible article bylines. */
export const humanDate = (iso) =>
  new Date(iso + 'T00:00:00Z').toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  });

/** schema.org Article node for a guide. */
export const articleLd = ({ path, title, description, published, modified }) => ({
  '@type': 'Article',
  headline: title,
  description,
  datePublished: published,
  dateModified: modified || published,
  inLanguage: 'en',
  mainEntityOfPage: { '@type': 'WebPage', '@id': site.origin + path },
  author: { '@id': site.origin + '/#organization' },
  publisher: { '@id': site.origin + '/#organization' },
  image: site.origin + '/static/og-default.png',
});

/** schema.org SoftwareApplication node — the product itself. */
export const softwareLd = () => ({
  '@type': 'SoftwareApplication',
  '@id': site.origin + '/#software',
  name: site.name,
  applicationCategory: 'BusinessApplication',
  applicationSubCategory: 'Inventory Management Software',
  operatingSystem: 'Web, Android, iOS',
  url: site.origin + '/',
  downloadUrl: site.playStoreUrl,
  softwareVersion: '1.0.28',
  publisher: { '@id': site.origin + '/#organization' },
  featureList: [
    'Barcode inventory tracking',
    'Low stock alerts and reorder suggestions',
    'Purchase orders and sales orders',
    'Invoicing, payments and credit notes',
    'Batch and expiry tracking',
    'Multi-location stock transfers',
    'Stock takes and cycle counting',
    'Profit and loss, ABC analysis and valuation reports',
    'Role-based access control for staff',
    'Excel import, bulk update and export',
    'Natural-language AI assistant',
  ],
  offers: {
    '@type': 'Offer',
    price: '0',
    priceCurrency: 'INR',
    availability: 'https://schema.org/InStock',
    description: 'Free during the current launch period on every plan tier.',
  },
});

/* ================================================================== */
/* icons                                                               */
/* ================================================================== */

/* Stroke icons drawn on a 24 grid, inheriting currentColor so they take the
   brand colour in both themes without a second copy. */
const ICONS = {
  barcode: '<path d="M3 5v14M6.5 5v14M10 5v10M13.5 5v14M17 5v10M20.5 5v14"/>',
  alert: '<path d="M12 3a6 6 0 0 0-6 6c0 4-1.5 5.5-2 6h16c-.5-.5-2-2-2-6a6 6 0 0 0-6-6Z"/><path d="M10 19a2 2 0 0 0 4 0"/>',
  orders: '<path d="M6 3h9l4 4v14H6z"/><path d="M15 3v4h4"/><path d="M9.5 12h6M9.5 16h4"/>',
  invoice: '<path d="M5 3h14v18l-3-2-2 2-2-2-2 2-3-2z"/><path d="M9 8h6M9 12h6M9 16h3"/>',
  chart: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
  spark: '<path d="M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9z"/><path d="M18.5 16.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z"/>',
  layers: '<path d="M12 3 3 7.5 12 12l9-4.5z"/><path d="m3 12.5 9 4.5 9-4.5"/><path d="m3 17 9 4.5L21 17"/>',
  shield: '<path d="M12 3 5 6v6c0 4.2 2.9 7.6 7 9 4.1-1.4 7-4.8 7-9V6z"/><path d="m9 12 2 2 4-4"/>',
};

export const icon = (name) =>
  `<span class="ico"><svg viewBox="0 0 24 24" width="21" height="21" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${
    ICONS[name] || ICONS.layers
  }</svg></span>`;

/* ================================================================== */
/* diagrams                                                            */
/* ================================================================== */

/**
 * The classic inventory sawtooth: stock falls as you sell, an order is placed
 * when it crosses the reorder point, and the delivery arrives lead-time days
 * later — ideally just as safety stock is reached. It makes the relationship
 * between the three numbers visible in a way the formula alone does not.
 */
export const sawtoothFigure = (caption) => `
<figure class="fig">
<div class="fig__scroll"><svg viewBox="0 0 720 330" role="img" aria-labelledby="rop-t rop-d">
  <title id="rop-t">Inventory level over time against the reorder point</title>
  <desc id="rop-d">Stock declines as units sell. Each time the level crosses the reorder point an order is placed; the delivery arrives after the lead time, just as stock reaches the safety-stock floor, and the level jumps back to its maximum.</desc>

  <g stroke="var(--line)" stroke-width="1">
    <line x1="58" y1="46"  x2="700" y2="46"/>
    <line x1="58" y1="120" x2="700" y2="120"/>
    <line x1="58" y1="270" x2="700" y2="270"/>
  </g>

  <rect x="58" y="245" width="642" height="25" fill="var(--brand)" opacity=".13"/>
  <line x1="58" y1="245" x2="700" y2="245" stroke="var(--brand)" stroke-width="1.5" stroke-dasharray="2 4" opacity=".7"/>
  <line x1="58" y1="195" x2="700" y2="195" stroke="var(--warn)" stroke-width="1.75" stroke-dasharray="7 5"/>

  <path d="M70 50 L200 195 L250 245 L250 50 L380 195 L430 245 L430 50 L560 195 L610 245 L610 50 L690 139"
        fill="none" stroke="var(--brand)" stroke-width="2.75" stroke-linejoin="round" stroke-linecap="round"/>

  <g fill="var(--warn)">
    <circle cx="200" cy="195" r="4.5"/><circle cx="380" cy="195" r="4.5"/><circle cx="560" cy="195" r="4.5"/>
  </g>
  <g fill="var(--brand)">
    <circle cx="250" cy="245" r="4.5"/><circle cx="430" cy="245" r="4.5"/><circle cx="610" cy="245" r="4.5"/>
  </g>

  <g stroke="var(--fg-fade)" stroke-width="1.3" fill="none">
    <path d="M200 288 L200 296 M250 288 L250 296 M200 292 L250 292"/>
  </g>
  <path d="M244 288.5 L250 292 L244 295.5 Z" fill="var(--fg-fade)"/>

  <line x1="58" y1="46" x2="58" y2="270" stroke="var(--line-hi)" stroke-width="1.5"/>
  <line x1="58" y1="270" x2="700" y2="270" stroke="var(--line-hi)" stroke-width="1.5"/>

  <g font-family="var(--mono)" font-size="13" fill="var(--fg-mut)">
    <text x="50" y="50"  text-anchor="end">max</text>
    <text x="50" y="199" text-anchor="end" fill="var(--warn)">ROP</text>
    <text x="50" y="262" text-anchor="end" fill="var(--brand)">SS</text>
    <text x="50" y="274" text-anchor="end">0</text>
    <text x="225" y="311" text-anchor="middle">lead time</text>
    <text x="205" y="182" fill="var(--warn)">order placed</text>
    <text x="256" y="238" fill="var(--brand)">delivery</text>
  </g>
  <text x="379" y="326" text-anchor="middle" font-family="var(--body)" font-size="13" fill="var(--fg-fade)">time &rarr;</text>
</svg></div>
<p class="fig__hint">Scroll the diagram sideways &rarr;</p>
<figcaption>${caption}</figcaption>
</figure>`;

/**
 * Why a spreadsheet cannot produce a trustworthy report: it stores the current
 * quantity, so changing it destroys the previous one. A ledger stores the
 * movements and derives the quantity, so the same figure carries its history.
 */
export const ledgerFigure = (caption) => `
<figure class="fig">
<div class="fig__scroll"><svg viewBox="0 0 720 300" role="img" aria-labelledby="led-t led-d">
  <title id="led-t">A spreadsheet cell compared with a transaction ledger</title>
  <desc id="led-d">On the left a spreadsheet cell is overtyped from 40 to 37 and the 40 is gone. On the right three recorded movements — a receipt, a sale and a damage write-off — sum to 37, so the quantity is derived and every change keeps its reason, date and author.</desc>

  <text x="20" y="24" font-family="var(--mono)" font-size="13" letter-spacing="1.4" fill="var(--fg-fade)">SPREADSHEET</text>
  <text x="390" y="24" font-family="var(--mono)" font-size="13" letter-spacing="1.4" fill="var(--brand)">TRANSACTION LEDGER</text>

  <g>
    <rect x="20" y="44" width="300" height="52" rx="7" fill="var(--bg-alt)" stroke="var(--line-hi)"/>
    <text x="38" y="76" font-family="var(--mono)" font-size="19" fill="var(--fg-fade)" text-decoration="line-through">40</text>
    <text x="96" y="76" font-family="var(--body)" font-size="13.5" fill="var(--fg-fade)">overtyped &rarr;</text>
    <rect x="196" y="52" width="60" height="36" rx="5" fill="var(--bg)" stroke="var(--warn)" stroke-width="1.6"/>
    <text x="226" y="76" font-family="var(--mono)" font-size="19" fill="var(--fg)" text-anchor="middle">37</text>
  </g>
  <g font-family="var(--body)" font-size="13" fill="var(--fg-mut)">
    <text x="20" y="132">The 40 no longer exists.</text>
    <text x="20" y="154">No reason. No date. No name.</text>
    <text x="20" y="176">Nothing to reconcile a report against.</text>
  </g>
  <g transform="translate(20 200)">
    <rect x="0" y="0" width="300" height="62" rx="7" fill="var(--warn)" opacity=".1"/>
    <text x="16" y="26" font-family="var(--body)" font-size="13" font-weight="600" fill="var(--warn)">&#9888; Result: 37 is a claim</text>
    <text x="16" y="47" font-family="var(--body)" font-size="13.5" fill="var(--fg-mut)">You cannot check it, only believe it.</text>
  </g>

  <line x1="355" y1="40" x2="355" y2="268" stroke="var(--line)" stroke-width="1" stroke-dasharray="3 5"/>

  <g font-family="var(--mono)" font-size="13.5">
    <g transform="translate(390 44)">
      <rect x="0" y="0" width="310" height="34" rx="6" fill="var(--bg-alt)" stroke="var(--line)"/>
      <text x="14" y="22" fill="var(--brand)">+50</text>
      <text x="58" y="22" fill="var(--fg-mut)" font-family="var(--body)" font-size="13.5">receipt &middot; PO-1043 &middot; Asha &middot; 2 Sep</text>
    </g>
    <g transform="translate(390 86)">
      <rect x="0" y="0" width="310" height="34" rx="6" fill="var(--bg-alt)" stroke="var(--line)"/>
      <text x="14" y="22" fill="var(--fg)">&#8722;11</text>
      <text x="58" y="22" fill="var(--fg-mut)" font-family="var(--body)" font-size="13.5">sale &middot; SO-2210 &middot; Ravi &middot; 4 Sep</text>
    </g>
    <g transform="translate(390 128)">
      <rect x="0" y="0" width="310" height="34" rx="6" fill="var(--bg-alt)" stroke="var(--line)"/>
      <text x="14" y="22" fill="var(--warn)">&#8722;2</text>
      <text x="58" y="22" fill="var(--fg-mut)" font-family="var(--body)" font-size="13.5">damage &middot; crushed &middot; Asha &middot; 5 Sep</text>
    </g>
  </g>
  <line x1="390" y1="176" x2="700" y2="176" stroke="var(--line-hi)" stroke-width="1.5"/>
  <g transform="translate(390 186)">
    <text x="14" y="24" font-family="var(--mono)" font-size="19" fill="var(--brand)">37</text>
    <text x="58" y="24" font-family="var(--body)" font-size="13" fill="var(--fg-mut)">derived, not entered</text>
  </g>
  <g transform="translate(390 224)">
    <rect x="0" y="0" width="310" height="44" rx="7" fill="var(--brand)" opacity=".11"/>
    <text x="16" y="27" font-family="var(--body)" font-size="13" font-weight="600" fill="var(--brand)">&#10003; Every figure walks back to a movement</text>
  </g>
</svg></div>
<p class="fig__hint">Scroll the diagram sideways &rarr;</p>
<figcaption>${caption}</figcaption>
</figure>`;

/**
 * The shape ABC analysis exists to exploit: a small share of the catalogue
 * carries most of the value, so uniform treatment wastes effort at both ends.
 */
export const abcFigure = (caption) => `
<figure class="fig">
<div class="fig__scroll"><svg viewBox="0 0 720 240" role="img" aria-labelledby="abc-t abc-d">
  <title id="abc-t">Share of products against share of inventory value, by ABC class</title>
  <desc id="abc-d">Class A is about 12 per cent of products but 77 per cent of value. Class B is 24 per cent of products and 18 per cent of value. Class C is 64 per cent of products and only 5 per cent of value.</desc>

  <text x="20" y="34" font-family="var(--mono)" font-size="13" letter-spacing="1.4" fill="var(--fg-fade)">SHARE OF PRODUCTS</text>
  <g transform="translate(20 46)">
    <rect x="0"     y="0" width="79.2"  height="46" rx="5" fill="var(--brand)"/>
    <rect x="83.2"  y="0" width="158.4" height="46" rx="5" fill="var(--brand)" opacity=".55"/>
    <rect x="245.6" y="0" width="422.4" height="46" rx="5" fill="var(--fg-fade)" opacity=".28"/>
    <text x="39"  y="29" font-family="var(--display)" font-size="15" font-weight="700" fill="var(--on-brand)" text-anchor="middle">12%</text>
    <text x="162" y="29" font-family="var(--display)" font-size="15" font-weight="700" fill="var(--on-brand)" text-anchor="middle">24%</text>
    <text x="457" y="29" font-family="var(--display)" font-size="15" font-weight="700" fill="var(--fg)" text-anchor="middle">64%</text>
  </g>

  <text x="20" y="134" font-family="var(--mono)" font-size="13" letter-spacing="1.4" fill="var(--fg-fade)">SHARE OF VALUE</text>
  <g transform="translate(20 146)">
    <rect x="0"     y="0" width="508.2" height="46" rx="5" fill="var(--brand)"/>
    <rect x="512.2" y="0" width="118.8" height="46" rx="5" fill="var(--brand)" opacity=".55"/>
    <rect x="635"   y="0" width="33"    height="46" rx="5" fill="var(--fg-fade)" opacity=".28"/>
    <text x="254" y="29" font-family="var(--display)" font-size="15" font-weight="700" fill="var(--on-brand)" text-anchor="middle">77%</text>
    <text x="571" y="29" font-family="var(--display)" font-size="15" font-weight="700" fill="var(--on-brand)" text-anchor="middle">18%</text>
    <text x="651" y="29" font-family="var(--display)" font-size="13" font-weight="700" fill="var(--fg)" text-anchor="middle">5%</text>
  </g>

  <g font-family="var(--mono)" font-size="13" fill="var(--fg-mut)">
    <text x="20"  y="228">A &mdash; count monthly, calculate reorder points</text>
    <text x="420" y="228">C &mdash; count yearly, flat rules</text>
  </g>
</svg></div>
<p class="fig__hint">Scroll the diagram sideways &rarr;</p>
<figcaption>${caption}</figcaption>
</figure>`;
