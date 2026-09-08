import { site } from '../site.mjs';
import { faqLd, esc } from '../layout.mjs';
import { section, wrap, cards, faqBlock, cta, related, table, toc, humanDate, articleLd } from '../blocks.mjs';

export function guide({ slug, title, h1, description, published, modified, lead, contents, sections, faqs, links }) {
  const path = '/blog/' + slug;
  const trail = [
    { href: '/', label: 'Home' },
    { href: '/blog', label: 'Guides' },
    { href: path, label: h1.length > 40 ? h1.slice(0, 38) + '…' : h1 },
  ];
  const body = `
<article>
<section class="hero" style="padding-bottom:30px">${wrap(`
  <p class="eyebrow">Guide</p>
  <h1 style="max-width:24ch">${h1}</h1>
  <p class="hero__lead">${lead}</p>
`)}</section>
<section class="sec sec--tight">${wrap(
    `<p class="meta"><time datetime="${published}">Published ${humanDate(published)}</time>${
      modified && modified !== published ? ` &middot; <time datetime="${modified}">updated ${humanDate(modified)}</time>` : ''
    } &middot; ${Math.max(4, Math.round(sections.replace(/<[^>]+>/g, ' ').split(/\s+/).length / 210))} min read</p>
     ${toc(contents)}
     <div class="prose">${sections}</div>
     ${related('Keep reading', links)}`,
    'wrap--narrow'
  )}</section>
</article>
${section({ alt: true, title: 'Questions', body: faqBlock(faqs) })}
${cta()}`;

  return {
    path,
    file: 'blog/' + slug + '.html',
    title,
    description,
    trail,
    priority: '0.7',
    changefreq: 'yearly',
    ogType: 'article',
    published,
    schema: [articleLd({ path, title: h1, description, published, modified }), faqLd(faqs)],
    body,
  };
}

/* ================================================================== */

