import { site, featureGroups } from '../site.mjs';
import { faqLd, esc } from '../layout.mjs';
import { section, wrap, cards, faqBlock, cta, related, table, featureList, sawtoothFigure, ledgerFigure, icon } from '../blocks.mjs';

const T = (label) => [
  { href: '/', label: 'Home' },
  { href: '/features', label: 'Features' },
  ...(label ? [{ href: '#', label }] : []),
];

/** A feature page: hero, prose sections, FAQ, related, CTA. */
function featurePage({ slug, title, h1, description, lead, sections, faqs, links }) {
  const path = '/features/' + slug;
  const trail = [
    { href: '/', label: 'Home' },
    { href: '/features', label: 'Features' },
    { href: path, label: h1.length > 40 ? h1.slice(0, 38) + '…' : h1 },
  ];
  const body = `
<section class="hero">${wrap(`
  <p class="eyebrow">Feature</p>
  <h1 style="max-width:22ch">${h1}</h1>
  <p class="hero__lead">${lead}</p>
  <div class="btnrow" style="margin-top:24px">
    <a class="btn" href="${site.appUrl}" data-app-link>Open the web app</a>
    <a class="btn btn--ghost" href="/features">All features</a>
  </div>
`)}</section>
<section class="sec">${wrap(`<div class="prose">${sections}</div>${related('Related', links)}`, 'wrap--narrow')}</section>
${section({ alt: true, title: 'Questions', body: faqBlock(faqs) })}
${cta()}`;

  return {
    path,
    file: 'features/' + slug + '.html',
    title,
    description,
    trail,
    priority: '0.8',
    changefreq: 'monthly',
    schema: [faqLd(faqs)],
    body,
  };
}

/* ------------------------------------------------------------------ */
/* /features/ — the index                                              */
/* ------------------------------------------------------------------ */

const indexPage = {
  path: '/features',
  file: 'features.html',
  title: 'Features — Every Screen in SmartShelfKart Inventory Software',
  description:
    'The complete SmartShelfKart feature list: stock movements, barcode scanning, purchase and sales orders, billing, batch and expiry tracking, reports, roles and Excel import.',
  trail: [
    { href: '/', label: 'Home' },
    { href: '/features', label: 'Features' },
  ],
  priority: '0.9',
  changefreq: 'monthly',
  body: `
<section class="hero">${wrap(`
  <p class="eyebrow">Features</p>
  <h1 style="max-width:20ch">Everything SmartShelfKart does, in one list</h1>
  <p class="hero__lead">Forty-three features across six areas of the business — grouped the way the app groups them, so what you read here is what you find when you open it. Nothing on this page is a roadmap item.</p>
`)}</section>

${section({
  tight: true,
  body: cards([
    { icon: 'barcode', title: 'Barcode inventory management', body: 'Camera scanning on mobile, keyboard-wedge scanners on the web, SKU and barcode on every product.', href: '/features/barcode-inventory-management', more: 'How it works' },
    { icon: 'alert', title: 'Low-stock alerts &amp; reorder points', body: 'A threshold per product, a live low-stock list, and reorder quantities derived from real movement.', href: '/features/low-stock-alerts-and-reorder-points', more: 'How it works' },
    { icon: 'orders', title: 'Purchase &amp; sales orders', body: 'Both sides of the order book, with part-receipts, allocation, despatch and returns.', href: '/features/purchase-orders-and-sales-orders', more: 'How it works' },
    { icon: 'invoice', title: 'Billing &amp; GST invoicing', body: 'Invoices from the same catalogue as your stock, with per-line tax, payments and credit notes.', href: '/features/gst-billing-and-invoicing', more: 'How it works' },
    { icon: 'chart', title: 'Reports &amp; analytics', body: 'P&amp;L, ABC analysis, valuation, ageing and the stock ledger — all derived from transactions.', href: '/features/inventory-reports-and-analytics', more: 'How it works' },
    { icon: 'spark', title: 'Nova AI assistant', body: 'Ask your inventory a question in English or Hinglish and get an answer that matches the reports.', href: '/features/ai-inventory-assistant', more: 'How it works' },
  ]),
})}

${featureGroups
  .map((g, i) =>
    section({
      alt: i % 2 === 1,
      title: esc(g.title),
      lead: esc(g.blurb),
      body: featureList(g.items),
    })
  )
  .join('\n')}

${cta()}`,
};

/* ------------------------------------------------------------------ */
/* individual feature pages                                            */
/* ------------------------------------------------------------------ */

