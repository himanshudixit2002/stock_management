import { guide } from './blog.mjs';
import { table } from '../blocks.mjs';

export const abc = guide({
  slug: 'abc-analysis-inventory',
  title: 'ABC Analysis in Inventory Management — Method and Example',
  h1: 'ABC analysis: putting your effort where the money is',
  description:
    'How to run an ABC analysis on an inventory catalogue: the method step by step, a worked example, where the 80/20 split really lands, and what to do differently for each class.',
  published: '2026-04-21',
  modified: '2026-09-08',
  lead: 'Most catalogues have a small number of lines carrying most of the value and a long tail carrying almost none. ABC analysis finds the split so you stop treating both the same way.',
  contents: [
    { id: 'idea', label: 'The idea' },
    { id: 'method', label: 'The method, step by step' },
    { id: 'worked', label: 'A worked example' },
    { id: 'policy', label: 'What to do differently per class' },
    { id: 'variants', label: 'When value alone is the wrong axis' },
    { id: 'pitfalls', label: 'Pitfalls' },
  ],
  sections: `
<h2 id="idea">The idea</h2>
<p>Managing 2,000 products identically is impossible and, more importantly, pointless. Effort spent perfecting the reorder point on a line that sells four units a year is effort not spent on the line that turns over ₹40 lakh.</p>
<p>ABC analysis sorts the catalogue by annual consumption value — units sold per year times unit cost — and splits it into three classes. The usual shape:</p>
${table(
  ['Class', 'Share of lines', 'Share of value', 'How to treat it'],
  [
    ['A', '~10–20%', '~70–80%', 'Tight control, frequent counts, calculated reorder points, high service level'],
    ['B', '~20–30%', '~15–20%', 'Moderate control, quarterly counts, simple reorder rules'],
    ['C', '~50–70%', '~5–10%', 'Loose control, annual counts, flat cover rules, larger order quantities'],
  ]
)}
<p>The exact percentages do not matter and are not a law of nature. What matters is that the distribution is steep, and almost every catalogue's is.</p>

<h2 id="method">The method, step by step</h2>
<ol>
<li><b>Pull annual usage per product.</b> Units sold or consumed over twelve months. A shorter period works if you scale it, but avoid periods dominated by one season.</li>
<li><b>Multiply by unit cost.</b> This gives annual consumption value. Use <em>cost</em>, not selling price — you are measuring capital at risk, not revenue.</li>
<li><b>Sort descending by that value.</b></li>
<li><b>Add a running cumulative percentage of total value.</b></li>
<li><b>Draw the lines.</b> Everything up to ~80% cumulative is A; from there to ~95% is B; the remainder is C.</li>
<li><b>Sanity-check the boundaries.</b> If A comes out at 45% of your lines, either your catalogue is unusually flat or the usage data is wrong.</li>
</ol>
<div class="callout"><p><b>Do it in a spreadsheet the first time.</b> Export the catalogue with annual usage and cost, sort, and add one cumulative column. It takes about twenty minutes and you will learn more about your business in those twenty minutes than in most quarterly reviews.</p></div>

<h2 id="worked">A worked example</h2>
<p>A distributor with 500 SKUs and ₹4 crore of annual consumption value:</p>
${table(
  ['', 'Lines', '% of lines', 'Value', '% of value', 'Cumulative'],
  [
    ['A', '62', '12.4%', '₹3.08 cr', '77%', '77%'],
    ['B', '119', '23.8%', '₹0.72 cr', '18%', '95%'],
    ['C', '319', '63.8%', '₹0.20 cr', '5%', '100%'],
  ]
)}
<p>Sixty-two products carry three quarters of the money. The consequences are immediate and concrete:</p>
<ul>
<li>Counting those 62 monthly is about three hours of work. Counting all 500 monthly is a fortnight.</li>
<li>Calculating <a href="/blog/reorder-point-formula">proper reorder points</a> for 62 lines is an afternoon. For 500 it never happens.</li>
<li>A 10% cut in A-class stock releases about ₹30 lakh. The same 10% cut across all C items releases ₹2 lakh.</li>
</ul>
<p>Every one of those is a decision you cannot even see without the split.</p>

<h2 id="policy">What to do differently per class</h2>
<h3>A items</h3>
<ul>
<li>Full <a href="/tools/reorder-point-calculator">reorder point calculation</a> at a 98–99% service level.</li>
<li>Cycle count monthly.</li>
<li>Order more frequently in smaller quantities — the carrying cost is worth avoiding.</li>
<li>Watch supplier lead-time variability closely; this is where reducing it pays most.</li>
<li>Review demand at least quarterly.</li>
</ul>
<h3>B items</h3>
<ul>
<li>Simple reorder point: lead time demand plus a few days of cover, at 95%.</li>
<li>Cycle count quarterly.</li>
<li>Standard <a href="/tools/economic-order-quantity-calculator">EOQ</a> order quantities.</li>
</ul>
<h3>C items</h3>
<ul>
<li>Flat days-of-cover rule. Being wrong here is cheap.</li>
<li>Count annually.</li>
<li>Order in larger quantities less often — ordering cost dominates holding cost at this value.</li>
<li><b>Review for deletion.</b> The most valuable thing about identifying C items is deciding which of them you should stop carrying at all. Each one occupies shelf space, catalogue attention and a small amount of working capital.</li>
</ul>

<h2 id="variants">When value alone is the wrong axis</h2>
<p>Pure consumption value misses things that will hurt you:</p>
<ul>
<li><b>Criticality.</b> A ₹200 gasket that halts a production line is not a C item in any meaningful sense. Many businesses run a second axis for criticality and promote items regardless of value.</li>
<li><b>XYZ analysis.</b> Classifies by demand <em>variability</em> rather than value. An AZ item — high value, wildly unpredictable — is the hardest thing in any catalogue and deserves individual attention.</li>
<li><b>Lead time.</b> A cheap item with a fourteen-week lead time needs planning a C classification will not give it.</li>
<li><b>Perishability.</b> Dated stock has a deadline that value ranking ignores entirely.</li>
</ul>
<p>The practical approach is to run ABC on value, then manually promote the handful of items that are critical, long-lead or perishable. That list is usually short and every business already knows most of it.</p>

<h2 id="pitfalls">Pitfalls</h2>
<ul>
<li><b>Using selling price instead of cost.</b> Inflates high-margin lines and misrepresents capital at risk.</li>
<li><b>Using stock value instead of consumption value.</b> A product with ₹5 lakh sitting on the shelf and no sales is not an A item — it is a dead-stock problem, and the ageing report is the right place to see it.</li>
<li><b>Running it once and filing it.</b> Classes drift. Re-run every six to twelve months.</li>
<li><b>Treating the boundaries as sacred.</b> 80/95 are conventions. If your data has an obvious cliff, put the line at the cliff.</li>
<li><b>Forgetting new products.</b> A line launched two months ago has no annual usage and will land in C. Exclude and manage new lines separately until they have history.</li>
</ul>
<p>Once the classes exist, they should change how the system behaves — different service levels, different count frequencies, different order sizes. An ABC analysis that produces a spreadsheet nobody acts on has produced nothing. In <a href="/features/inventory-reports-and-analytics">SmartShelfKart</a> the ABC report runs off the same transaction record as everything else, so it stays current instead of being a one-off exercise.</p>`,
  faqs: [
    { q: 'What is ABC analysis in inventory management?', a: 'A method of classifying stock by annual consumption value — units used per year times unit cost — into three classes, so that high-value items receive tight control and the low-value tail receives simple rules.' },
    { q: 'What percentage should be A, B and C?', a: 'Conventionally A is the lines making up the first ~80% of cumulative value (often 10–20% of items), B the next ~15% and C the remainder. The exact boundaries are conventions, not rules — put them where your data shows a cliff.' },
    { q: 'Should I use cost or selling price?', a: 'Cost. ABC measures capital at risk, and inventory is carried at cost. Using selling price inflates high-margin lines and distorts the ranking.' },
    { q: 'How often should ABC analysis be re-run?', a: 'Every six to twelve months for most businesses. Classes drift as demand and prices change, and a classification from two years ago will misdirect your counting and ordering effort.' },
    { q: 'What is XYZ analysis?', a: 'A companion method that classifies items by demand variability rather than value. Combining them gives a nine-box grid; AZ items — high value and highly unpredictable — are the ones that most repay individual attention.' },
  ],
  links: [
    { href: '/blog/reorder-point-formula', label: 'The reorder point formula' },
    { href: '/blog/inventory-turnover-ratio', label: 'The inventory turnover ratio' },
    { href: '/blog/stock-audit-cycle-counting', label: 'Stock audits and cycle counting' },
    { href: '/features/inventory-reports-and-analytics', label: 'ABC analysis in SmartShelfKart' },
  ],
});

