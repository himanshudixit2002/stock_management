import { site, plans } from '../site.mjs';
import { faqLd, esc } from '../layout.mjs';
import { section, wrap, cards, faqBlock, cta, related, table, toc, humanDate, articleLd, ledgerFigure } from '../blocks.mjs';
import blog1 from './blog.mjs';
import blog2 from './blog2.mjs';

const allGuides = [...blog1, ...blog2];

/* ------------------------------------------------------------------ */
/* /blog/                                                              */
/* ------------------------------------------------------------------ */

const blogIndex = {
  path: '/blog',
  file: 'blog.html',
  title: 'Inventory Management Guides — Formulas, Methods, Benchmarks',
  description:
    'Practical guides to inventory management: reorder points, safety stock, ABC analysis, turnover, barcode systems and cycle counting — written so you could apply them on paper.',
  trail: [
    { href: '/', label: 'Home' },
    { href: '/blog', label: 'Guides' },
  ],
  priority: '0.8',
  changefreq: 'monthly',
  schema: [
    {
      '@type': 'CollectionPage',
      name: 'Inventory management guides',
      description: 'Practical guides to inventory management methods and formulas.',
      url: site.origin + '/blog',
      hasPart: allGuides.map((g) => ({
        '@type': 'Article',
        headline: g.title,
        url: site.origin + g.path,
        datePublished: g.published,
      })),
    },
  ],
  body: `
<section class="hero">${wrap(`
  <p class="eyebrow">Guides</p>
  <h1 style="max-width:20ch">How inventory management actually works</h1>
  <p class="hero__lead">No listicles and no vendor waffle. These are explanations of the methods the software implements — the formulas, where each input comes from, worked examples, and the cases where the method stops being the right one. Written so you could apply them with a spreadsheet if you had to.</p>
`)}</section>

${section({
    tight: true,
    body: cards([
      { title: 'What is inventory management?', body: 'The whole discipline in one page: the four decisions it exists to answer, the terms that matter, and how to tell when a spreadsheet has stopped being enough.', href: '/blog/what-is-inventory-management', more: 'Start here' },
      { title: 'The reorder point formula', body: 'Lead time demand plus safety stock — with the variance split that tells you whether your real problem is demand or your supplier.', href: '/blog/reorder-point-formula', more: 'Read' },
      { title: 'The safety stock formula', body: 'Where the Z-score comes from, how to pick a service level, and why a flat "two weeks of cover" over-stocks and under-stocks simultaneously.', href: '/blog/safety-stock-formula', more: 'Read' },
      { title: 'ABC analysis', body: 'Finding the fifth of the catalogue that carries three quarters of the value, and what to do differently for each class.', href: '/blog/abc-analysis-inventory', more: 'Read' },
      { title: 'The inventory turnover ratio', body: 'The formula, sector benchmarks, why you must use COGS rather than revenue, and the blended-average trap.', href: '/blog/inventory-turnover-ratio', more: 'Read' },
      { title: 'Inventory for a small business', body: 'What to fix first, in order — and the six reasons implementations fail, almost none of which are software problems.', href: '/blog/inventory-management-for-small-business', more: 'Read' },
      { title: 'Setting up a barcode system', body: 'What hardware you actually need, SKU versus barcode, labelling products that have none, and a one-week rollout.', href: '/blog/barcode-inventory-system-guide', more: 'Read' },
      { title: 'Stock audits and cycle counting', body: 'Running a full count honestly, moving to cycle counting, count frequency by class, and handling variances.', href: '/blog/stock-audit-cycle-counting', more: 'Read' },
    ]),
  })}

${section({
    alt: true,
    title: 'Free calculators to go with them',
    lead: 'Each guide has a calculator that does its arithmetic. No sign-up, nothing stored.',
    body: cards([
      { title: 'Reorder point calculator', body: 'When to place the next order.', href: '/tools/reorder-point-calculator', more: 'Open' },
      { title: 'Safety stock calculator', body: 'How much buffer, and what it costs.', href: '/tools/safety-stock-calculator', more: 'Open' },
      { title: 'EOQ calculator', body: 'How much to order each time.', href: '/tools/economic-order-quantity-calculator', more: 'Open' },
      { title: 'Turnover calculator', body: 'Whether you are carrying too much.', href: '/tools/inventory-turnover-calculator', more: 'Open' },
    ]),
  })}

${cta()}`,
};

/* ------------------------------------------------------------------ */
/* /pricing                                                            */
/* ------------------------------------------------------------------ */