const barcode = featurePage({
  slug: 'barcode-inventory-management',
  title: 'Barcode Inventory Management — Scan Stock In and Out',
  h1: 'Barcode inventory management that works on a phone and at a desk',
  description:
    'Scan stock in and out with a phone camera or a USB barcode scanner. Every product carries a SKU and a barcode, and every scan writes a proper transaction to the ledger.',
  lead: 'A barcode is only useful if scanning it does something. In SmartShelfKart a scan resolves to a product and drops you straight into the movement you were about to record — receive it, issue it, count it, or open its history.',
  sections: `
<h2 id="two-ways">Two ways to scan, depending on where you are standing</h2>
<p>Barcode hardware in a small business is rarely uniform. Somebody has a phone in their pocket on the floor, and somebody else has a ₹1,200 USB scanner wired to a desktop in the office. Both work, and they write the same record.</p>
<ul>
<li><b>On Android and iOS</b>, the camera is the scanner. Open the barcode screen, point it at the label, and the product resolves. No extra hardware, no pairing, nothing to charge.</li>
<li><b>On the web</b>, a USB or Bluetooth barcode scanner behaves as a keyboard: it types the code and presses Enter. Focus the field, scan, and the product is found. This is why cheap scanners work — there is no driver to install and no integration to configure.</li>
</ul>
<p>The same screen accepts a typed code, which matters more than it sounds. Labels get scuffed, and a system that only accepts a clean scan stops the person using it.</p>

<h2 id="sku-vs-barcode">SKU and barcode are different fields, on purpose</h2>
<p>Every product carries both. They are not the same thing and conflating them causes real problems later:</p>
<ul>
<li>The <b>SKU</b> is yours. You choose the format, it means something to your team, and it stays stable even when a supplier changes packaging.</li>
<li>The <b>barcode</b> is usually the manufacturer's — an EAN or UPC printed on the box. You do not control it, and two of your SKUs can legitimately share one if you repack.</li>
</ul>
<p>Keeping them separate means Excel import can match on either. When a supplier sends a price list keyed by their barcode, you can bulk-update against that. When your own team sends a count keyed by your SKU, you can bulk-update against that instead.</p>

<h2 id="where-scanning-lands">Where a scan actually lands</h2>
<p>Scanning is not a feature in isolation — it is an entry point into the movement screens:</p>
${table(
  ['Scan from', 'What happens'],
  [
    ['Stock In', 'The product is added to the receipt line, quantity focused, ready for the next scan.'],
    ['Stock Out', 'The product is issued, with the available quantity and any active hold shown before you commit.'],
    ['Fast POS', 'The line is added to the sale at the counter price and the running total updates.'],
    ['Stock Take', 'The counted quantity is captured against the product, and variance against the system is calculated at the end.'],
    ['Global search', 'You land on the product detail with its ledger, price history and current position.'],
  ]
)}

<h2 id="counting">Counting a shelf with a phone</h2>
<p>The stock take flow is the one that most repays a scanner. You create a count — the whole catalogue, a category, or a zone — and then walk the shelf scanning and entering what you actually see. The system holds its own figure back until you finish, so nobody anchors on the expected number, and at the end you get a variance list: what was over, what was short, and by how much.</p>
<p>You then post the count, which writes adjustment transactions with the stock take as the reason. That is the important part. The quantity does not simply change; there is a record saying it changed because of a count on a particular date, approved by a particular person.</p>

<h2 id="labels">If your products have no barcodes</h2>
<p>Plenty of businesses sell loose, repacked, or own-brand goods with nothing printed on them. Two things work:</p>
<ul>
<li>Use your SKU as the barcode value and print your own labels — any thermal label printer will encode a Code 128 from plain text.</li>
<li>Or skip barcodes entirely. Every screen that accepts a scan also accepts a search by name, SKU or category. Barcodes make it faster; they are not a prerequisite.</li>
</ul>

<h2 id="ledger">Every scan is a transaction, not an edit</h2>
<p>This is the part that separates a stock system from a spreadsheet with a scanner attached. A scan never overwrites a number. It appends a typed movement — a receipt, an issue, a transfer, an adjustment — carrying a quantity, a timestamp, a reason and the person who did it. The current quantity is the sum of those movements.</p>
<p>Because of that, the <a href="/features/inventory-reports-and-analytics">reports</a> can be trusted, the <a href="/blog/stock-audit-cycle-counting">audit trail</a> is complete by construction, and a disputed number can always be walked backwards until you find the movement that caused it.</p>`,
  faqs: [
    { q: 'Do I need a special barcode scanner?', a: 'No. On a phone the camera works. On a desktop, any USB or Bluetooth scanner that behaves as a keyboard works — which is nearly all of them, including the cheapest models. There is no driver and no pairing step inside the app.' },
    { q: 'Which barcode formats are supported?', a: 'The camera scanner reads the common one-dimensional retail formats such as EAN-13, EAN-8, UPC-A and Code 128, as well as QR codes. A keyboard-wedge scanner is format-agnostic: whatever it decodes, it types.' },
    { q: 'Can two products share a barcode?', a: 'They can, and sometimes they legitimately do — a repack, or two sizes sharing a case code. When a scan is ambiguous the app shows the matches and asks which one you mean rather than guessing.' },
    { q: 'Can I scan without an internet connection?', a: 'Scanning and lookup work against the locally cached catalogue, and writes are queued and synced when the connection returns. Long stretches fully offline are not the design target.' },
    { q: 'Can I print barcode labels from SmartShelfKart?', a: 'There is no built-in label designer. Export the catalogue to Excel with the SKU or barcode column and feed that to your label printer software, which is where the label layout belongs anyway.' },
  ],
  links: [
    { href: '/features/low-stock-alerts-and-reorder-points', label: 'Low-stock alerts and reorder points' },
    { href: '/blog/barcode-inventory-system-guide', label: 'Guide: setting up a barcode inventory system' },
    { href: '/blog/stock-audit-cycle-counting', label: 'Guide: stock audits and cycle counting' },
    { href: '/features', label: 'All features' },
  ],
});

