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
