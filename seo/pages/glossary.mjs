import { site } from '../site.mjs';
import { esc, ENTITIES } from '../layout.mjs';
import { section, wrap, cta, related } from '../blocks.mjs';

/**
 * Terms as they are actually used on a shop floor or in a warehouse, not
 * textbook paraphrases. `link` points at the page that explains the term
 * properly, so the glossary is a hub rather than a dead end.
 */
const TERMS = [
  ['ABC analysis', 'Ranking the catalogue by annual consumption value and treating the classes differently. Typically about a fifth of products carry three quarters of the value, so counting effort and reorder-point work go there first.', '/blog/abc-analysis-inventory'],
  ['Adjustment', 'A correction to a quantity, recorded as its own movement with a reason attached rather than by overtyping the number. It is what keeps a count explainable a year later.', null],
  ['Ageing', 'How long stock has been sitting, grouped into buckets. The report that turns a vague worry about dead stock into a list you can act on.', '/features/inventory-reports-and-analytics'],
  ['Allocation', 'Committing stock to a specific sales order. Allocated stock still exists physically but is no longer available to promise to anyone else — the distinction that stops two people selling the same last unit.', '/features/purchase-orders-and-sales-orders'],
  ['Backorder', 'A customer order accepted for stock you do not currently hold, to be filled when it arrives. Useful when lead times are reliable; a promise you will break when they are not.', null],
  ['Barcode', 'A machine-readable code on the product, usually the manufacturer’s EAN or UPC. Distinct from your SKU, which is yours and stays stable when a supplier changes packaging.', '/features/barcode-inventory-management'],
  ['Batch (lot)', 'A group of units produced or received together, tracked by a shared number. Essential wherever a recall or an expiry date has to reach exactly the affected units.', null],
  ['Bin / zone', 'A named storage location inside a warehouse. Without one, "we have twelve" is true and useless, because nobody can find them.', null],
  ['Carrying cost', 'The annual cost of holding one unit: capital tied up, storage, insurance, shrinkage and obsolescence. Commonly 20–30% of unit value per year, and consistently underestimated.', '/blog/what-is-inventory-management'],
  ['Credit note', 'A document that reduces what a customer owes, issued instead of deleting or editing a sent invoice. Deleting one destroys the audit trail and leaves a gap in the numbering nobody can later explain.', '/features/gst-billing-and-invoicing'],
  ['Cycle counting', 'Counting a slice of the catalogue continuously — a category a week, or twenty products a day — rather than shutting down once a year. Errors surface while their cause is still traceable.', '/blog/stock-audit-cycle-counting'],
  ['Days of inventory (DIO)', 'Days of stock on hand: days in the period divided by inventory turnover. The same fact as turnover, in a unit people can actually reason about.', '/tools/inventory-turnover-calculator'],
  ['Dead stock', 'Stock with no realistic prospect of selling. It is a loss you have already taken; carrying it only delays recognising it while consuming space and working capital.', null],
  ['Economic order quantity (EOQ)', 'The order quantity that balances the cost of ordering against the cost of holding, from √(2DS/H). At the EOQ those two annual costs are equal — a useful check on any answer.', '/tools/economic-order-quantity-calculator'],
  ['FIFO', 'First in, first out: the oldest cost is released when a unit sells. It matches how physical goods should move and is the sane default for anything with a shelf life.', null],
  ['Goods received note (GRN)', 'The record of what physically arrived against a purchase order — which is frequently not what was ordered. A system that cannot record a partial receipt forces you to misrepresent the delivery.', '/features/purchase-orders-and-sales-orders'],
  ['GSTIN', 'The taxpayer identification number printed on an Indian tax invoice. SmartShelfKart stores it and reports tax collected by rate; it does not file returns.', '/features/gst-billing-and-invoicing'],
  ['Hold', 'Stock reserved informally for a customer, with the reason and the person recorded. Releasing it returns it to availability rather than quietly changing a number.', null],
  ['HSN code', 'A tariff classification code for goods under GST. SmartShelfKart does not maintain an HSN master — worth knowing before a filing deadline rather than during one.', '/features/gst-billing-and-invoicing'],
  ['Landed cost', 'The true cost of a unit once freight, duty and handling are included. Margin calculated on the invoice price alone overstates itself, sometimes badly.', null],
  ['Lead time', 'Days from deciding to order to the stock being available to sell — including approval delays before the order goes out and put-away after it arrives. Not the supplier’s quote, which is consistently optimistic.', '/blog/reorder-point-formula'],
  ['Minimum order quantity (MOQ)', 'The smallest quantity a supplier will accept. It frequently overrides your EOQ, and when it is far above it, that is a negotiation rather than a constraint.', null],
  ['MRO', 'Maintenance, repair and operations supplies — things you consume but never sell. Rarely managed, and a common cause of expensive downtime.', null],
  ['Par level', 'A target quantity a location is topped back up to on a schedule. Simpler than a reorder point and appropriate where a supplier delivers on a fixed day.', null],
  ['Purchase order (PO)', 'Your instruction to a supplier: what, how much, at what price. It carries a status through its life rather than being an email that gets forgotten.', '/features/purchase-orders-and-sales-orders'],
  ['Reorder point (ROP)', 'The stock level at which the next order must be placed: lead time demand plus safety stock. The single most useful number to set correctly, per product.', '/tools/reorder-point-calculator'],
  ['Safety stock', 'The buffer that absorbs demand spiking and the supplier being late at the same time. Sized by how variable those actually are, not by how nervous you feel.', '/tools/safety-stock-calculator'],
  ['Service level', 'The share of replenishment cycles you intend to get through without stocking out. A business decision rather than a measurement; 95% is a common default.', '/blog/safety-stock-formula'],
  ['Shrinkage', 'Stock that disappears — theft, damage, miscounts. Invisible unless you count and record reasons, and most of it turns out to be process rather than theft.', '/blog/stock-audit-cycle-counting'],
  ['SKU', 'Stock keeping unit: your own identifier for one distinct sellable item. Two sizes of the same product are two SKUs, and getting this granularity right decides whether any of your data is usable.', null],
  ['Stock ledger', 'Every movement for one product, in order, with reason, source document and author. The appeal court for any disputed quantity — most arguments end within a minute of opening it.', '/features/inventory-reports-and-analytics'],
  ['Stock take', 'A structured physical count producing a variance against the system position. Count blind: showing the expected figure anchors the counter and the number stops being evidence.', '/blog/stock-audit-cycle-counting'],
  ['Stockout', 'Having none of something a customer wants. The cost is the lost sale plus, sometimes, the lost customer — and neither appears anywhere in your inventory reports.', '/features/low-stock-alerts-and-reorder-points'],
  ['Turnover', 'How many times a year stock sells through: cost of goods sold divided by average inventory. Use cost, never revenue — revenue inflates it by your entire gross margin.', '/blog/inventory-turnover-ratio'],
  ['Weighted average cost', 'Valuing each unit at the running average of what you paid. Simpler than FIFO and appropriate where units are genuinely interchangeable.', null],
  ['Work in progress (WIP)', 'Partly finished goods. Consumes capital, is easy to lose track of entirely, and is the category most often missing from a small manufacturer’s numbers.', null],
];