const lowStock = featurePage({
  slug: 'low-stock-alerts-and-reorder-points',
  title: 'Low Stock Alerts & Reorder Points — SmartShelfKart',
  h1: 'Low-stock alerts with a threshold per product, not one number for everything',
  description:
    'Set a low-stock threshold on each product, see everything under it live, and get reorder quantities calculated from real movement history — plus expiry alerts.',
  lead: 'A single global "alert me under 10" is worse than no alert at all: it screams about slow-moving spares and stays silent about the line you sell forty of a day. SmartShelfKart puts the threshold on the product, where it belongs.',
  sections: `
<h2 id="threshold">The threshold lives on the product</h2>
<p>Each product carries its own low-stock threshold. That single design decision is what makes the alert list usable, because the right trigger level is a property of the product's demand and lead time, not of your business as a whole.</p>
<p>A fast line with a two-day lead time might need a threshold of 60. A slow spare with a six-week lead time might need a threshold of 2. Both are correct, and no global number can express both.</p>
<div class="callout"><p><b>Not sure what to set it to?</b> The threshold you want is the reorder point. Work it out with the <a href="/tools/reorder-point-calculator">free reorder point calculator</a>, or read <a href="/blog/reorder-point-formula">how the formula is derived</a>.</p></div>

${sawtoothFigure('What a correctly set threshold does: the order goes out the moment stock crosses the reorder point, and the delivery arrives before the safety-stock floor is breached.')}

<h2 id="the-list">A live list, not an email you will ignore</h2>
<p>The Low Stock screen is a live view of everything currently under its own threshold, ordered so the most urgent sits at the top. It is a working screen, not a notification: you open it as part of the ordering routine, filter it by category or vendor, and act on it.</p>
<p>Out-of-stock lines are called out separately from merely low ones, because they are a different problem with a different urgency. A line at zero is losing sales right now; a line under threshold is a purchasing task for today.</p>

<h2 id="reorder">Reorder suggests a quantity, not just a flag</h2>
<p>Knowing you are low is half the job. The Reorder screen goes further and proposes how much to order, reading the product's actual movement history rather than a fixed rule. That means the suggestion reflects what has really been selling in recent weeks — including the fact that it slowed down, which is exactly the case where a fixed reorder quantity buys you dead stock.</p>
<p>You are never locked into the suggestion. It is a starting number in an editable field, and the purchase order it feeds into is <a href="/features/purchase-orders-and-sales-orders">an ordinary PO</a> you can adjust before sending.</p>

<h2 id="forecast">Forecast: when does this run out?</h2>
<p>The Stock Forecast screen answers the question a threshold cannot: not "am I low", but "how many days do I have". It projects a run-out date per product from the current position and recent consumption rate. That is the number that tells you whether a six-week lead time is already too late.</p>

<h2 id="expiry">Dated stock has a second clock</h2>
<p>If you handle pharmacy, food, cosmetics or anything else with a shelf life, quantity is only half the risk. Batch tracking carries a lot number and expiry date through every movement, and Expiry Alerts warn you before dated stock crosses the line into a write-off — early enough to discount it, return it to the supplier, or move it to a location that will sell it.</p>
${table(
  ['Signal', 'Answers', 'Where'],
  [
    ['Low Stock', 'What is under its threshold right now?', 'Low Stock screen'],
    ['Reorder', 'How much should I actually order?', 'Reorder screen'],
    ['Stock Forecast', 'How many days until this runs out?', 'Stock Forecast screen'],
    ['Expiry Alerts', 'What is about to become unsellable?', 'Expiry Alerts screen'],
    ['Ageing', 'What has been sitting too long to be worth holding?', 'Ageing report'],
  ]
)}

<h2 id="tuning">Setting thresholds without doing it 2,000 times</h2>
<p>Nobody is going to hand-set a threshold on a catalogue of two thousand products, and a system that requires it will simply be left at its defaults. Two things make it tractable:</p>
<ul>
<li><b>Bulk edit</b> — select a filtered set of products and change the threshold on all of them at once.</li>
<li><b>Update from Excel</b> — export the catalogue, calculate thresholds in a column of formulas, and re-import matching on SKU. For a first pass this is by far the fastest route: work out reorder points for your A-class items properly and give everything else a sensible default.</li>
</ul>
<p><a href="/blog/abc-analysis-inventory">ABC analysis</a> is the natural companion here — spend the effort on the fifth of the catalogue that carries most of the value, and default the rest.</p>`,
  faqs: [
    { q: 'Can each product have a different low-stock level?', a: 'Yes, and that is the intended way to use it. The threshold is a field on the product. A global default exists only as a starting point for newly created products.' },
    { q: 'Do I get a notification, or do I have to check?', a: 'Both. In-app notifications surface low-stock and expiry events, and the Low Stock screen is a live list you can open at any time. The list is the reliable one — notifications are a prompt, not the system of record.' },
    { q: 'How does the reorder suggestion decide a quantity?', a: 'It reads the product\'s recorded movement history and current position rather than applying a fixed multiple. Because it is derived from your own transactions, it changes as demand changes. It is a suggestion in an editable field, not an automatic order.' },
    { q: 'Does it order from suppliers automatically?', a: 'No. Nothing is sent to a vendor without you creating and sending a purchase order. Automatic ordering on a forecast is how businesses end up with warehouses full of a discontinued line.' },
    { q: 'Can I set thresholds in bulk?', a: 'Yes — either by selecting products and bulk-editing, or by exporting to Excel, calculating thresholds there and re-importing with Update from Excel, which matches on SKU or barcode.' },
  ],
  links: [
    { href: '/tools/reorder-point-calculator', label: 'Free reorder point calculator' },
    { href: '/tools/safety-stock-calculator', label: 'Free safety stock calculator' },
    { href: '/blog/reorder-point-formula', label: 'Guide: the reorder point formula' },
    { href: '/features/purchase-orders-and-sales-orders', label: 'Purchase and sales orders' },
  ],
});