export const turnover = guide({
  slug: 'inventory-turnover-ratio',
  title: 'Inventory Turnover Ratio — Formula, Benchmarks, and Meaning',
  h1: 'The inventory turnover ratio',
  description:
    'The inventory turnover formula, why you must use cost of goods sold rather than revenue, benchmarks by sector, and why a blended company-wide figure hides the problem.',
  published: '2026-05-12',
  modified: '2026-09-08',
  lead: 'Turnover measures how many times a year your stock sells through. It is the closest thing inventory has to a single headline number — which is exactly why it is so often misread.',
  contents: [
    { id: 'formula', label: 'The formula' },
    { id: 'cogs', label: 'Cost, not revenue' },
    { id: 'days', label: 'Days of supply' },
    { id: 'benchmarks', label: 'Benchmarks by sector' },
    { id: 'higher', label: 'Higher is not always better' },
    { id: 'blend', label: 'The blended-average trap' },
    { id: 'improve', label: 'How to improve it honestly' },
  ],
  sections: `
<h2 id="formula">The formula</h2>
<div class="formula">Inventory turnover = cost of goods sold &divide; average inventory
Average inventory  = (opening + closing) &divide; 2
Days of supply     = 365 &divide; turnover</div>
<p>Turnover of 6 means you sold through your average stockholding six times over the year — about 61 days of stock on hand. <a href="/tools/inventory-turnover-calculator">The calculator is here.</a></p>
<p>Averaging opening and closing is a crude smoothing. If your stock swings seasonally, average the twelve month-end figures instead; a business whose year-end deliberately lands at a low point will otherwise flatter itself considerably.</p>

<h2 id="cogs">Cost, not revenue — the error that makes everyone look good</h2>
<p>The most common mistake is dividing sales by average inventory. Inventory is carried at cost. Putting revenue on top inflates the ratio by your entire gross margin.</p>
<div class="formula">Revenue ₹1.0 cr, margin 40% &rarr; COGS ₹60 lakh
Average inventory ₹10 lakh

Correct:   60 &divide; 10 = 6.0&times;   (61 days)
Incorrect: 100 &divide; 10 = 10.0&times;  (37 days)</div>
<p>That business would believe it holds 37 days of stock when it holds 61. If you are comparing yourself with a published benchmark, make sure the benchmark uses the same basis — many trade publications quietly do not.</p>

<h2 id="days">Days of supply is the number to quote</h2>
<p>"We turn 6 times" requires mental arithmetic to be meaningful. "We hold 61 days of stock" is immediately legible to anyone in the room, including people who do not think about inventory for a living. It also maps directly onto the operational questions — is 61 days reasonable given a 7-day lead time? — in a way the ratio does not.</p>
<p>Use turnover for comparisons and trends; use days of supply for decisions and conversations.</p>

<h2 id="benchmarks">Benchmarks by sector</h2>
${table(
  ['Sector', 'Typical annual turnover', 'Days of supply'],
  [
    ['Grocery and fresh food', '12–25&times;', '15–30'],
    ['Restaurants and food service', '20–40&times;', '9–18'],
    ['General retail', '4–8&times;', '45–90'],
    ['Apparel and fashion', '4–8&times;', '45–90'],
    ['Consumer electronics', '6–10&times;', '35–60'],
    ['Wholesale and distribution', '5–10&times;', '35–75'],
    ['Pharmacy', '8–14&times;', '25–45'],
    ['Auto and industrial spares', '2–4&times;', '90–180'],
    ['Building materials', '4–6&times;', '60–90'],
    ['Jewellery and luxury', '1–2&times;', '180–365'],
  ]
)}
<p>These are broad ranges, not targets. Turnover is a property of what you sell far more than of how well you manage it. A spares distributor at 3&times; may be excellent; a grocer at 3&times; is throwing away perishable stock every week. Compare against your own history first, your sector second, and never against an unrelated industry.</p>

<h2 id="higher">Higher is not always better</h2>
<p>Rising turnover generally means less capital tied up and less obsolescence risk. Beyond a point it means you are running thin, and the costs of thin do not appear anywhere in the turnover calculation:</p>
<ul>
<li>Stockouts and lost sales — the customer who goes elsewhere is invisible in your numbers.</li>
<li>Expedited freight to cover the gaps.</li>
<li>More frequent ordering, so higher ordering cost.</li>
<li>Loss of quantity discounts.</li>
<li>Staff time spent firefighting.</li>
</ul>
<p>This is why turnover must be read next to a service-level or stockout measure. Turnover taken alone can be "improved" by simply refusing to hold stock, which is not an improvement in anything but the ratio.</p>

<h2 id="blend">The blended-average trap</h2>
<p>A single company-wide figure conceals the thing you most need to see. Consider two businesses, both at 6&times;:</p>
${table(
  ['', 'Business A', 'Business B'],
  [
    ['Fast lines', '6&times; across the board', '20&times;'],
    ['Slow lines', 'none', '0.4&times;'],
    ['Blended', '6&times;', '6&times;'],
    ['Reality', 'Uniformly healthy', 'Half the capital is in dead stock'],
  ]
)}
<p>Business B has a serious problem that the headline number hides completely. Always calculate turnover by category and read it beside an <a href="/features/inventory-reports-and-analytics">ageing report</a>, which shows what has not moved at all. <a href="/blog/abc-analysis-inventory">ABC analysis</a> tells you where the value sits; turnover tells you how fast it is cycling; ageing tells you what is not cycling at all. You need all three.</p>

<h2 id="improve">How to improve it honestly</h2>
<ol>
<li><b>Deal with dead stock deliberately.</b> Discount it, bundle it, return it, or write it off. It is already a loss — carrying it only delays recognising it while consuming space and capital.</li>
<li><b>Shorten lead times.</b> This is the highest-quality lever, because less <a href="/tools/safety-stock-calculator">safety stock</a> is needed for the same service level. Turnover rises with no increase in risk.</li>
<li><b>Order smaller and more often</b> where <a href="/tools/economic-order-quantity-calculator">EOQ</a> supports it, particularly on A items.</li>
<li><b>Prune the tail.</b> Lines selling twice a year rarely earn their working capital or their shelf space.</li>
<li><b>Set reorder points properly</b> so you are not carrying arbitrary buffers on products that never needed them.</li>
</ol>
<div class="callout callout--warn"><p><b>What not to do:</b> improve the ratio by cutting stock on your best-selling lines. It works arithmetically and costs you the sales that pay for everything else. If turnover improves while revenue falls, you have not become efficient — you have become smaller.</p></div>`,
  faqs: [
    { q: 'What is the inventory turnover formula?', a: 'Cost of goods sold divided by average inventory, where average inventory is the mean of opening and closing stock at cost. Days of supply is 365 divided by the turnover ratio.' },
    { q: 'What is a good inventory turnover ratio?', a: 'It depends heavily on sector: grocery often runs 12–25× a year, general retail 4–8×, wholesale 5–10×, and spares or jewellery 1–4×. Compare against your own history and your sector rather than a universal target.' },
    { q: 'Why must I use COGS rather than sales?', a: 'Inventory is carried at cost, so dividing revenue by inventory inflates the ratio by your entire gross margin. A business with a 40% margin would report roughly 1.7× its true turnover.' },
    { q: 'Is a very high inventory turnover bad?', a: 'It can be. Beyond a point it means running thin, producing stockouts, expedited freight and lost sales — none of which appear in the ratio itself. Always read turnover next to a service-level measure.' },
    { q: 'Should I calculate turnover per product?', a: 'Per category at minimum. A single blended figure can hide a business where fast lines turn 20× and half the capital sits in stock turning 0.4×.' },
  ],
  links: [
    { href: '/tools/inventory-turnover-calculator', label: 'Inventory turnover calculator' },
    { href: '/blog/abc-analysis-inventory', label: 'ABC analysis' },
    { href: '/tools/economic-order-quantity-calculator', label: 'EOQ calculator' },
    { href: '/features/inventory-reports-and-analytics', label: 'Reports in SmartShelfKart' },
  ],
});