const pricingFaqs = [
  { q: 'Is SmartShelfKart really free?', a: 'Yes, on every tier, right now. All four tiers carry a monthly list price and all four are currently set to ₹0 for the launch period. No card is required to create a workspace.' },
  { q: 'What happens when the launch period ends?', a: 'The list prices shown here are what the tiers are designed to cost. We will give existing workspaces notice before anything changes, and your data is exportable to Excel at any time regardless.' },
  { q: 'What counts against the product limit?', a: 'Distinct products in your catalogue. Variants you have created as separate products each count as one. Archived products do not count toward the active limit.' },
  { q: 'Which tier includes the AI assistant?', a: 'Nova is part of the MAX tier. Starter and Growth do not include it. Since every tier is currently ₹0, MAX is reachable today.' },
  { q: 'Can I change tier later?', a: 'Yes. Changing tier does not migrate or delete data — it changes the limits and which features are unlocked.' },
  { q: 'Do I need a credit card to start?', a: 'No. Create a workspace with an email address and start using it.' },
  { q: 'Can I export my data if I leave?', a: 'Yes. Export to Excel covers your catalogue and report data. We think software that traps your data is software you will come to resent, so this is not gated behind a tier.' },
];

const pricing = {
  path: '/pricing',
  file: 'pricing.html',
  title: 'Pricing — Free on Every Tier During Launch | SmartShelfKart',
  description:
    'SmartShelfKart pricing: four tiers with user, product and order limits — all currently free during the launch period, including the tier with the Nova AI assistant.',
  trail: [
    { href: '/', label: 'Home' },
    { href: '/pricing', label: 'Pricing' },
  ],
  priority: '0.9',
  changefreq: 'monthly',
  schema: [
    faqLd(pricingFaqs),
    {
      '@type': 'Product',
      name: 'SmartShelfKart',
      description: 'Inventory management software for small and growing businesses.',
      brand: { '@id': site.origin + '/#organization' },
      offers: plans.map((p) => ({
        '@type': 'Offer',
        name: p.label,
        price: '0',
        priceCurrency: 'INR',
        description: p.description,
        availability: 'https://schema.org/InStock',
        url: site.origin + '/pricing',
      })),
    },
  ],
  body: `
<section class="hero" style="padding-bottom:34px">${wrap(`
  <p class="eyebrow">Pricing</p>
  <h1 style="max-width:18ch">Four tiers. All of them free right now.</h1>
  <p class="hero__lead">Each tier carries a monthly list price, and every one of them is currently set to ₹0 for the launch period — including MAX, the tier with the Nova AI assistant. No card, no trial clock, no feature that stops working on day fifteen.</p>
`)}</section>

<section class="sec sec--tight">${wrap(`<div class="plans">${plans
    .map(
      (p) => `<div class="plan${p.featured ? ' plan--hot' : ''}">
      ${p.featured ? '<p class="plan__tag">Most complete</p>' : '<p class="plan__tag">&nbsp;</p>'}
      <h3>${esc(p.label)}</h3>
      <p class="plan__desc">${esc(p.description)}</p>
      <p class="plan__price">Free</p>
      <p class="plan__was">&#8377;${p.listPrice.toLocaleString('en-IN')}/mo list price</p>
      <ul class="plan__limits">${Object.entries(p.limits)
        .map(([k, v]) => `<li><span>${esc(k)}</span><b>${esc(v)}</b></li>`)
        .join('')}
        <li><span>Nova AI assistant</span><b>${p.locked.includes('AI assistant') ? '&mdash;' : 'Included'}</b></li>
      </ul>
      <p style="margin:18px 0 0"><a class="btn btn--sm" href="${site.appUrl}" data-app-link>Start free</a></p>
    </div>`
    )
    .join('')}</div>`)}</section>

${section({
    alt: true,
    title: 'What every tier includes',
    lead: 'The limits differ. The product does not — core stock control is not held back to sell you an upgrade.',
    body: `<div class="grid">
      <div class="card"><h3>All 43 features</h3><p>Stock movements, purchase and sales orders, returns, billing, batch tracking, stock takes, warehouse zones, reports and the audit log — on every tier, subject only to the AI assistant note below.</p></div>
      <div class="card"><h3>Web, Android and iOS</h3><p>The same workspace on every platform, against one live database. Nothing is desktop-only.</p></div>
      <div class="card"><h3>Roles and permissions</h3><p>Invite staff and control exactly which screens they open and which actions they can take, on every tier.</p></div>
      <div class="card"><h3>Excel import and export</h3><p>Bulk import, bulk update matched on SKU or barcode, and export whenever you want your data back. Never gated.</p></div>
      <div class="card"><h3>Every report</h3><p>Profit and loss, ABC analysis, valuation, ageing, stock ledger, price history and the full transaction record.</p></div>
      <div class="card"><h3>Nova AI assistant</h3><p>Part of the MAX tier. Starter and Growth do not include it — and since MAX is currently ₹0, that is a tier choice rather than a payment.</p></div>
    </div>`,
  })}

${section({
    title: 'Full comparison',
    body: table(
      ['', ...plans.map((p) => esc(p.label))],
      [
        ['List price', ...plans.map((p) => '&#8377;' + p.listPrice.toLocaleString('en-IN') + '/mo')],
        ['Price today', ...plans.map(() => '<b>Free</b>')],
        ...['Team members', 'Products', 'Invoices', 'Sales orders', 'Purchase orders'].map((k) => [
          k,
          ...plans.map((p) => esc(p.limits[k] || '—')),
        ]),
        ['Nova AI assistant', ...plans.map((p) => (p.locked.includes('AI assistant') ? '&mdash;' : '&#10003;'))],
        ['All other features', ...plans.map(() => '&#10003;')],
        ['Excel import &amp; export', ...plans.map(() => '&#10003;')],
        ['Roles &amp; permissions', ...plans.map(() => '&#10003;')],
      ]
    ),
  })}

${section({ alt: true, title: 'Pricing questions', body: faqBlock(pricingFaqs) })}
${cta({ title: 'Create a workspace', body: 'An email address is all it takes. Nothing to install, no card, and every tier is free during launch.' })}`,
};