const whatIs = guide({
  slug: 'what-is-inventory-management',
  title: 'What Is Inventory Management? A Practical Guide',
  h1: 'What is inventory management?',
  description:
    'Inventory management explained: the four decisions it exists to answer, the terms that matter, the core methods, and how to tell when a spreadsheet has stopped being enough.',
  published: '2026-03-04',
  modified: '2026-09-08',
  lead: 'Inventory management is the practice of knowing what stock you hold, what it is worth, where it is, and what to do about it next. Everything else — the formulas, the software, the counting — exists to serve those four questions.',
  contents: [
    { id: 'definition', label: 'A working definition' },
    { id: 'four', label: 'The four decisions' },
    { id: 'terms', label: 'The terms that actually matter' },
    { id: 'types', label: 'Types of inventory' },
    { id: 'methods', label: 'The core methods' },
    { id: 'costs', label: 'What holding stock really costs' },
    { id: 'signals', label: 'When a spreadsheet stops being enough' },
    { id: 'start', label: 'How to start' },
  ],
  sections: `
<h2 id="definition">A working definition</h2>
<p>Inventory management is the set of practices by which a business tracks the goods it holds and decides how much of each to hold. That covers ordering, receiving, storing, counting, valuing and eventually selling or writing off — and it covers the decisions as much as the record-keeping.</p>
<p>The record-keeping half gets most of the attention because it is visible: the counting, the scanning, the reconciling. But an accurate count that nobody acts on is just an expensive hobby. The decisions are where the money is.</p>

<h2 id="four">The four decisions it exists to answer</h2>
<p>Strip away the vocabulary and every inventory system, from a paper ledger to a warehouse management platform, exists to answer four questions:</p>
<ol>
<li><b>What do I have?</b> The current position, by product and by location, accurate enough to promise to a customer.</li>
<li><b>When should I order more?</b> The <a href="/blog/reorder-point-formula">reorder point</a> — the level at which replenishment must start if you are to avoid running out.</li>
<li><b>How much should I order?</b> The order quantity, balancing the cost of ordering against the cost of holding — the domain of <a href="/tools/economic-order-quantity-calculator">EOQ</a>.</li>
<li><b>What should I stop holding?</b> Dead, obsolete and expiring stock, which quietly consumes capital and space until somebody decides to deal with it.</li>
</ol>
<p>A system that answers the first question and none of the others is a stock count, not inventory management. That distinction is precisely where most spreadsheet-based setups sit.</p>

<h2 id="terms">The terms that actually matter</h2>
${table(
  ['Term', 'What it means', 'Why you care'],
  [
    ['SKU', 'Stock keeping unit — your own identifier for a distinct sellable item', 'Two sizes of the same product are two SKUs. Getting this granularity right determines whether any of your data is usable'],
    ['Lead time', 'Days from placing an order to the stock being available to sell', 'Drives your reorder point. Use your measured figure, not the supplier\'s promise'],
    ['Reorder point', 'The stock level that triggers a new order', 'The single most useful number to set correctly per product'],
    ['Safety stock', 'Buffer held against demand and supply variability', 'Sized by how variable things are, not by how nervous you feel'],
    ['Service level', 'The share of cycles you get through without a stockout', 'A business decision. 95% is a common default'],
    ['Turnover', 'How many times a year stock sells through', 'The headline efficiency measure; read alongside stockouts'],
    ['Carrying cost', 'Annual cost of holding one unit', 'Typically 20–30% of unit cost. Usually underestimated'],
    ['Shrinkage', 'Stock that disappears — theft, damage, miscounts', 'Invisible unless you count and record reasons'],
    ['Dead stock', 'Stock with no realistic prospect of selling', 'A loss already taken; holding it only delays recognising it'],
  ]
)}

<h2 id="types">Types of inventory</h2>
<p>Not all stock is the same kind of asset, and treating it as one is why some businesses cannot explain their own numbers:</p>
<ul>
<li><b>Raw materials</b> — inputs waiting to be used. Driven by production schedules.</li>
<li><b>Work in progress</b> — partly finished goods. Consumes capital and is easy to lose track of entirely.</li>
<li><b>Finished goods</b> — ready to sell. What most retail and distribution businesses mean by "stock".</li>
<li><b>MRO</b> — maintenance, repair and operations supplies. Never sold, so frequently unmanaged, and frequently the cause of expensive downtime.</li>
<li><b>Safety stock</b> — deliberate buffer, not surplus. The distinction is a decision you recorded, not a property of the goods.</li>
<li><b>In transit</b> — bought and paid for, not yet arrived. Forgetting this is a classic cause of double-ordering.</li>
</ul>

<h2 id="methods">The core methods</h2>
<h3>Reorder point with a fixed order quantity</h3>
<p>The workhorse for small businesses. Each product has a trigger level and an order quantity; crossing the trigger fires an order. Simple, robust and easy to automate. Combine a <a href="/tools/reorder-point-calculator">calculated reorder point</a> with an <a href="/tools/economic-order-quantity-calculator">EOQ</a> quantity and you have a complete policy.</p>
<h3>Periodic review</h3>
<p>Rather than a trigger level, you review on a schedule — every Monday, say — and top up to a target. Better where a supplier has a fixed delivery day. It requires slightly more buffer, because you carry risk over the review interval as well as the lead time.</p>
<h3>ABC analysis</h3>
<p>Sort products by the value they represent and treat the classes differently. Usually about 20% of lines carry 70–80% of value. <a href="/blog/abc-analysis-inventory">The method is here</a> and it is the highest-leverage hour you can spend on a catalogue you have never analysed.</p>
<h3>FIFO, LIFO and weighted average</h3>
<p>Costing conventions that decide which cost is released when you sell. FIFO — oldest first — matches how physical goods should move and is the sane default for anything perishable.</p>
<h3>Cycle counting</h3>
<p>Counting a slice of the catalogue continuously rather than shutting down once a year for a full count. <a href="/blog/stock-audit-cycle-counting">More on that here.</a></p>

<h2 id="costs">What holding stock really costs</h2>
<p>The invoice price is the visible cost. The annual carrying cost is the one that decides whether a policy is sane, and it typically runs 20–30% of unit value per year:</p>
<ul>
<li><b>Capital</b> — cash in stock is cash not in the business. If you borrow, this is your actual interest rate.</li>
<li><b>Storage</b> — rent, shelving, handling, utilities.</li>
<li><b>Risk</b> — theft, damage, obsolescence, expiry.</li>
<li><b>Insurance and tax</b> on the value held.</li>
</ul>
<p>At 25%, ₹10 lakh of stock costs about ₹2.5 lakh a year to hold. That figure is what makes "just order more, to be safe" an expensive instinct — and what makes the effort of setting reorder points properly pay for itself.</p>

<h2 id="signals">When a spreadsheet stops being enough</h2>
<p>Spreadsheets are genuinely good at inventory up to a point, and it is worth being honest about where that point is. You have passed it when any of these is true:</p>
<ul>
<li>Two people need to update stock at the same time.</li>
<li>You have asked "who changed this, and why?" and could not find out.</li>
<li>Someone sold something that was already promised to another customer.</li>
<li>You cannot answer what margin you made on a category last quarter without an evening's work.</li>
<li>Returns, part-deliveries or credit notes have to be handled "carefully" by one person who understands the sheet.</li>
<li>The stock figure is routinely wrong and everyone has learned to check the shelf instead.</li>
</ul>
<p>The failure is not that spreadsheets cannot hold the data. It is that they have no concept of a transaction — a quantity change with a type, a reason, a timestamp and a person attached. Without that, history cannot be reconstructed and reports cannot be trusted. <a href="/compare/inventory-management-software-vs-excel">The full comparison is here.</a></p>

<h2 id="start">How to start, in order</h2>
<ol>
<li><b>Get the catalogue right.</b> One row per genuinely distinct sellable item, with a stable SKU. Do this badly and everything downstream is unusable.</li>
<li><b>Do one honest full count.</b> Every later number is built on this one. Do not skip it and do not adjust it to match the books.</li>
<li><b>Record movements as they happen.</b> Not at the end of the day, not from memory. This is a habit change, and it is the hardest part of any implementation.</li>
<li><b>Run ABC analysis.</b> Find the 20% that carries the value.</li>
<li><b>Set reorder points on the A items properly.</b> Default the rest. Perfection on the long tail is not worth the hours.</li>
<li><b>Start cycle counting.</b> A items monthly, C items annually.</li>
<li><b>Review quarterly.</b> Demand drifts, suppliers change, and a policy set two years ago describes a business that no longer exists.</li>
</ol>
<div class="callout"><p><b>The order matters.</b> Almost every failed inventory implementation skipped straight to step 5, setting sophisticated reorder points on top of a catalogue nobody trusted and movements nobody recorded.</p></div>`,
  faqs: [
    { q: 'What is inventory management in simple terms?', a: 'Knowing what stock you hold, what it is worth, where it is, and deciding when to order more and how much. The record-keeping exists to support those decisions — an accurate count nobody acts on has no value.' },
    { q: 'What is the difference between inventory management and inventory control?', a: 'Inventory control is the narrower activity of maintaining accurate counts and securing stock. Inventory management includes that, plus the decisions about how much to hold, when to reorder and what to stop carrying.' },
    { q: 'What are the four types of inventory?', a: 'Raw materials, work in progress, finished goods, and MRO supplies. Safety stock and in-transit stock are usually treated as further categories because they behave differently for planning.' },
    { q: 'How much does holding inventory cost?', a: 'Typically 20–30% of the unit value per year, covering capital tied up, storage, insurance, shrinkage and obsolescence. At 25%, ₹10 lakh of stock costs about ₹2.5 lakh a year to hold.' },
    { q: 'Do small businesses need inventory management software?', a: 'Not always. A spreadsheet is adequate for a single person with a small, stable catalogue. It stops being adequate as soon as two people need to update stock at once, or you need to know who changed something and why.' },
  ],
  links: [
    { href: '/blog/reorder-point-formula', label: 'The reorder point formula, explained' },
    { href: '/blog/abc-analysis-inventory', label: 'ABC analysis: where to spend your effort' },
    { href: '/compare/inventory-management-software-vs-excel', label: 'Inventory software vs. Excel' },
    { href: '/tools', label: 'Free inventory calculators' },
  ],
});