export const smallBiz = guide({
  slug: 'inventory-management-for-small-business',
  title: 'Inventory Management for Small Business — A Starting Guide',
  h1: 'Inventory management for a small business',
  description:
    'A practical starting guide for small businesses: what to fix first, how to run a first stock count, which numbers to set, and the mistakes that make rollouts fail.',
  published: '2026-06-03',
  modified: '2026-09-08',
  lead: 'Most small-business inventory advice is written for warehouses with a planning team. This is written for a business where the person setting up the system is also the person serving customers.',
  contents: [
    { id: 'order', label: 'Do these in order' },
    { id: 'catalogue', label: 'Step 1: fix the catalogue' },
    { id: 'count', label: 'Step 2: one honest count' },
    { id: 'record', label: 'Step 3: record movements as they happen' },
    { id: 'numbers', label: 'Step 4: set the numbers that matter' },
    { id: 'roles', label: 'Multiple people, one truth' },
    { id: 'fail', label: 'Why implementations fail' },
  ],
  sections: `
<h2 id="order">Do these in order</h2>
<p>The sequence matters more than any individual step. Nearly every failed rollout skipped ahead to the interesting parts on top of a foundation that was not there.</p>
<div class="formula">1. Clean catalogue      &rarr; nothing works without this
2. One honest count     &rarr; every later number builds on it
3. Record movements     &rarr; the habit change, and the hard part
4. Set reorder points   &rarr; only now is there data to set them from
5. Count continuously   &rarr; keeps it true
6. Review quarterly     &rarr; keeps it relevant</div>

<h2 id="catalogue">Step 1: fix the catalogue</h2>
<p>One row per genuinely distinct sellable item. If a customer can order the 500ml and the 1-litre separately, they are two SKUs. If you sell the same thing under two names, that is one SKU with one name.</p>
<ul>
<li><b>Pick a SKU format and stick to it.</b> Short, meaningful, and never reused. <code>SHM-500-LAV</code> beats <code>1042</code> for a human and works just as well for a machine.</li>
<li><b>Record the barcode separately from the SKU.</b> The barcode belongs to the manufacturer; the SKU is yours. Keeping both lets you bulk-update from either your data or a supplier's.</li>
<li><b>Categorise once, properly.</b> Every report you will ever want groups by category. A flat catalogue of 800 uncategorised products cannot be analysed.</li>
<li><b>Record cost as well as price.</b> Without cost there is no margin report, and margin is the reason to do any of this.</li>
<li><b>Delete what you no longer sell.</b> Or archive it. Carrying discontinued lines in the active catalogue slows every screen and every count.</li>
</ul>
<div class="callout"><p>This is unglamorous work and it is where the value is. A tidy catalogue with mediocre processes beats a sophisticated system on a catalogue nobody trusts.</p></div>

<h2 id="count">Step 2: one honest count</h2>
<p>Everything downstream inherits this number. Some rules:</p>
<ul>
<li><b>Count what is there, not what should be there.</b> The temptation to adjust toward the book figure is overwhelming and completely destructive.</li>
<li><b>Close, or freeze movement, while you count.</b> Counting a moving shelf produces a number that was never true.</li>
<li><b>Two people on high-value items.</b> One counts, one records.</li>
<li><b>Write down the variances.</b> The gap between book and physical is your first real measurement of shrinkage, and you will want the baseline later.</li>
<li><b>Do not investigate every discrepancy.</b> Investigate the expensive ones. Absorb the rest and move on.</li>
</ul>

<h2 id="record">Step 3: record movements as they happen</h2>
<p>This is the whole ball game, and it is a habit change rather than a software problem. Stock moves at the counter, at the loading bay, in the van — not at a desk at 6pm.</p>
<ul>
<li><b>Make recording take seconds.</b> If it takes a minute, it will not happen when the shop is busy, and busy is exactly when the movements matter.</li>
<li><b>Put it on the phone.</b> The person who knows what moved is holding a phone, not sitting at the office desktop.</li>
<li><b>Record reasons, not just quantities.</b> "Minus 3" is useless in a month. "Minus 3, damaged in transit" is a supplier conversation.</li>
<li><b>Never let anyone overtype a quantity.</b> Corrections should be adjustments with reasons, so the history survives. This single rule is what separates a stock system from a spreadsheet.</li>
</ul>
<p>Expect this step to take a few weeks to bed in, and expect the first month's data to be imperfect. That is normal and it is still worth far more than no data.</p>

<h2 id="numbers">Step 4: set the numbers that matter</h2>
<p>Only now do you have enough history to set anything sensibly.</p>
<ol>
<li>Run <a href="/blog/abc-analysis-inventory">ABC analysis</a>. Twenty minutes in a spreadsheet.</li>
<li>For A items, calculate a proper <a href="/tools/reorder-point-calculator">reorder point</a> at a 98% service level.</li>
<li>For everything else, use lead time demand plus a few days of cover.</li>
<li>Load the reorder point as each product's low-stock threshold.</li>
<li>Check <a href="/tools/inventory-turnover-calculator">turnover</a> by category and look at what is not moving at all.</li>
</ol>
<p>Nothing here needs a consultant, and none of it needs more than a spreadsheet plus the calculators on this site.</p>

<h2 id="roles">Multiple people, one truth</h2>
<p>The moment two people touch stock, three requirements appear that a shared spreadsheet cannot meet:</p>
<ul>
<li><b>Simultaneous access</b> without overwriting each other.</li>
<li><b>Attribution</b> — every change carrying the name of whoever made it.</li>
<li><b>Permissions</b> — a shop assistant recording sales without being able to alter costs or delete products.</li>
</ul>
<p>Being able to answer "who changed this, and when?" removes an entire category of recurring workplace argument. It is worth more than most feature lists suggest.</p>

<h2 id="fail">Why implementations fail</h2>
${table(
  ['Failure', 'What actually happened', 'The fix'],
  [
    ['"The system is always wrong"', 'Movements are not being recorded at the moment they happen', 'Make recording fast and mobile; audit for a fortnight'],
    ['Nobody uses it but the owner', 'Staff have no permissions, or the tool is desk-bound', 'Give roles and put it on phones'],
    ['Abandoned after two months', 'Everything was migrated at once, including 300 dead SKUs', 'Start with the products that actually move'],
    ['Reports look wrong', 'Opening count was adjusted to match the books', 'Recount honestly; accept the variance'],
    ['Alerts are ignored', 'One global low-stock threshold, so alerts are meaningless', 'Per-product reorder points'],
    ['Data stuck in the old sheet', 'No import path, so it was retyped and abandoned halfway', 'Bulk import from Excel, matched on SKU'],
  ]
)}
<p>Notice how few of these are software problems. The common thread is a process that asks people to do something inconvenient at the moment stock actually moves.</p>
<p>If you want to see what this looks like implemented, <a href="/features">SmartShelfKart's feature list</a> maps directly onto these steps — catalogue and Excel import, stock takes, typed movements with reasons, per-product thresholds, roles, and reports derived from the movement record. It is <a href="/pricing">free on every tier</a> during the launch period.</p>`,
  faqs: [
    { q: 'Where should a small business start with inventory management?', a: 'With the catalogue. One row per distinct sellable item, a stable SKU, a category and a cost. Then one honest full count, then recording movements as they happen. Reorder points come after there is data to calculate them from.' },
    { q: 'Do I need software, or is a spreadsheet fine?', a: 'A spreadsheet is genuinely fine for one person with a small stable catalogue. It stops being fine when two people need to update stock at once, when you need to know who changed something, or when returns and part-deliveries need unwinding.' },
    { q: 'How often should a small business count stock?', a: 'One full count to establish a baseline, then cycle counting continuously — high-value items monthly, the long tail annually. Continuous counting finds problems while they are still small.' },
    { q: 'What is the most common reason inventory systems fail?', a: 'Movements are not recorded at the moment they happen. Everything else follows from that: counts drift, reports lose credibility, and staff go back to checking the shelf.' },
    { q: 'How long does it take to set up?', a: 'A clean catalogue and a first count is typically a few days of real work for a small business. The habit of recording movements takes a few weeks to bed in, and that is the part worth protecting.' },
  ],
  links: [
    { href: '/compare/inventory-management-software-vs-excel', label: 'Inventory software vs. Excel' },
    { href: '/blog/stock-audit-cycle-counting', label: 'Stock audits and cycle counting' },
    { href: '/blog/what-is-inventory-management', label: 'What is inventory management?' },
    { href: '/pricing', label: 'SmartShelfKart pricing' },
  ],
});