/* ------------------------------------------------------------------ */
/* /compare/inventory-management-software-vs-excel                     */
/* ------------------------------------------------------------------ */

const vsExcelFaqs = [
  { q: 'Can I manage inventory in Excel?', a: 'Yes, and for one person with a small stable catalogue it is a reasonable choice. Excel is fast, flexible and already installed. It stops being suitable when several people need to update stock at once, or when you need to know who changed a figure and why.' },
  { q: 'What is the main thing a spreadsheet cannot do?', a: 'Record a transaction. A spreadsheet stores the current quantity; changing it destroys the previous value. Inventory software stores the movements and derives the quantity, so history is reconstructable and every report can be traced to source.' },
  { q: 'At what point should I move off a spreadsheet?', a: 'When two people need simultaneous access, when you cannot answer "who changed this?", when a customer has been sold something already promised elsewhere, or when returns and part-deliveries need one person who understands the file.' },
  { q: 'Will I lose my spreadsheet data when I move?', a: 'No. Import from Excel reads an .xlsx file and creates products in bulk, matching on SKU or barcode, and export sends your data back out at any time.' },
  { q: 'Is inventory software harder to use than Excel?', a: 'The daily work is usually easier because the screens are built for the task. The setup is more demanding, because the software insists on a clean catalogue where a spreadsheet will happily hold whatever you put in it.' },
];