const orders = featurePage({
  slug: 'purchase-orders-and-sales-orders',
  title: 'Purchase Orders & Sales Orders — Inventory Order Management',
  h1: 'Purchase orders and sales orders against the same stock',
  description:
    'Raise purchase orders, receive them in parts, allocate sales orders against available stock, despatch, invoice and handle returns — all writing to one inventory ledger.',
  lead: 'An order system that does not touch stock is just a document folder. In SmartShelfKart a receipt against a purchase order raises the quantity, an allocation against a sales order reserves it, and a despatch releases it — so the position on screen is the position on the shelf.',
  sections: `
<h2 id="po">Purchase orders: draft, send, receive, part-receive</h2>
<p>A purchase order starts as a draft against a vendor. You add lines from the catalogue with quantities and agreed costs, and the order carries a status through its life rather than being a document that gets emailed and forgotten.</p>
<p>The part that matters is receiving. Suppliers routinely ship 80 of the 100 you ordered, and a system that only understands "received" or "not received" forces you to lie to it. Here a receipt is per line and per quantity: you record what physically arrived, stock rises by exactly that, and the order stays open for the balance. A second delivery closes it.</p>
<ul>
<li>Costs on the receipt feed <b>price history</b>, so you can see what you actually paid for a line over time rather than what the price list said.</li>
<li>An open PO is visible against the product, so you do not double-order something already on its way.</li>
<li>Reorder suggestions can be turned straight into a PO instead of being retyped.</li>
</ul>

<h2 id="so">Sales orders: allocate, despatch, bill</h2>
<p>A sales order goes the other way. You take the order against a customer, allocate against available stock, and despatch — with the invoice created from the order rather than typed again.</p>
<p>Allocation is where the value is. Stock allocated to an order is committed: it still exists physically, but it is no longer available to promise to somebody else. Without that distinction two salespeople sell the same last unit, which is the single most common way a small business breaks a promise to a customer.</p>
<p>The <b>Hold / Release</b> pair covers the informal version of the same problem — a customer who has asked you to keep something back. Held stock is visible as held, with the reason and the person attached, and releasing it puts it back into availability rather than quietly changing a number.</p>

<h2 id="returns">Returns that unwind correctly</h2>
<p>Returns are where hand-rolled systems fall apart, because a return is not the negative of a sale. Goods coming back may be resaleable, damaged, or destined back to the supplier, and each of those is a different outcome for the quantity.</p>
${table(
  ['Return type', 'What happens to stock', 'What happens to money'],
  [
    ['Customer return, resaleable', 'Quantity goes back into available stock', 'Credit note against the customer'],
    ['Customer return, damaged', 'Recorded as damage, not as sellable stock', 'Credit note against the customer'],
    ['Return to vendor', 'Quantity leaves stock against the vendor', 'Recorded against the purchase'],
  ]
)}
<p>Keeping damage separate from ordinary shrinkage is deliberate. If write-offs and miscounts land in the same bucket, the one number you most need — how much stock you are actually losing, and to what — becomes unreadable.</p>

<h2 id="parties">Vendors and customers carry their own history</h2>
<p>Both sides of the order book are attached to a record that accumulates. A vendor shows what you have bought, at what prices, and how reliably orders were filled. A customer shows their orders, their invoices, what they have paid and what is outstanding — and a <b>customer statement</b> you can send when a conversation about money is needed.</p>

<h2 id="flow">The whole loop</h2>
<div class="formula">Reorder suggestion &rarr; Purchase order &rarr; Receipt (full or partial) &rarr; Stock rises
Sales order &rarr; Allocation &rarr; Despatch &rarr; Invoice &rarr; Payment
Return &rarr; Restock or damage &rarr; Credit note</div>
<p>Every arrow in that diagram writes a transaction. At the end of it, <a href="/features/inventory-reports-and-analytics">Profit &amp; Loss</a> can compute margin because it has both the cost you paid and the price you charged, from the same records, for the same units.</p>`,
  faqs: [
    { q: 'Can I receive a purchase order in parts?', a: 'Yes. Receipts are per line and per quantity. A partial receipt raises stock by what arrived and leaves the order open for the balance, so a split delivery does not require you to misrepresent what happened.' },
    { q: 'Does a sales order reserve stock?', a: 'Allocating against a sales order commits that quantity, so it is no longer available to promise elsewhere. Held stock works the same way for informal reservations, with the reason and person recorded.' },
    { q: 'Do invoices come from the sales order?', a: 'Yes. An invoice can be created from a sales order so lines, quantities and prices are not retyped. You can also raise a standalone invoice when there was no order.' },
    { q: 'Can I convert a low-stock alert into a purchase order?', a: 'Yes. The Reorder screen proposes quantities and those flow into a purchase order you can edit before sending.' },
    { q: 'How are returns to a supplier handled?', a: 'As an outward return against the vendor. Quantity leaves stock and the movement is recorded against the purchase, so the vendor record and the stock ledger both stay honest.' },
  ],
  links: [
    { href: '/features/gst-billing-and-invoicing', label: 'Billing and GST invoicing' },
    { href: '/features/low-stock-alerts-and-reorder-points', label: 'Low-stock alerts and reorder points' },
    { href: '/features/inventory-reports-and-analytics', label: 'Reports and analytics' },
    { href: '/blog/what-is-inventory-management', label: 'Guide: what is inventory management?' },
  ],
});