export const barcodeGuide = guide({
  slug: 'barcode-inventory-system-guide',
  title: 'How to Set Up a Barcode Inventory System (Step by Step)',
  h1: 'Setting up a barcode inventory system',
  description:
    'A practical guide to barcode inventory: what hardware you actually need, SKU versus barcode, labelling products that have none, and where scanning pays for itself.',
  published: '2026-06-24',
  modified: '2026-09-08',
  lead: 'Barcodes are cheap, the hardware is cheap, and the payoff is immediate — but only if scanning is wired into the moments where stock actually moves. Here is how to set it up without buying anything you do not need.',
  contents: [
    { id: 'why', label: 'What barcoding actually buys you' },
    { id: 'hardware', label: 'The hardware you need' },
    { id: 'sku', label: 'SKU vs barcode' },
    { id: 'none', label: 'Products with no barcode' },
    { id: 'workflows', label: 'Where scanning pays off' },
    { id: 'rollout', label: 'A one-week rollout' },
  ],
  sections: `
<h2 id="why">What barcoding actually buys you</h2>
<p>Not speed, primarily. Accuracy. A person typing a SKU makes an error every few hundred entries; a scanner does not. Over a year of stock movements that difference is the gap between records you trust and records you check against the shelf.</p>
<p>Speed follows as a second-order effect, and it matters most in the places where you currently avoid recording things because it takes too long — which are exactly the places your data is worst.</p>

<h2 id="hardware">The hardware you need</h2>
${table(
  ['Situation', 'What to use', 'Rough cost'],
  [
    ['Shop floor, warehouse aisle, van', 'The phone already in your pocket', '₹0'],
    ['Fixed counter or receiving desk', 'USB keyboard-wedge scanner', '₹1,000–₹2,500'],
    ['Moving around near a desktop', 'Bluetooth keyboard-wedge scanner', '₹2,500–₹6,000'],
    ['High-volume warehouse picking', 'Rugged handheld terminal', '₹25,000+'],
  ]
)}
<p>Start at the top of that table. A phone camera is a perfectly good scanner for anything under a few hundred scans a day, and the marginal cost is zero. Buy a wired scanner when you find yourself standing at the same desk scanning repeatedly.</p>
<div class="callout"><p><b>"Keyboard wedge"</b> means the scanner presents itself to the computer as a keyboard: it types the digits and presses Enter. There is no driver, no configuration and no integration — it works with any software that has a text field, which is why the cheap ones are fine. Avoid anything requiring proprietary software unless you have a specific reason.</p></div>

<h2 id="sku">SKU vs barcode — keep them separate</h2>
<p>These are different identifiers doing different jobs, and merging them causes problems that only surface months later:</p>
<ul>
<li><b>SKU</b> — yours. You choose the format, it means something to your team, and it survives a supplier changing their packaging or their part number.</li>
<li><b>Barcode (EAN/UPC)</b> — the manufacturer's, printed on the box. You do not control it. Two of your SKUs can share one if you repack, and a supplier can change it without telling you.</li>
</ul>
<p>Store both on every product. The practical payoff is bulk updates: a supplier price list keyed to their barcodes can be imported directly, and your own team's count keyed to your SKUs can be imported directly, with no manual matching in between.</p>

<h2 id="none">Products with no barcode</h2>
<p>Loose goods, repacks, own-brand and anything you make yourself. Two workable approaches:</p>
<ol>
<li><b>Print your own.</b> Use the SKU as the barcode value and print Code 128 labels. A basic thermal label printer is ₹6,000–₹12,000 and any label software will encode plain text as Code 128. Do not buy into a proprietary label ecosystem for this.</li>
<li><b>Do not barcode them.</b> Every screen that accepts a scan also accepts a search by name, SKU or category. Barcodes make things faster; they are not a prerequisite. Barcode the fast movers, search for the rest.</li>
</ol>
<p>Option 2 is underrated. Barcoding a 400-line catalogue where 40 lines are 80% of the movement is mostly wasted effort — <a href="/blog/abc-analysis-inventory">ABC analysis</a> will tell you which 40.</p>

<h2 id="workflows">Where scanning actually pays off</h2>
<p>A scanner attached to nothing is a toy. The value is in wiring it into specific moments:</p>
<ul>
<li><b>Receiving.</b> Scan each line as it comes off the vehicle, against the purchase order. Discrepancies surface while the driver is still there, which is the only time they are easy to resolve.</li>
<li><b>Stock takes.</b> The biggest single win. Walking a shelf scanning is several times faster than reading and typing, and vastly more accurate. <a href="/blog/stock-audit-cycle-counting">Cycle counting</a> becomes practical rather than aspirational.</li>
<li><b>Counter sales.</b> Scanning at point of sale keeps stock live without anyone doing a second data-entry job.</li>
<li><b>Picking and despatch.</b> Scanning against the order catches the wrong-item error before it reaches the customer, which is where it becomes expensive.</li>
<li><b>Lookups.</b> Scanning to see current stock, price and history is a small thing that gets used dozens of times a day.</li>
</ul>

<h2 id="rollout">A one-week rollout</h2>
<ol>
<li><b>Day 1.</b> Audit the catalogue. Which products already have barcodes on the packaging? Capture them — scan each product once into the barcode field.</li>
<li><b>Day 2.</b> Decide which unbarcoded products get printed labels. Use ABC: the A items, and anything counted often.</li>
<li><b>Day 3.</b> Print and apply labels. Put them where they can be scanned without moving the product.</li>
<li><b>Day 4.</b> Wire scanning into receiving. This is the highest-value workflow and the easiest to train.</li>
<li><b>Day 5.</b> Run a cycle count on one category, scanning. Compare the time taken with your last manual count; this is the number that convinces everyone else.</li>
<li><b>Week 2 onwards.</b> Add point of sale and picking once receiving is habitual. Do not roll out five workflows simultaneously.</li>
</ol>
<p>In <a href="/features/barcode-inventory-management">SmartShelfKart</a> the camera works on Android and iOS, keyboard-wedge scanners work on the web, and a scan lands directly in the movement screen you were headed for — so the scan produces a recorded transaction rather than just a lookup.</p>`,
  faqs: [
    { q: 'What hardware do I need for a barcode inventory system?', a: 'To start, nothing — a phone camera is a capable scanner for a few hundred scans a day. Add a USB keyboard-wedge scanner (₹1,000–₹2,500) where someone stands at a fixed desk scanning repeatedly.' },
    { q: 'What is a keyboard-wedge barcode scanner?', a: 'One that presents itself to the computer as a keyboard: it types the decoded digits and presses Enter. No driver and no integration are needed, which is why inexpensive models work with any software that has a text field.' },
    { q: 'What if my products do not have barcodes?', a: 'Either print your own using the SKU as the barcode value — a basic thermal label printer and Code 128 is enough — or skip barcodes for those lines and search by name or SKU instead. Barcode the fast movers first.' },
    { q: 'Should the SKU and the barcode be the same?', a: 'No. The SKU is yours and stays stable; the barcode belongs to the manufacturer and can change. Storing both separately lets you bulk-import from either your own data or a supplier\'s list.' },
    { q: 'Which barcode format should I use for my own labels?', a: 'Code 128 for internal labels — it is compact, encodes alphanumeric SKUs, and every scanner reads it. EAN-13 or UPC-A are only needed if your products will be scanned at someone else\'s till.' },
  ],
  links: [
    { href: '/features/barcode-inventory-management', label: 'Barcode inventory in SmartShelfKart' },
    { href: '/blog/stock-audit-cycle-counting', label: 'Stock audits and cycle counting' },
    { href: '/blog/abc-analysis-inventory', label: 'ABC analysis' },
    { href: '/blog/inventory-management-for-small-business', label: 'Inventory management for a small business' },
  ],
});