const vsExcel = {
  path: '/compare/inventory-management-software-vs-excel',
  file: 'compare/inventory-management-software-vs-excel.html',
  title: 'Inventory Software vs Excel — An Honest Comparison',
  description:
    'Excel versus inventory management software: what a spreadsheet genuinely does better, the one thing it structurally cannot do, and when it stops being enough.',
  trail: [
    { href: '/', label: 'Home' },
    { href: '/compare/inventory-management-software-vs-excel', label: 'vs. Excel' },
  ],
  priority: '0.8',
  changefreq: 'yearly',
  ogType: 'article',
  published: '2026-05-27',
  schema: [
    articleLd({
      path: '/compare/inventory-management-software-vs-excel',
      title: 'Inventory management software vs. Excel',
      description: 'An honest comparison of spreadsheets and inventory software for stock management.',
      published: '2026-05-27',
      modified: '2026-09-08',
    }),
    faqLd(vsExcelFaqs),
  ],
  body: `
<section class="hero" style="padding-bottom:30px">${wrap(`
  <p class="eyebrow">Comparison</p>
  <h1 style="max-width:22ch">Inventory software vs. Excel, honestly</h1>
  <p class="hero__lead">We sell inventory software, so treat what follows accordingly — but a comparison that pretends spreadsheets are useless is not worth reading. Excel is genuinely good at this up to a well-defined point. Here is where that point is, and why.</p>
`)}</section>

<section class="sec sec--tight">${wrap(
    `<p class="meta"><time datetime="2026-05-27">Published ${humanDate('2026-05-27')}</time> &middot; <time datetime="2026-09-08">updated ${humanDate('2026-09-08')}</time></p>
  ${toc([
    { id: 'excel-wins', label: 'What Excel is genuinely better at' },
    { id: 'structural', label: 'The one structural limitation' },
    { id: 'side', label: 'Side by side' },
    { id: 'signals', label: 'Six signals you have outgrown it' },
    { id: 'cost', label: 'The real cost of staying' },
    { id: 'move', label: 'How to move without losing anything' },
  ])}
  <div class="prose">
  <h2 id="excel-wins">What Excel is genuinely better at</h2>
  <p>These are real advantages and they are why so many businesses stay:</p>
  <ul>
  <li><b>Ad-hoc analysis.</b> No inventory system will ever match a spreadsheet for "let me just check something". Pivot it, chart it, throw it away. This never stops being true, which is why good inventory software exports to Excel rather than pretending you will not want to.</li>
  <li><b>Zero learning curve.</b> Everyone already knows it.</li>
  <li><b>Infinite flexibility.</b> A column for anything, a formula for anything. No vendor decides what fields exist.</li>
  <li><b>No cost, no commitment, no migration.</b></li>
  <li><b>It works offline, on any machine, forever.</b> A file from 2011 still opens.</li>
  </ul>
  <p>For a sole trader with 80 products and one person touching stock, a spreadsheet is very likely the correct tool. Adopting software there would be adding process for no return.</p>

  <h2 id="structural">The one structural limitation</h2>
  ${ledgerFigure('The same product, the same closing quantity, two entirely different amounts of information.')}
  <p>Everything else on this page follows from a single fact: <b>a spreadsheet stores the current quantity, and inventory is fundamentally a history of movements.</b></p>
  <p>When you change a cell from 40 to 37, the 40 is gone. There is no record that three units left, no reason, no timestamp, no person. The number is now 37 and the only evidence is the number itself.</p>
  <div class="formula">Spreadsheet:  quantity = whatever is in the cell
Inventory system:  quantity = sum of all recorded movements</div>
  <p>That difference is not cosmetic. It is the reason a spreadsheet cannot produce a trustworthy margin report, cannot explain a discrepancy, cannot unwind a return correctly, and cannot answer "who changed this". Those are not missing features that a clever template could add — they need history, and history is exactly what the model discards.</p>

  <h2 id="side">Side by side</h2>
  ${table(
    ['', 'Excel / Google Sheets', 'Inventory software'],
    [
      ['Setup time', 'Minutes', 'Hours to days — a clean catalogue is required'],
      ['Cost', 'Free or near it', 'Free to substantial, depending on the vendor'],
      ['Ad-hoc analysis', 'Excellent', 'Limited; export to a spreadsheet'],
      ['Multiple simultaneous users', 'Conflicts, or serialised access', 'Designed for it'],
      ['Who changed what', 'Not available', 'Audit log per change'],
      ['Movement history with reasons', 'Only if hand-built, and it decays', 'Built in'],
      ['Barcode scanning', 'Possible into a cell', 'Wired into the movement screens'],
      ['Reorder alerts', 'Conditional formatting you must remember to look at', 'Per-product thresholds, live list'],
      ['Purchase and sales orders', 'Separate files', 'Linked to stock, with part-receipts'],
      ['Returns and credit notes', 'Manual and error-prone', 'Modelled explicitly'],
      ['Margin by product', 'Possible with effort; goes stale', 'Derived from recorded transactions'],
      ['Permissions', 'File-level at best', 'Per-role, per-screen, per-action'],
      ['Offline', 'Fully', 'Partially, with sync'],
      ['Risk of catastrophic error', 'High — one bad paste, one wrong sort', 'Low; changes are appended, not overwritten'],
    ]
  )}
  <div class="callout callout--warn"><p><b>The wrong-sort problem deserves its own mention.</b> Sorting one column without selecting the others silently detaches every quantity from its product. It produces a file that looks perfectly normal, and businesses have run on such a file for months before noticing.</p></div>

  <h2 id="signals">Six signals you have outgrown it</h2>
  <ol>
  <li><b>Two people need it open at once.</b> Even with cloud co-editing, two people editing quantities on one row is a coin flip.</li>
  <li><b>You have asked "who changed this?" and could not find out.</b></li>
  <li><b>Something was sold twice.</b> Spreadsheets have no notion of allocated or reserved stock, so the last unit can be promised to two customers.</li>
  <li><b>A returns or part-delivery question needs the one person who understands the file.</b></li>
  <li><b>Quarterly margin analysis takes an evening.</b> That analysis should be a screen.</li>
  <li><b>Staff have stopped trusting the number and check the shelf instead.</b> This is the terminal signal: the file is now overhead with no benefit.</li>
  </ol>

  <h2 id="cost">The real cost of staying</h2>
  <p>The spreadsheet is free; running the business on it is not. The costs are diffuse, which is precisely why they persist:</p>
  <ul>
  <li>Stockouts, because thresholds were never per-product and nobody watched the sheet.</li>
  <li>Overstock, because "order extra to be safe" is the only strategy available without variability data — and carrying stock costs 20–30% a year.</li>
  <li>Hours of reconciliation, monthly, forever.</li>
  <li>Shrinkage that is invisible because there is no expected figure to compare against.</li>
  <li>Decisions made on numbers that were correct when they were pasted.</li>
  </ul>
  <p>A business holding ₹20 lakh of stock is paying roughly ₹5 lakh a year in carrying cost. Cutting that by a tenth through properly set <a href="/tools/reorder-point-calculator">reorder points</a> is ₹50,000 a year, which is more than most inventory software costs — and all of it is free here during launch.</p>

  <h2 id="move">How to move without losing anything</h2>
  <ol>
  <li><b>Clean the sheet first.</b> One row per product, a stable SKU, no merged cells, no blank spacer rows, no colour-as-data. Migrating a messy catalogue produces a messy system.</li>
  <li><b>Delete what you no longer sell</b> before importing rather than after.</li>
  <li><b>Import in bulk</b> matched on SKU or barcode — never retype. Retyping is where migrations die.</li>
  <li><b>Do one honest physical count</b> as the opening position. Do not import the sheet's quantities on faith.</li>
  <li><b>Run both for two weeks</b> if it helps confidence, then stop. Running two systems indefinitely is worse than either alone.</li>
  <li><b>Keep the spreadsheet for analysis.</b> Export whenever you want to explore something. That is what it was always best at.</li>
  </ol>
  <p><a href="/features">SmartShelfKart</a> imports from Excel, updates in bulk from Excel matched on SKU, and exports back to Excel — deliberately, because the goal is to replace the spreadsheet as a system of record, not to take your data hostage.</p>
  </div>
  ${related('Keep reading', [
    { href: '/blog/inventory-management-for-small-business', label: 'Inventory management for a small business' },
    { href: '/blog/what-is-inventory-management', label: 'What is inventory management?' },
    { href: '/compare/free-inventory-management-software-india', label: 'What "free" inventory software really means' },
    { href: '/pricing', label: 'SmartShelfKart pricing' },
  ])}`,
    'wrap--narrow'
  )}</section>

${section({ alt: true, title: 'Questions', body: faqBlock(vsExcelFaqs) })}
${cta()}`,
};