const billing = featurePage({
  slug: 'gst-billing-and-invoicing',
  title: 'Billing & GST Invoicing From Your Inventory — SmartShelfKart',
  h1: 'Invoicing built on the same catalogue as your stock',
  description:
    'Create invoices from sales orders or POS sales, with per-line tax rates, your GSTIN on the document, payments, part-payments, credit notes and customer statements.',
  lead: 'When billing and stock are separate systems, somebody spends every month reconciling them. Here an invoice line is a catalogue line, so what you billed and what left the shelf cannot drift apart.',
  sections: `
<h2 id="where-from">Three ways an invoice starts</h2>
<ul>
<li><b>From a sales order</b> — lines, quantities and prices carry over, so nothing is retyped and nothing is transcribed wrong.</li>
<li><b>From a Fast POS sale</b> — a counter sale produces its bill immediately.</li>
<li><b>Standalone</b> — for the case where there was no order, which happens more often than order-first software likes to admit.</li>
</ul>

<h2 id="tax">Tax, honestly described</h2>
<p>SmartShelfKart supports a <b>tax rate per invoice line</b>, a configurable tax label that defaults to <code>GST</code>, your <b>GSTIN</b> stored in billing settings and printed on the document, and a billing report that breaks collected tax down <b>by rate</b>. For most small businesses selling at a handful of standard rates, that covers day-to-day invoicing.</p>
<div class="callout callout--warn"><p><b>What it is not.</b> This is not a GST return-filing tool. It does not split a line into CGST/SGST/IGST components, maintain an HSN/SAC master, or generate GSTR filings or e-invoices. If you need those, keep filing where you file today and use the by-rate tax report as the input to it. We would rather say this plainly than have you discover it in the last week of a quarter.</p></div>

<h2 id="money">Payments, part-payments and what is actually owed</h2>
<p>An invoice is not settled by being sent. Payments are recorded against it — including part-payments, which are the normal case in wholesale — and the balance is what remains. From that, three things follow without any extra bookkeeping:</p>
<ul>
<li><b>Outstanding and overdue</b> figures that mean something, because they are computed from real receipts.</li>
<li><b>Customer statements</b>: a running account per customer you can send when the conversation about money needs a document behind it.</li>
<li><b>Ageing</b>: how long money has been owed, in buckets, so you chase the right invoices first.</li>
</ul>

<h2 id="credit">Credit notes</h2>
<p>When something is returned or wrongly billed, the fix is a credit note, not a deleted invoice. Deleting a sent invoice destroys the audit trail and leaves a hole in the numbering that nobody can explain later. A credit note reduces what is owed while leaving both documents intact and reconcilable.</p>

<h2 id="reports">Billing reports</h2>
${table(
  ['Report', 'Answers'],
  [
    ['Collected', 'What actually came in, over a period'],
    ['Outstanding', 'What is billed and unpaid right now'],
    ['Overdue', 'What is past its due date, and by how long'],
    ['Tax by rate', 'How much tax was charged at each rate'],
    ['Customer statement', 'One customer\'s complete running account'],
  ]
)}

<h2 id="stock">The link back to stock</h2>
<p>Because invoice lines come from the catalogue, billing and inventory reconcile by construction. <a href="/features/inventory-reports-and-analytics">Profit &amp; Loss</a> can compute margin per product because it holds the cost from the <a href="/features/purchase-orders-and-sales-orders">purchase side</a> and the price from the billing side against the same units. No export, no matching step, no month-end reconciliation.</p>`,
  faqs: [
    { q: 'Does SmartShelfKart file GST returns?', a: 'No. It records per-line tax rates, stores your GSTIN on the invoice, and reports tax collected by rate. Filing itself — GSTR forms, e-invoicing, HSN masters — is out of scope, and the by-rate report is intended as an input to whatever you file with.' },
    { q: 'Can I set a different tax rate per line?', a: 'Yes. The rate is a field on the invoice line, with a workspace default you can set once in billing settings so most invoices need no adjustment.' },
    { q: 'Can I record a part-payment?', a: 'Yes. Payments are recorded against an invoice and the balance is what remains, so an invoice paid in three instalments is represented correctly rather than being flipped from unpaid to paid.' },
    { q: 'How do I correct an invoice I have already sent?', a: 'Issue a credit note. The original stays intact, the credit reduces what is owed, and both documents remain in the record — which is what an auditor, and your own future self, needs to see.' },
    { q: 'Can I put my logo and business details on the invoice?', a: 'Yes. Billing settings hold your business name, address, tax ID/GSTIN, tax label and default rate, and those appear on the documents you generate.' },
  ],
  links: [
    { href: '/features/purchase-orders-and-sales-orders', label: 'Purchase and sales orders' },
    { href: '/features/inventory-reports-and-analytics', label: 'Reports and analytics' },
    { href: '/pricing', label: 'Pricing and plan limits' },
    { href: '/features', label: 'All features' },
  ],
});