export const audit = guide({
  slug: 'stock-audit-cycle-counting',
  title: 'Stock Audits and Cycle Counting — A Practical Method',
  h1: 'Stock audits and cycle counting',
  description:
    'How to run a stock audit properly and move to cycle counting: count frequency by ABC class, handling variances, and the rules that keep counts honest.',
  published: '2026-07-15',
  modified: '2026-09-08',
  lead: 'The annual full count is a ritual that finds problems eleven months too late. Cycle counting finds the same problems while they are still small enough to explain.',
  contents: [
    { id: 'why', label: 'Why counts drift' },
    { id: 'full', label: 'Running a full count properly' },
    { id: 'cycle', label: 'Moving to cycle counting' },
    { id: 'frequency', label: 'How often to count what' },
    { id: 'variance', label: 'Handling variances' },
    { id: 'accuracy', label: 'Measuring accuracy honestly' },
  ],
  sections: `
<h2 id="why">Why counts drift</h2>
<p>Stock records go wrong for a small number of recurring reasons, and knowing them tells you where to look when a variance appears:</p>
<ul>
<li><b>Movements not recorded</b> — the biggest single cause. Something was sold, sampled, used internally or given away and nobody wrote it down.</li>
<li><b>Movements recorded twice</b> — a receipt entered by two people, or a sale recorded at both the till and the office.</li>
<li><b>Wrong SKU</b> — two similar products, one entry, both now wrong in opposite directions. These show up as matched pairs of variances.</li>
<li><b>Unit-of-measure confusion</b> — a case counted as one unit, or the reverse. Usually a large, obviously round-numbered variance.</li>
<li><b>Damage and shrinkage</b> — genuine loss that was never recorded as loss.</li>
<li><b>Returns not processed</b> — goods physically back on the shelf with no record.</li>
</ul>
<p>Note that only two of those are theft-shaped. Most inventory variance is a process problem, and treating every discrepancy as a security matter poisons the exercise.</p>

<h2 id="full">Running a full count properly</h2>
<p>You need at least one, to establish a baseline. Rules that make the difference between a count worth having and an expensive fiction:</p>
<ol>
<li><b>Freeze movement.</b> Close, or count outside trading hours. A shelf that moves while being counted yields a number that was never true.</li>
<li><b>Count blind.</b> Do not show the counter the expected figure. Anchoring is powerful and people will unconsciously reconcile toward it.</li>
<li><b>Two people on high-value lines.</b> One counts, one records.</li>
<li><b>Count by location, not by list.</b> Walking the shelf in physical order is faster and misses less than hunting products from a catalogue order.</li>
<li><b>Record what you find, including zero.</b> A product not found is a count of zero, not a blank to fill in later.</li>
<li><b>Recount the extremes before posting.</b> Anything with a large variance gets a second look while you are still there.</li>
<li><b>Post the count as adjustments with a reason.</b> Not as overwritten quantities. The history is the point.</li>
</ol>
<div class="callout callout--warn"><p><b>Never adjust the count to match the books.</b> It is tempting, it makes the paperwork tidy, and it destroys the only honest measurement you have. If the variance is uncomfortable, the discomfort is the information.</p></div>

<h2 id="cycle">Moving to cycle counting</h2>
<p>Instead of counting everything once a year, count a slice continuously — a category a week, or twenty products a day. Advantages compound:</p>
<ul>
<li>No shutdown, so no lost trading days.</li>
<li>Errors are found within weeks, while the cause is still traceable. A variance found eleven months later is unexplainable by definition.</li>
<li>The count becomes routine rather than an annual crisis, and routine work is done better.</li>
<li>High-value items get counted far more often than low-value ones, which is where the effort belongs.</li>
</ul>
<p>Twenty products a day covers a 2,000-line catalogue roughly four times a year at a cost of perhaps fifteen minutes daily. That is a fraction of the labour of one annual count, spread out and far more useful.</p>

<h2 id="frequency">How often to count what</h2>
${table(
  ['Class', 'Share of value', 'Count frequency', 'Counts per year'],
  [
    ['A', '~75%', 'Monthly', '12'],
    ['B', '~20%', 'Quarterly', '4'],
    ['C', '~5%', 'Annually', '1'],
    ['High-shrinkage items', 'any', 'Weekly to monthly', '12–52'],
    ['New products', 'any', 'Monthly for the first quarter', '3'],
  ]
)}
<p>Derive the classes from <a href="/blog/abc-analysis-inventory">ABC analysis</a>. Promote anything with a history of shrinkage regardless of value — small high-theft items are frequently C-class by value and deserve A-class attention.</p>

<h2 id="variance">Handling variances</h2>
<p>A variance is information, not an accusation. Work it in this order:</p>
<ol>
<li><b>Recount.</b> A meaningful share of variances are counting errors. Recount before investigating anything.</li>
<li><b>Check the neighbours.</b> A +12 on one SKU and a &minus;12 on a similar one is a mis-scan, not a loss.</li>
<li><b>Check unit of measure.</b> Variances that are exact multiples of case size are almost always a packing-unit error.</li>
<li><b>Check recent movements.</b> The <a href="/features/inventory-reports-and-analytics">stock ledger</a> for that product usually contains the answer — a missing receipt, a duplicated sale.</li>
<li><b>Set a materiality threshold.</b> Investigate variances above a value; absorb the rest. Chasing a ₹40 discrepancy costs more than the discrepancy.</li>
<li><b>Post the adjustment with a reason code.</b> Damage, theft, count error, unrecorded sale. Over months, the distribution of reason codes tells you what to fix — and that distribution is the real output of a counting programme.</li>
</ol>

<h2 id="accuracy">Measuring accuracy honestly</h2>
<div class="formula">Record accuracy = lines counted correctly &divide; lines counted

Count a line "correct" only if it matches exactly,
or within a tolerance you set in advance.</div>
<p>Measure by line, not by value — otherwise one large correct line hides fifty small wrong ones. World-class is above 97%; below 90% means the records are not being used for decisions, whatever anyone says. Track it over time: the trend is far more informative than the level.</p>
<p>Two rules keep the number honest. Set the tolerance <em>before</em> counting, not after seeing the results. And publish the number to the people doing the recording — accuracy improves when the people creating the data can see its effect.</p>
<p>None of this works without a system that treats a count as a set of typed adjustments with reasons attached rather than a set of overwritten numbers. In <a href="/features">SmartShelfKart</a>, a stock take captures counted quantities, computes the variance against the system position, and posts adjustments carrying the stock take as their reason — so the count is still explainable a year later.</p>`,
  faqs: [
    { q: 'What is cycle counting?', a: 'Counting a small slice of the catalogue continuously — a category a week, or twenty products a day — instead of shutting down for one annual full count. Errors surface within weeks, while their cause is still traceable.' },
    { q: 'How often should stock be counted?', a: 'By value class: A items monthly, B items quarterly, C items annually. Promote anything with a history of shrinkage or any newly launched product regardless of its value class.' },
    { q: 'What is a good inventory record accuracy?', a: 'Above 97% of lines matching is strong. Below 90% means the records are not reliable enough to make decisions from. Measure by line rather than by value, so one large correct line does not mask many small wrong ones.' },
    { q: 'Should I investigate every stock discrepancy?', a: 'No. Set a materiality threshold and investigate above it; absorb the rest. Chasing a ₹40 variance costs more than the variance. Always recount first — many discrepancies are counting errors.' },
    { q: 'Why should I not adjust a count to match the books?', a: 'Because the variance is the only honest measurement you have of how much stock you are actually losing and why. Adjusting to the book figure produces tidy paperwork and destroys the information.' },
  ],
  links: [
    { href: '/blog/abc-analysis-inventory', label: 'ABC analysis' },
    { href: '/blog/barcode-inventory-system-guide', label: 'Setting up a barcode inventory system' },
    { href: '/blog/inventory-management-for-small-business', label: 'Inventory management for a small business' },
    { href: '/features/inventory-reports-and-analytics', label: 'Reports and the stock ledger' },
  ],
});

export default [abc, turnover, smallBiz, barcodeGuide, audit];