/* ------------------------------------------------------------------ */
/* /compare/free-inventory-management-software-india                   */
/* ------------------------------------------------------------------ */

const freeFaqs = [
  { q: 'Is there genuinely free inventory management software?', a: 'Yes, in three different senses: open-source software that is free to license but costs you hosting and maintenance; free tiers of commercial products, usually limited by users or records; and launch or promotional pricing. Each has different long-term implications, and it is worth knowing which one you are signing up to.' },
  { q: 'What is the catch with free tiers?', a: 'Usually a limit that binds exactly when the software has become essential — user seats, record counts, or gating exports so your data is hard to take with you. The export question is the one to check first.' },
  { q: 'Is SmartShelfKart free?', a: 'Every tier is currently priced at ₹0 during the launch period, including the top tier. The tiers carry list prices which is what they are designed to cost later, and existing workspaces will be given notice before anything changes.' },
  { q: 'Can I export my data out of a free plan?', a: 'In SmartShelfKart, yes — Excel export is available on every tier and is not gated. Check this before adopting any free product; if export is a paid feature, the free plan is a trap rather than a plan.' },
  { q: 'Is open-source inventory software cheaper?', a: 'The licence is free; the total cost usually is not. You are taking on hosting, upgrades, backups, security patching and the internal expertise to run all of it. That is a good trade if you have the capability in-house and a poor one if you do not.' },
];