const reports = featurePage({
  slug: 'inventory-reports-and-analytics',
  title: 'Inventory Reports & Analytics — P&L, ABC, Valuation, Ageing',
  h1: 'Inventory reports where every number traces back to a transaction',
  description:
    'Profit and loss by product, ABC analysis, valuation, ageing buckets, the stock ledger and a full audit log — all derived from movements, never typed in.',
  lead: 'A report is only worth reading if you can open the number and see what produced it. Every figure in SmartShelfKart is computed from the transaction record, so any total can be walked backwards to the individual movements behind it.',
  sections: `
<h2 id="derived">Derived, not entered</h2>
${ledgerFigure('The difference a ledger makes. A spreadsheet stores the answer; a ledger stores the workings and derives the answer, so any figure in any report can be walked back to the movements that produced it.')}
<p>There is no screen anywhere in SmartShelfKart where you type a closing stock figure, a valuation, or a margin. Those are all computed. That constraint is what makes the reports trustworthy — the failure mode of spreadsheet-based reporting is a number that was correct when someone pasted it in and has been quietly wrong ever since.</p>

<h2 id="which">What each report is for</h2>
${table(
  ['Report', 'The question it answers', 'When you read it'],
  [
    ['Dashboard', 'What needs my attention today?', 'Every morning'],
    ['Profit &amp; Loss', 'Where is the margin, by product and category?', 'Monthly, and before pricing decisions'],
    ['ABC analysis', 'Which items carry most of the value?', 'Quarterly, to set counting and ordering effort'],
    ['Inventory valuation', 'What is the stock worth, and how did it change?', 'Month end, and for the accountant'],
    ['Ageing', 'What has been sitting too long?', 'Monthly, before it becomes dead stock'],
    ['Stock ledger', 'Everything that happened to this one product', 'When a number is disputed'],
    ['Price history', 'What did we pay and charge over time?', 'Before negotiating with a supplier'],
    ['Damage report', 'What are we losing, and where?', 'Monthly'],
    ['Full history', 'The complete movement record, filtered', 'Whenever you need the raw truth'],
    ['Audit log', 'Who changed what, when?', 'When something does not add up'],
  ]
)}

<h2 id="pl">Profit and loss that knows both sides</h2>
<p>Margin needs a cost and a price for the same units. Because purchases and sales both write to the same ledger, the P&amp;L report has both without any matching step. You get margin by product, by category and by period — which is the report that tells you the line you sell most of is the one you make least on.</p>

<h2 id="abc">ABC analysis</h2>
<p>ABC sorts the catalogue by the value it actually carries. Typically a fifth of the lines account for most of the money, and treating all products identically wastes effort at the top and bottom simultaneously. Once you know your A-class items you can count them more often, set their reorder points properly, and default the long tail. <a href="/blog/abc-analysis-inventory">The full method is here.</a></p>

<h2 id="valuation">Valuation and ageing</h2>
<p>Valuation answers what the shelf is worth and how that has moved. Ageing answers something more uncomfortable: how long it has been there. Stock that has not moved in 180 days is not an asset in any practical sense, and the ageing buckets are what turn that from a vague worry into a list you can act on — discount it, return it, or write it off deliberately rather than discovering it at year end.</p>

<h2 id="ledger">The stock ledger is the appeal court</h2>
<p>When somebody insists the number is wrong, the stock ledger settles it. It is every in and out for a single product, in order, with the reason, the document it came from and the person who recorded it. Almost every "the system is wrong" argument ends within a minute of opening it — usually with a receipt that was never recorded, or a sale recorded twice.</p>

<h2 id="export">Getting the numbers out</h2>
<p>Export to Excel is available for the catalogue and for report data, because there will always be an analysis you want to do somewhere else, and software that traps your data is software you will resent. <a href="/features/ai-inventory-assistant">Nova</a> can also answer report-shaped questions conversationally, and its figures are computed from the same transactions — so it agrees with the Reports screen rather than offering a second opinion.</p>`,
  faqs: [
    { q: 'Can I export reports to Excel?', a: 'Yes. Catalogue and report data export to .xlsx, so you can take any analysis further in a spreadsheet without re-keying.' },
    { q: 'How is inventory valued?', a: 'From recorded purchase costs on receipts and the movements that followed, so valuation reflects what you actually paid rather than a list price typed in once.' },
    { q: 'Can I see the history of a single product?', a: 'Yes — the stock ledger shows every movement for one product in order, with reason, source document and the person who recorded it.' },
    { q: 'Do reports cover multiple locations?', a: 'Yes. Transfers move quantity between locations and remain visible as movements, so per-location positions and the consolidated position are both derivable.' },
    { q: 'Is there an audit trail of edits, not just movements?', a: 'Yes. The audit log records changes with the user and timestamp attached, separately from the stock ledger, and the activity timeline presents the same information in readable form.' },
  ],
  links: [
    { href: '/blog/abc-analysis-inventory', label: 'Guide: ABC analysis' },
    { href: '/blog/inventory-turnover-ratio', label: 'Guide: inventory turnover ratio' },
    { href: '/tools/inventory-turnover-calculator', label: 'Free inventory turnover calculator' },
    { href: '/features/ai-inventory-assistant', label: 'Nova AI assistant' },
  ],
});