const rop = guide({
  slug: 'reorder-point-formula',
  title: 'The Reorder Point Formula, Explained With Examples',
  h1: 'The reorder point formula',
  description:
    'How to calculate a reorder point: lead time demand plus safety stock, why the supplier variability term matters, a worked example, and the three mistakes that break it.',
  published: '2026-03-18',
  modified: '2026-09-08',
  lead: 'A reorder point is the stock level at which you must place the next order to avoid running out before it arrives. The formula is short. Getting the inputs right is the entire job.',
  contents: [
    { id: 'formula', label: 'The formula' },
    { id: 'lead-time', label: 'Lead time demand' },
    { id: 'buffer', label: 'The safety stock term' },
    { id: 'worked', label: 'A worked example' },
    { id: 'simple', label: 'The simple version' },
    { id: 'mistakes', label: 'Three ways it goes wrong' },
    { id: 'apply', label: 'Applying it across a catalogue' },
  ],
  sections: `
<h2 id="formula">The formula</h2>
<div class="formula">Reorder point = lead time demand + safety stock
                = (d &times; L) + Z &times; &radic;( L &times; &sigma;<sub>d</sub>&sup2; + d&sup2; &times; &sigma;<sub>L</sub>&sup2; )</div>
<p>Two parts, and they answer two different questions. Lead time demand is what you will sell while you wait. Safety stock is what covers you when either the selling or the waiting goes worse than average.</p>
<p><a href="/tools/reorder-point-calculator">The calculator is here</a> if you want the number now; the rest of this page is why it is that number.</p>

<h2 id="lead-time">Lead time demand: the part everyone gets nearly right</h2>
<p>Average daily demand times lead time in days. Sell 40 a day, supplier takes 7 days, you will sell 280 while you wait. If you order at 280 you arrive at zero exactly as the delivery lands — assuming nothing varies, which is the assumption safety stock exists to remove.</p>
<p>The word doing the damage in that paragraph is <b>lead time</b>. It is not what the supplier quotes. It is the elapsed time from you deciding to order to the stock being available to sell, and it includes:</p>
<ul>
<li>The time before the order actually goes out — approval, batching it with other orders, waiting for Monday.</li>
<li>The supplier's real fulfilment time, not their promise.</li>
<li>Transit.</li>
<li>Receiving, checking and put-away at your end.</li>
</ul>
<p>A "3-day" supplier is routinely a 6-day lead time once those are counted. Businesses that measure the whole span rather than the middle of it fix most of their stockout problem without changing anything else.</p>

<h2 id="buffer">The safety stock term, and why it has two parts</h2>
<div class="formula">safety stock = Z &times; &radic;( L &times; &sigma;<sub>d</sub>&sup2; + d&sup2; &times; &sigma;<sub>L</sub>&sup2; )</div>
<p>Under the square root are two independent risks:</p>
<ul>
<li><code>L &times; &sigma;<sub>d</sub>&sup2;</code> — demand bouncing around its average, accumulated over L days. Variances add over time, which is why it is L and not L&sup2;.</li>
<li><code>d&sup2; &times; &sigma;<sub>L</sub>&sup2;</code> — the supplier being late while you keep selling at rate d. Each extra day of lateness costs you d units, so the demand rate is squared here.</li>
</ul>
<p>They are combined as variances and then square-rooted because they are independent. Adding the two standard deviations directly would size you for both going maximally wrong at once, which is real but rare, and paying for it permanently is poor value.</p>
<p>Z converts your chosen <a href="/tools/safety-stock-calculator">service level</a> into a multiplier: 1.65 for 95%, 2.33 for 99%.</p>

<h2 id="worked">A worked example</h2>
<p>A distributor sells a fast-moving line:</p>
<ul>
<li>d = 40 units/day, &sigma;<sub>d</sub> = 12 units/day</li>
<li>L = 7 days, &sigma;<sub>L</sub> = 1.5 days</li>
<li>Target service level 95%, so Z = 1.65</li>
</ul>
<div class="formula">Lead time demand = 40 &times; 7                    = 280
Demand variance  = 7 &times; 12&sup2;                   = 1,008
Supply variance  = 40&sup2; &times; 1.5&sup2;                = 3,600
&sigma;                = &radic;(1,008 + 3,600)         = 67.9
Safety stock     = 1.65 &times; 67.9               = 112
Reorder point    = 280 + 112                  = 392 units</div>
<p>Now read the diagnosis rather than just the answer. <b>78% of the variance comes from the supplier, not from demand.</b> This business does not have a forecasting problem; it has a supplier reliability problem. Halving &sigma;<sub>L</sub> to 0.75 days drops the buffer from 112 to about 66 units — a 41% cut in buffer stock from one conversation with the supplier, with no change to service level.</p>
<div class="callout"><p>This variance split is the most useful thing the formula produces, and it is invisible if you use a simplified version. It tells you whether to invest in forecasting or in supply reliability.</p></div>

<h2 id="simple">The simple version, and when it is fine</h2>
<div class="formula">Reorder point = (d &times; L) + (d &times; buffer days)</div>
<p>Lead time demand plus a few days of cover. It is crude, but it is enormously better than a flat global threshold and it takes seconds per product. Use it for your C-class items — the long tail where the full calculation is not worth the effort — and do the proper version for A-class items where the money is. <a href="/blog/abc-analysis-inventory">ABC analysis</a> tells you which is which.</p>

<h2 id="mistakes">Three ways a correct formula still fails</h2>
<h3>1. Using the quoted lead time</h3>
<p>Covered above, and it is the big one. Measure your own, end to end, including the time before the order leaves and the time after it arrives.</p>
<h3>2. One reorder point for everything</h3>
<p>The formula is per-product because d, L, &sigma;<sub>d</sub> and &sigma;<sub>L</sub> are all per-product. A global "alert under 10" is wrong for essentially every line, and being wrong in both directions simultaneously means people learn to ignore the alert entirely — which is worse than having no alert at all.</p>
<h3>3. Never recalculating</h3>
<p>Demand drifts, suppliers change, seasons turn. A reorder point set eighteen months ago describes a business that no longer exists. Quarterly is a reasonable cadence; immediately is the right answer after a supplier change.</p>

<h2 id="apply">Applying it across a catalogue without losing a week</h2>
<p>Nobody calculates 2,000 reorder points by hand, and any process that requires it will be abandoned. The practical route:</p>
<ol>
<li>Run <a href="/blog/abc-analysis-inventory">ABC analysis</a> and identify the A items — usually about 20% of lines.</li>
<li>Calculate reorder points properly for those, at a 98–99% service level.</li>
<li>For B items, use the simple version at 95%.</li>
<li>For C items, apply a flat days-of-cover rule. Being slightly wrong on a slow mover costs very little.</li>
<li>Load them in bulk — export the catalogue to a spreadsheet, calculate in a column, import back matching on SKU.</li>
</ol>
<p>Then the number needs to actually do something. In <a href="/features/low-stock-alerts-and-reorder-points">SmartShelfKart</a> the reorder point is the product's low-stock threshold, checked against live stock, so crossing it puts the item on the Low Stock list and into the reorder suggestions rather than waiting for someone to notice.</p>`,
  faqs: [
    { q: 'What is the reorder point formula?', a: 'Reorder point = (average daily demand × lead time) + safety stock, where safety stock is Z × √(L × σd² + d² × σL²). The first term covers what you will sell while waiting; the second covers demand and supplier variability.' },
    { q: 'What lead time should I use?', a: 'Your own measured lead time, from deciding to order through to stock being available to sell — including approval delays before the order goes out and receiving time after it arrives. Supplier quotes routinely understate this by several days.' },
    { q: 'Do I need the full formula, or is the simple one enough?', a: 'Use the full version for A-class items where the money is, and the simple version — lead time demand plus a few days of cover — for the long tail. The full version also tells you whether demand or supply variability is the real problem, which the simple one cannot.' },
    { q: 'How often should reorder points be recalculated?', a: 'Quarterly for most items, and immediately after any supplier change or a visible shift in a product\'s demand pattern.' },
    { q: 'Can the reorder point be lower than the safety stock?', a: 'No. The reorder point always includes safety stock plus lead time demand, so it is at least as large. If you compute otherwise, one of the inputs is wrong.' },
  ],
  links: [
    { href: '/tools/reorder-point-calculator', label: 'Reorder point calculator' },
    { href: '/blog/safety-stock-formula', label: 'The safety stock formula, explained' },
    { href: '/blog/abc-analysis-inventory', label: 'ABC analysis' },
    { href: '/features/low-stock-alerts-and-reorder-points', label: 'Low-stock alerts in SmartShelfKart' },
  ],
});