const freeIndia = {
  path: '/compare/free-inventory-management-software-india',
  file: 'compare/free-inventory-management-software-india.html',
  title: 'Free Inventory Management Software: What "Free" Really Means',
  description:
    'The three kinds of free inventory software, what each really costs, the seven questions to ask before adopting one, and how to avoid a free plan that traps your data.',
  trail: [
    { href: '/', label: 'Home' },
    { href: '/compare/free-inventory-management-software-india', label: 'Free inventory software' },
  ],
  priority: '0.7',
  changefreq: 'yearly',
  ogType: 'article',
  published: '2026-07-29',
  schema: [
    articleLd({
      path: '/compare/free-inventory-management-software-india',
      title: 'Free inventory management software: what "free" really means',
      description: 'The three kinds of free inventory software and what each actually costs.',
      published: '2026-07-29',
      modified: '2026-09-08',
    }),
    faqLd(freeFaqs),
  ],
  body: `
<section class="hero" style="padding-bottom:30px">${wrap(`
  <p class="eyebrow">Buyer's guide</p>
  <h1 style="max-width:22ch">Free inventory management software: what "free" actually means</h1>
  <p class="hero__lead">Three quite different things get called free, and they have very different consequences two years in. This page is about telling them apart and knowing what to check — not about ranking vendors, which is a job we cannot do impartially.</p>
`)}</section>

<section class="sec sec--tight">${wrap(
    `<p class="meta"><time datetime="2026-07-29">Published ${humanDate('2026-07-29')}</time> &middot; <time datetime="2026-09-08">updated ${humanDate('2026-09-08')}</time></p>
  ${toc([
    { id: 'three', label: 'The three kinds of free' },
    { id: 'limits', label: 'Where free tiers usually bind' },
    { id: 'questions', label: 'Seven questions to ask first' },
    { id: 'trap', label: 'The data-export trap' },
    { id: 'ours', label: 'Where SmartShelfKart sits' },
  ])}
  <div class="prose">
  <h2 id="three">The three kinds of free</h2>
  ${table(
    ['Kind', 'What you pay', 'Suits'],
    [
      ['Open source', 'Nothing for the licence; hosting, upgrades, backups, security patching and internal expertise', 'Teams with real technical capability in-house'],
      ['Free tier of a commercial product', 'Nothing, until you cross a user, record or feature limit', 'Small businesses whose scale stays inside the limits'],
      ['Launch or promotional pricing', 'Nothing now; list price later, with notice', 'Businesses willing to adopt early in exchange for full access'],
    ]
  )}
  <p>None of these is dishonest, and all three can be the right choice. What causes trouble is adopting one while assuming the terms of another — most often assuming a free tier is permanent and unlimited when it is neither.</p>

  <h2 id="limits">Where free tiers usually bind</h2>
  <p>Free tiers are designed to become insufficient at the point the software has become load-bearing. The common limits, roughly in order of how quickly they bite:</p>
  <ul>
  <li><b>User seats.</b> The most common, and the one that bites fastest. A one-user free tier is unusable the moment you hire.</li>
  <li><b>Product or record counts.</b> Fine until a catalogue grows, then abrupt.</li>
  <li><b>Transactions or invoices per month.</b> Scales with success, which is when you can least afford disruption.</li>
  <li><b>Locations or warehouses.</b> Often the first paid-tier trigger for a growing business.</li>
  <li><b>Feature gates.</b> Reports, exports, integrations, or the API withheld from the free tier.</li>
  <li><b>History retention.</b> Older transactions aged out, which quietly destroys the year-on-year comparison you will eventually want.</li>
  </ul>
  <p>Read them before adopting, not after. The relevant question is not "does the free tier work today" but "which limit will I hit first, and how disruptive will that day be".</p>

  <h2 id="questions">Seven questions to ask before adopting anything free</h2>
  <ol>
  <li><b>Can I export everything, on the free tier, without paying?</b> If not, stop here. This is the only question that is genuinely disqualifying.</li>
  <li><b>Which limit will I hit first, and when?</b> Project it from your actual growth, not from today's numbers.</li>
  <li><b>What does the paid tier cost when I hit it?</b> A free tier followed by a large step is a deferred purchase decision, not a free product.</li>
  <li><b>How long is transaction history kept?</b> Ageing out old records makes year-on-year comparison impossible.</li>
  <li><b>Does it work on a phone?</b> Stock moves where the goods are. Desk-bound software gets used at the end of the day, from memory, which defeats the purpose.</li>
  <li><b>Can I give staff limited access?</b> If everyone needs the owner's login, you will not roll it out to staff, and a system only the owner uses is a very expensive spreadsheet.</li>
  <li><b>Does it record movements, or just quantities?</b> If corrections overwrite rather than append, you have bought a spreadsheet with a nicer interface.</li>
  </ol>
  <div class="callout"><p><b>Question 1 is the only one that is genuinely non-negotiable.</b> Every other limitation is survivable if you can leave with your data. If you cannot, you are not choosing software — you are choosing a vendor permanently.</p></div>

  <h2 id="trap">The data-export trap</h2>
  <p>The most costly pattern in this market is a free tier that lets you enter unlimited data and charges to get it out. Eighteen months in, the switching cost is not the new software — it is the four years of transaction history you cannot retrieve, and the vendor knows it.</p>
  <p>Test this on day one, not on the day you want to leave. Create a few records, export them, and open the file. If the export is missing fields, is gated behind a paid tier, or does not exist, treat that as a decision the vendor has already made about the relationship.</p>

  <h2 id="ours">Where SmartShelfKart sits</h2>
  <p>Being explicit, since this is our site:</p>
  <ul>
  <li>SmartShelfKart is in the <b>third category</b> — launch pricing. Four tiers exist with list prices of ₹999 to ₹9,999 a month, and all four are currently set to ₹0.</li>
  <li>The tiers have <a href="/pricing">real limits</a> on users, products and monthly orders. They are published rather than discovered.</li>
  <li><b>Excel export is available on every tier and is not gated.</b> By question 1 above, that is the commitment that matters.</li>
  <li>The <a href="/features/ai-inventory-assistant">Nova AI assistant</a> is restricted to the MAX tier. Everything else is on every tier.</li>
  <li>Existing workspaces will be given notice before pricing changes.</li>
  </ul>
  <p>If you are evaluating several options, run the seven questions against each of them including this one. A vendor that answers them straightforwardly is telling you something useful regardless of the answers.</p>
  </div>
  ${related('Keep reading', [
    { href: '/pricing', label: 'SmartShelfKart pricing and limits' },
    { href: '/compare/inventory-management-software-vs-excel', label: 'Inventory software vs. Excel' },
    { href: '/blog/inventory-management-for-small-business', label: 'Inventory management for a small business' },
    { href: '/features', label: 'The full feature list' },
  ])}`,
    'wrap--narrow'
  )}</section>

${section({ alt: true, title: 'Questions', body: faqBlock(freeFaqs) })}
${cta()}`,
};