const slug = (t) =>
  t.toLowerCase().replace(/[()’/]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

const letters = [...new Set(TERMS.map((t) => t[0][0].toUpperCase()))].sort();

const index = `<nav class="glossnav" aria-label="Jump to letter">${letters
  .map((l) => `<a href="#letter-${l}">${l}</a>`)
  .join('')}</nav>`;

let currentLetter = '';
const list = TERMS.map(([term, def, link]) => {
  const L = term[0].toUpperCase();
  const head = L !== currentLetter ? ((currentLetter = L), `<h2 class="glossletter" id="letter-${L}">${L}</h2>`) : '';
  return (
    head +
    `<div class="gloss" id="${slug(term)}">
      <h3><a href="#${slug(term)}" class="gloss__anchor" aria-label="Link to ${esc(term)}">${esc(term)}</a></h3>
      <p>${def}</p>
      ${link ? `<p class="gloss__more"><a href="${link}">Read more &rarr;</a></p>` : ''}
    </div>`
  );
}).join('');

export default [
  {
    path: '/glossary',
    file: 'glossary.html',
    title: 'Inventory Management Glossary — 36 Terms, Defined',
    ogTitle: 'Inventory management glossary',
    description:
      'Thirty-six inventory management terms defined as they are actually used: SKU, reorder point, safety stock, lead time, shrinkage, GRN, ABC analysis, turnover and more.',
    trail: [
      { href: '/', label: 'Home' },
      { href: '/glossary', label: 'Glossary' },
    ],
    priority: '0.7',
    changefreq: 'monthly',
    image: '/static/og/glossary.jpg',
    about: [ENTITIES.inventoryManagement, ENTITIES.sku],
    schema: [
      {
        '@type': 'DefinedTermSet',
        '@id': site.origin + '/glossary#termset',
        name: 'Inventory management glossary',
        description: 'Terms used in inventory, stock control, purchasing and warehouse operations.',
        url: site.origin + '/glossary',
        inLanguage: 'en',
        hasDefinedTerm: TERMS.map(([term, def]) => ({
          '@type': 'DefinedTerm',
          '@id': `${site.origin}/glossary#${slug(term)}`,
          name: term,
          description: def.replace(/<[^>]+>/g, ''),
          inDefinedTermSet: { '@id': site.origin + '/glossary#termset' },
        })),
      },
    ],
    body: `
<section class="hero">${wrap(`
  <p class="eyebrow">Reference</p>
  <h1 style="max-width:19ch">Inventory management glossary</h1>
  <p class="hero__lead">Thirty-six terms, defined the way they are used on a shop floor rather than the way a textbook phrases them &mdash; and each one linked to the page that explains it properly.</p>
`)}</section>

<section class="sec sec--tight">${wrap(`${index}<div class="glosslist">${list}</div>
${related('Where to go next', [
      { href: '/blog/what-is-inventory-management', label: 'Guide: what is inventory management?' },
      { href: '/tools', label: 'Free inventory calculators' },
      { href: '/features', label: 'Everything SmartShelfKart does' },
      { href: '/blog', label: 'All guides' },
    ])}`)}</section>

${cta({
      title: 'The terms above, as working screens',
      body: 'Reorder points on every product, batch and expiry tracking, stock takes with variance, and a ledger where every quantity traces back to a movement. Free on every tier during launch.',
    })}`,
  },
];