const ai = featurePage({
  slug: 'ai-inventory-assistant',
  title: 'Nova — AI Inventory Assistant You Can Ask in Plain Language',
  h1: 'An AI assistant that reads your actual inventory',
  description:
    'Nova answers questions about your live stock in English or Hinglish and prepares stock actions for you to confirm, computed from the same transactions as the reports.',
  lead: 'Most "AI in inventory software" is a chat box that has never seen your data. Nova is wired to the transaction record — the same one the reports read — so when it tells you a number, that number is the report\'s number.',
  sections: `
<h2 id="two-jobs">Two kinds of request, routed differently</h2>
<p>Nova classifies what you asked before it does anything, because analytics and actions deserve different treatment:</p>
<ul>
<li><b>Analytics</b> — "what did we lose money on last month", "what is sitting over 90 days", "how much did we buy from this vendor this quarter". These are answered read-only, from your transactions.</li>
<li><b>Actions</b> — "add 20 of this to stock", "mark these five as damaged". These produce an action card you confirm. Nothing is written to your inventory without an explicit confirmation from you.</li>
</ul>

<h2 id="grounded">Grounded in transactions, not guessed</h2>
<p>The design rule Nova is built to is simple and non-negotiable: <b>facts are derived from your recorded transactions, and the numbers must match the Reports screen.</b> If Nova and the P&amp;L report disagree, that is a bug, not a difference of interpretation.</p>
<p>The same rule cuts the other way on invention. If you ask about a product that is not in your catalogue, Nova says it cannot find it. It does not create a plausible-looking row with a made-up SKU to satisfy the shape of the question. A request like "reorder everything low" is treated as a selector over products that exist — never as licence to invent one.</p>

<h2 id="language">English and Hinglish</h2>
<p>Nova understands questions in English and in Hinglish, which matters a great deal for the people who actually work the floor. The person who knows what is on the shelf is often not the person most comfortable typing formal English, and making them switch languages to ask a question is how a tool ends up used by one person in the office instead of the whole team.</p>

<h2 id="cards">Action cards keep you in control</h2>
<p>When Nova understands you want to change something, it does not change it. It builds the action — product, quantity, movement type, reason — and shows it to you as a card. You read it, adjust it if it is not quite right, and confirm. The resulting write is an ordinary transaction, indistinguishable in the ledger from one made through the normal screen, with the same audit trail.</p>
<p>This is deliberately more friction than a fully autonomous agent. Inventory is the one place where a confidently wrong write costs real money and takes an hour to unpick.</p>

<h2 id="availability">Where it is available</h2>
<p>Nova is part of the <b>MAX</b> tier and is not available on Starter or Growth. Every tier is currently priced at ₹0 during the launch period, which means Nova is reachable today — see <a href="/pricing">pricing</a> for exactly what each tier includes.</p>

<h2 id="privacy">What it can and cannot see</h2>
<p>Nova operates inside your workspace. It reads your workspace's data and nothing else, and the same server-side access rules that govern the app govern it — a request is verified against your membership of the workspace before any data is returned. It is not a shared model trained on your inventory; your stock levels are not somebody else's answers.</p>`,
  faqs: [
    { q: 'Which plan includes the AI assistant?', a: 'Nova is part of the MAX tier. Starter and Growth do not include it. Because every tier is currently priced at ₹0 during the launch period, it is reachable today.' },
    { q: 'Can it change my stock without asking?', a: 'No. Requests that would write something produce an action card you must confirm. Read-only questions are answered directly; writes always require a human confirmation.' },
    { q: 'Will its numbers match the reports?', a: 'They are built to. Nova derives facts from the same transaction record the reports read, so a disagreement between Nova and the Reports screen is treated as a defect.' },
    { q: 'Does it work in Hindi or Hinglish?', a: 'Yes — it handles English and Hinglish, which is deliberate: the people who know what is on the shelf should not have to switch languages to ask about it.' },
    { q: 'Is my inventory data used to train a model?', a: 'No. Nova queries your workspace to answer your question. Your data is not a training corpus, and requests are verified against your workspace membership before any data is read.' },
  ],
  links: [
    { href: '/features/inventory-reports-and-analytics', label: 'Reports and analytics' },
    { href: '/pricing', label: 'Pricing and plan limits' },
    { href: '/features', label: 'All features' },
    { href: '/about', label: 'About SmartShelfKart' },
  ],
});

export default [indexPage, barcode, lowStock, orders, billing, reports, ai];