/* ------------------------------------------------------------------ */
/* /about, /contact, 404                                               */
/* ------------------------------------------------------------------ */

const about = {
  path: '/about',
  file: 'about.html',
  title: 'About SmartShelfKart — Who Built It and Why',
  description:
    'SmartShelfKart is inventory management software for small and growing businesses. What we built, the principles behind it, and what it deliberately does not do.',
  trail: [
    { href: '/', label: 'Home' },
    { href: '/about', label: 'About' },
  ],
  priority: '0.5',
  changefreq: 'yearly',
  body: `
<section class="hero" style="padding-bottom:30px">${wrap(`
  <p class="eyebrow">About</p>
  <h1 style="max-width:20ch">Inventory software for businesses that cannot run an implementation project</h1>
  <p class="hero__lead">There is a wide gap between a spreadsheet and an ERP. SmartShelfKart is built for the businesses sitting in it — where a real system is overdue, and a six-month rollout with a consultant is not going to happen.</p>
`)}</section>

<section class="sec sec--tight">${wrap(
    `<div class="prose">
  <h2>What it is</h2>
  <p>SmartShelfKart is inventory management software covering stock movements, purchase and sales orders, returns, billing, batch and expiry tracking, stock takes, reports and role-based staff access. It runs on the web, Android and iOS from a single workspace and a single live database.</p>
  <p>It is built with Flutter and Firebase, with a Python service on Google Cloud Run behind the Nova AI assistant. That stack is why the same product runs properly on three platforms rather than being a mobile app with a neglected web version.</p>

  <h2>The principles it is built to</h2>
  <ul>
  <li><b>Every number is derived, never entered.</b> There is no screen where you type a closing balance or a valuation. Quantities are the sum of recorded movements, so any figure can be traced back to the transactions that produced it.</li>
  <li><b>Corrections append, they do not overwrite.</b> A wrong quantity is fixed with an adjustment carrying a reason, not by retyping. History survives, which is what makes the audit log and the reports worth anything.</li>
  <li><b>The person who knows what happened should be able to record it.</b> Which means on a phone, in seconds, with permissions narrow enough that giving staff access is not a risk.</li>
  <li><b>Your data is yours.</b> Excel export on every tier, not gated behind an upgrade.</li>
  <li><b>The AI does not invent things.</b> Nova answers from your recorded transactions and its numbers must match the Reports screen. If it cannot find a product, it says so rather than producing a plausible-looking row.</li>
  </ul>

  <h2>What it deliberately does not do</h2>
  <p>Being clear about this is more useful than a longer feature list:</p>
  <ul>
  <li><b>It is not a GST return-filing tool.</b> It records per-line tax, stores your GSTIN and reports tax collected by rate. It does not produce GSTR filings, e-invoices or an HSN master.</li>
  <li><b>It is not a full accounting package.</b> It handles invoices, payments and credit notes; it is not a general ledger.</li>
  <li><b>It is not a warehouse management system.</b> There are zones and bins, but no wave picking, slotting optimisation or conveyor integration.</li>
  <li><b>It does not order from suppliers automatically.</b> It suggests quantities; a person sends the order.</li>
  <li><b>It is not designed for long periods fully offline.</b> It caches and syncs; it does not assume a disconnected warehouse.</li>
  </ul>

  <h2>Where it is</h2>
  <p>The web app is at <a href="${site.appUrl}" data-app-link>smartshelfkart.com/app</a> and the Android app is <a href="${site.playStoreUrl}" rel="noopener">on Google Play</a>. Every plan tier is <a href="/pricing">free during the launch period</a>.</p>
  <p>Questions, problems or feature requests: <a href="/contact">get in touch</a>.</p>
  </div>`,
    'wrap--narrow'
  )}</section>
${cta()}`,
};