const ss = guide({
  slug: 'safety-stock-formula',
  title: 'The Safety Stock Formula and Service Levels Explained',
  h1: 'The safety stock formula',
  description:
    'Where the safety stock formula comes from, what the Z-score means, how to choose a service level, and why a flat two-weeks-of-cover rule fails in both directions.',
  published: '2026-04-02',
  modified: '2026-09-08',
  lead: 'Safety stock is not a comfort blanket. It is a priced decision about how often you are willing to run out — and the formula tells you exactly what that decision costs.',
  contents: [
    { id: 'why', label: 'Why any buffer at all' },
    { id: 'formula', label: 'The formula' },
    { id: 'z', label: 'Service level and the Z-score' },
    { id: 'split', label: 'Reading the variance split' },
    { id: 'flat', label: 'Why flat cover rules fail' },
    { id: 'choosing', label: 'Choosing service levels per class' },
    { id: 'practice', label: 'In practice' },
  ],
  sections: `
<h2 id="why">Why any buffer at all</h2>
<p>Order exactly lead time demand and you will stock out roughly half the time. Not occasionally — half the time. Demand exceeds its own average in about half of all periods, by definition. Safety stock is what buys you down from a 50% stockout rate to something a business can live with.</p>
<p>How far down is a decision, and it has a price. That is the whole content of the formula.</p>

<h2 id="formula">The formula</h2>
<div class="formula">Safety stock = Z &times; &radic;( L &times; &sigma;<sub>d</sub>&sup2; + d&sup2; &times; &sigma;<sub>L</sub>&sup2; )

Z    service level factor
L    average lead time, days
&sigma;<sub>d</sub>   standard deviation of daily demand
d    average daily demand
&sigma;<sub>L</sub>   standard deviation of lead time, days</div>
<p>The square root of a sum of two variances. That construction encodes an assumption worth stating plainly: demand risk and supply risk are treated as independent. Your supplier being late is not correlated with your customers buying more. That is usually true, and where it is not — a market-wide shortage hits supply and demand together — the formula will understate the buffer you need.</p>

<h2 id="z">Service level and the Z-score</h2>
<p>Z is the number of standard deviations of cover you are buying, drawn from the normal distribution:</p>
${table(
  ['Service level', 'Z', 'Meaning', 'Relative buffer'],
  [
    ['50%', '0.00', 'No buffer. Stock out half the time', '0'],
    ['80%', '0.84', 'Stock out 1 cycle in 5', '0.51&times;'],
    ['90%', '1.28', 'Stock out 1 cycle in 10', '0.78&times;'],
    ['95%', '1.65', 'Stock out 1 cycle in 20', '1.00&times;'],
    ['98%', '2.05', 'Stock out 1 cycle in 50', '1.25&times;'],
    ['99%', '2.33', 'Stock out 1 cycle in 100', '1.41&times;'],
    ['99.9%', '3.09', 'Stock out 1 cycle in 1,000', '1.88&times;'],
  ]
)}
<p>The right-hand column is the one to read before choosing. Moving from 95% to 99.9% removes about one stockout in twenty cycles and costs 88% more buffer — permanently, on every unit, forever. Note also that the relationship is not linear: the first 45 percentage points of service cost you 1.0&times;, and the last 4.9 cost you another 0.88&times;.</p>

<h2 id="split">Reading the variance split</h2>
<p>The two terms under the root are separately meaningful, and comparing them is the most actionable output of the whole exercise.</p>
<div class="formula">demand risk = L &times; &sigma;<sub>d</sub>&sup2;
supply risk = d&sup2; &times; &sigma;<sub>L</sub>&sup2;</div>
<p>If <b>supply risk dominates</b>, your buffer exists to insure against your supplier. The fix is commercial, not analytical: tighten the lead time, agree a delivery window, or add a second source. Cutting &sigma;<sub>L</sub> in half typically cuts the total buffer by a third or more.</p>
<p>If <b>demand risk dominates</b>, the buffer is the price of genuinely unpredictable customers. Better forecasting, promotion planning or shorter lead times will help; supplier conversations will not.</p>
<p><a href="/tools/safety-stock-calculator">The calculator</a> prints this split as a percentage, because most businesses guess it wrong — and usually guess demand when the answer is supply.</p>

<h2 id="flat">Why "two weeks of cover" fails twice</h2>
<p>The flat rule is popular because it needs no data. It is also wrong in both directions simultaneously:</p>
<ul>
<li>On a <b>steady, reliably supplied product</b>, two weeks is far more than the risk warrants. That is cash on a shelf earning nothing, incurring 20–30% a year in carrying cost.</li>
<li>On a <b>volatile product with an unreliable supplier</b>, two weeks is not enough. You stock out anyway, having paid for a buffer that did not cover the actual risk.</li>
</ul>
<p>So you over-invest where you are safe and under-invest where you are exposed. A flat rule is not a conservative choice; it is an uninformed one, and it costs money at both ends.</p>

<h2 id="choosing">Choosing service levels per class</h2>
<p>Service level should not be uniform, because the cost of a stockout is not uniform. A reasonable policy:</p>
${table(
  ['Class', 'Typical service level', 'Reasoning'],
  [
    ['A — high value or critical', '98–99%', 'A stockout loses the customer, not just the sale'],
    ['B — ordinary lines', '95%', 'Standard balance of cost and risk'],
    ['C — slow tail', '85–90%', 'Carrying cost outweighs the occasional wait'],
    ['Perishable', '90–95%', 'Higher buffers become write-offs, not insurance'],
    ['Single-source, long lead time', '98%+', 'Recovery from a stockout is measured in weeks'],
  ]
)}
<p><a href="/blog/abc-analysis-inventory">ABC analysis</a> is how you assign the classes. Doing this well is typically worth more than any refinement of the formula itself.</p>

<h2 id="practice">In practice</h2>
<ol>
<li>Pull daily sales for a representative period and take <code>STDEV.P</code> for &sigma;<sub>d</sub>.</li>
<li>Pull your recorded delivery times and take <code>STDEV.P</code> for &sigma;<sub>L</sub>. If you have never recorded them, start now — this single dataset is worth more than most forecasting effort.</li>
<li>Assign a service level by ABC class.</li>
<li>Compute, add lead time demand to get the <a href="/blog/reorder-point-formula">reorder point</a>, and load it as each product's threshold.</li>
<li>Review quarterly, and immediately on a supplier change.</li>
</ol>
<div class="callout"><p><b>If you record nothing else, record delivery dates.</b> Almost every business can estimate demand variability from sales history it already has. Almost none can estimate lead-time variability, because nobody wrote down when deliveries actually arrived — and that is usually the larger term.</p></div>`,
  faqs: [
    { q: 'What is the safety stock formula?', a: 'Safety stock = Z × √(L × σd² + d² × σL²). Z is the service-level factor, L is average lead time, σd is the standard deviation of daily demand, d is average daily demand and σL is the standard deviation of lead time.' },
    { q: 'What happens if I hold no safety stock?', a: 'You stock out roughly half the time, because demand exceeds its own average in about half of all periods. Ordering exactly lead time demand is a coin flip on every cycle.' },
    { q: 'What service level should I target?', a: '95% is a reasonable default. Use 98–99% for high-value or customer-critical items and 85–90% for the slow tail. The buffer cost rises steeply above 98%, so the top end should be a deliberate choice.' },
    { q: 'Is safety stock the same as a reorder point?', a: 'No. Safety stock is the buffer; the reorder point is lead time demand plus that buffer. The reorder point is the number a system can watch, so it is the one you set on the product.' },
    { q: 'Which matters more — demand variability or lead-time variability?', a: 'It varies by product, and the calculation tells you. In many small businesses lead-time variability dominates, which means the fix is a supplier conversation rather than a forecasting project.' },
  ],
  links: [
    { href: '/tools/safety-stock-calculator', label: 'Safety stock calculator' },
    { href: '/blog/reorder-point-formula', label: 'The reorder point formula' },
    { href: '/blog/abc-analysis-inventory', label: 'ABC analysis' },
    { href: '/tools', label: 'All free calculators' },
  ],
});

export default [whatIs, rop, ss];