const contact = {
  path: '/contact',
  file: 'contact.html',
  title: 'Contact SmartShelfKart — Support and Enquiries',
  description:
    'Get in touch with SmartShelfKart for support, bug reports, feature requests or questions about plans and data export.',
  trail: [
    { href: '/', label: 'Home' },
    { href: '/contact', label: 'Contact' },
  ],
  priority: '0.4',
  changefreq: 'yearly',
  schema: [
    {
      '@type': 'ContactPage',
      name: 'Contact SmartShelfKart',
      url: site.origin + '/contact',
      mainEntity: { '@id': site.origin + '/#organization' },
    },
  ],
  body: `
<section class="hero" style="padding-bottom:30px">${wrap(`
  <p class="eyebrow">Contact</p>
  <h1 style="max-width:16ch">Get in touch</h1>
  <p class="hero__lead">Support questions, bug reports, feature requests, or anything about plans, limits and data export.</p>
`)}</section>

<section class="sec sec--tight">${wrap(
    `<div class="grid">
    <div class="card"><h3>Email</h3><p><a href="mailto:${site.email}">${site.email}</a><br>We read everything. Include your workspace name and, for a bug, what you did and what happened.</p></div>
    <div class="card"><h3>In-app support</h3><p>The Help and Support screens inside the app carry answers to the most common questions, and the About screen shows your version number — useful to quote in a bug report.</p></div>
    <div class="card"><h3>Android</h3><p>Issues specific to the Android build can also be raised through <a href="${site.playStoreUrl}" rel="noopener">the Google Play listing</a>.</p></div>
    <div class="card"><h3>Privacy and data</h3><p>See the <a href="/privacy-policy">privacy policy</a>, or the <a href="/data-deletion">data deletion page</a> to request removal of your account and data.</p></div>
  </div>
  <div class="prose" style="margin-top:36px">
    <h2>Before you write</h2>
    <p>These come up most often and are answered on the site:</p>
    <ul>
    <li><a href="/pricing">Is it free, and what are the limits?</a></li>
    <li><a href="/compare/inventory-management-software-vs-excel#move">How do I move my spreadsheet in?</a></li>
    <li><a href="/features/ai-inventory-assistant">Which tier includes the AI assistant?</a></li>
    <li><a href="/features/gst-billing-and-invoicing#tax">Does it handle GST?</a></li>
    </ul>
  </div>`,
    'wrap--narrow'
  )}</section>`,
};

const notFound = {
  path: '/404',
  file: '404.html',
  title: 'Page Not Found — SmartShelfKart',
  description: 'That page does not exist. Here is where everything else lives.',
  noindex: true,
  skipSitemap: true,
  trail: [{ href: '/', label: 'Home' }],
  body: `
<section class="hero">${wrap(`
  <p class="eyebrow">404</p>
  <h1 style="max-width:16ch">That page does not exist</h1>
  <p class="hero__lead">The link may be out of date, or the address may have a typo. Everything on the site is one click from here.</p>
  <div class="btnrow" style="margin-top:24px">
    <a class="btn" href="/">Home</a>
    <a class="btn btn--ghost" href="${site.appUrl}" data-app-link>Open the app</a>
  </div>
`)}</section>
${section({
    tight: true,
    body: cards([
      { title: 'Features', body: 'Every screen in the product, grouped the way the app groups it.', href: '/features', more: 'Browse' },
      { title: 'Pricing', body: 'Four tiers, their limits, and what each costs.', href: '/pricing', more: 'View' },
      { title: 'Free calculators', body: 'Reorder point, safety stock, EOQ and turnover.', href: '/tools', more: 'Open' },
      { title: 'Guides', body: 'How inventory management actually works.', href: '/blog', more: 'Read' },
    ]),
  })}`,
};

export default [blogIndex, pricing, vsExcel, freeIndia, about, contact, notFound];
