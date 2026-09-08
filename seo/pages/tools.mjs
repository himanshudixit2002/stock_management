import { site } from '../site.mjs';
import { faqLd, esc } from '../layout.mjs';
import { section, wrap, cards, faqBlock, cta, related, table, sawtoothFigure } from '../blocks.mjs';

/**
 * Renders a calculator page. The maths runs entirely in the visitor's browser:
 * nothing typed here is transmitted, which is both a genuine privacy property
 * and the reason these pages need no backend.
 */
function toolPage({ slug, title, h1, description, lead, fields, compute, prose, faqs, links, howto }) {
  const path = '/tools/' + slug;
  const trail = [
    { href: '/', label: 'Home' },
    { href: '/tools', label: 'Free tools' },
    { href: path, label: h1.length > 40 ? h1.slice(0, 38) + '…' : h1 },
  ];

  const inputs = fields
    .map((f) => {
      if (f.options) {
        return `<div><label for="${f.id}">${f.label}${
          f.hint ? `<small>${f.hint}</small>` : ''
        }</label><select id="${f.id}">${f.options
          .map((o) => `<option value="${o[1]}"${o[2] ? ' selected' : ''}>${esc(o[0])}</option>`)
          .join('')}</select></div>`;
      }
      return `<div><label for="${f.id}">${f.label}${
        f.hint ? `<small>${f.hint}</small>` : ''
      }</label><input type="number" id="${f.id}" value="${f.value}" min="${
        f.min ?? 0
      }" step="${f.step ?? 'any'}" inputmode="decimal"></div>`;
    })
    .join('');

  const ids = fields.map((f) => f.id);

  const script = `<script>
(function(){
  var ids=${JSON.stringify(ids)};
  var els={};ids.forEach(function(i){els[i]=document.getElementById(i);});
  var main=document.getElementById('r-main'),note=document.getElementById('r-note'),
      rows=document.getElementById('r-rows'),err=document.getElementById('r-err');
  var nf=function(n,d){return isFinite(n)?Number(n).toLocaleString('en-IN',{minimumFractionDigits:d==null?0:d,maximumFractionDigits:d==null?0:d}):'—';};
  var compute=${compute};
  function run(){
    var v={};for(var i=0;i<ids.length;i++){var raw=els[ids[i]].value;v[ids[i]]=raw===''?NaN:parseFloat(raw);}
    var out;
    try{out=compute(v,nf);}catch(e){out={err:'Check the numbers above.'};}
    if(out.err){err.textContent=out.err;err.hidden=false;main.textContent='—';note.textContent='';rows.innerHTML='';return;}
    err.hidden=true;
    main.textContent=out.main;
    note.textContent=out.note||'';
    rows.innerHTML=(out.rows||[]).map(function(r){
      return '<li><span>'+r[0]+'</span><b>'+r[1]+'</b></li>';}).join('');
  }
  ids.forEach(function(i){els[i].addEventListener('input',run);els[i].addEventListener('change',run);});
  run();
})();
</script>`;

  const body = `
<section class="hero" style="padding-bottom:34px">${wrap(`
  <p class="eyebrow">Free tool</p>
  <h1 style="max-width:24ch">${h1}</h1>
  <p class="hero__lead">${lead}</p>
`)}</section>

<section class="sec sec--tight">${wrap(
    `<div class="calc">
      <div class="calc__fields">${inputs}</div>
      <div class="calc__out">
        <p class="calc__big" id="r-main" aria-live="polite">—<small id="r-note"></small></p>
        <ul class="calc__rows" id="r-rows"></ul>
        <p class="calc__err" id="r-err" hidden></p>
      </div>
    </div>
    <p class="meta">Everything is calculated in your browser. Nothing you type on this page is sent to a server, stored, or logged.</p>
    <div class="prose">${prose}</div>
    ${related('Related', links)}`,
    'wrap--narrow'
  )}</section>

${section({ alt: true, title: 'Questions', body: faqBlock(faqs) })}
${cta({
    title: 'Stop recalculating this by hand every month',
    body: 'SmartShelfKart keeps a reorder point on every product and watches it against live stock, so the number you just worked out becomes an alert instead of a spreadsheet you forget to update.',
  })}`;

  const schema = [faqLd(faqs)];
  if (howto) schema.push(howto);
  schema.push({
    '@type': 'WebApplication',
    name: h1,
    url: site.origin + path,
    applicationCategory: 'BusinessApplication',
    operatingSystem: 'Any',
    browserRequirements: 'Requires JavaScript',
    offers: { '@type': 'Offer', price: '0', priceCurrency: 'INR' },
  });

  return {
    path,
    file: 'tools/' + slug + '.html',
    title,
    description,
    trail,
    priority: '0.8',
    changefreq: 'monthly',
    schema,
    script,
    body,
  };
}

/* ------------------------------------------------------------------ */

const Z_OPTIONS = [
  ['80% service level (Z = 0.84)', '0.8416'],
  ['85% service level (Z = 1.04)', '1.0364'],
  ['90% service level (Z = 1.28)', '1.2816'],
  ['95% service level (Z = 1.65)', '1.6449', true],
  ['97% service level (Z = 1.88)', '1.8808'],
  ['98% service level (Z = 2.05)', '2.0537'],
  ['99% service level (Z = 2.33)', '2.3263'],
  ['99.9% service level (Z = 3.09)', '3.0902'],
];

const reorder = toolPage({
  slug: 'reorder-point-calculator',
  title: 'Reorder Point Calculator (Free, No Sign-Up)',
  h1: 'Reorder point calculator',
  description:
    'Work out the stock level at which to place your next order. Free reorder point calculator using average demand, lead time, demand variability and your chosen service level.',
  lead: 'Enter how fast the product sells, how long your supplier takes, and how confident you want to be. The calculator returns the stock level at which you should place the next order — and the safety stock inside it.',
  fields: [
    { id: 'd', label: 'Average demand', hint: 'Units sold per day', value: 40, step: '0.01' },
    { id: 'l', label: 'Lead time', hint: 'Days from order to delivery', value: 7, step: '0.1' },
    { id: 'sd', label: 'Demand std. deviation', hint: 'Units per day; 0 if steady', value: 12, step: '0.01' },
    { id: 'sl', label: 'Lead time std. deviation', hint: 'Days; 0 if reliable', value: 1.5, step: '0.01' },
    { id: 'z', label: 'Service level', hint: 'Chance of not stocking out', options: Z_OPTIONS },
  ],
  compute: `function(v,nf){
    if(!isFinite(v.d)||!isFinite(v.l)||v.d<0||v.l<0) return {err:'Enter an average demand and a lead time.'};
    var sd=isFinite(v.sd)?v.sd:0, sl=isFinite(v.sl)?v.sl:0, z=v.z;
    var ltd=v.d*v.l;
    var sigma=Math.sqrt(v.l*sd*sd + v.d*v.d*sl*sl);
    var ss=z*sigma;
    var rop=ltd+ss;
    return {
      main:nf(Math.ceil(rop))+' units',
      note:'Place the next order when stock falls to this level',
      rows:[
        ['Lead time demand (d &times; L)', nf(ltd,1)+' units'],
        ['Demand variability during lead time', nf(sigma,1)+' units'],
        ['Safety stock (Z &times; &sigma;)', nf(Math.ceil(ss))+' units'],
        ['Reorder point, unrounded', nf(rop,1)+' units'],
        ['Days of cover at this level', nf(v.d>0?rop/v.d:0,1)+' days']
      ]
    };
  }`,
  prose: `
${sawtoothFigure('The number this calculator returns is the dashed ROP line. Everything above it is stock you are still selling through; everything below it is the buffer that has to survive the lead time.')}

<h2 id="formula">The formula</h2>
<p>A reorder point is not a guess or a round number. It is the answer to one question: <em>how much stock do I need on hand to survive until the next delivery arrives?</em> That is demand during the lead time, plus a buffer for the times demand or the supplier misbehaves.</p>
<div class="formula">Reorder point = (average daily demand &times; lead time in days) + safety stock

safety stock = Z &times; &radic;( L &times; &sigma;<sub>d</sub>&sup2; + d&sup2; &times; &sigma;<sub>L</sub>&sup2; )</div>
<p>The second term is the part most calculators skip. It combines two independent sources of risk — demand varying day to day (<code>&sigma;<sub>d</sub></code>) and the supplier varying delivery to delivery (<code>&sigma;<sub>L</sub></code>) — because in practice both go wrong, and occasionally both go wrong at once.</p>

<h2 id="inputs">What each input means, and where to get it</h2>
${table(
  ['Input', 'What it is', 'Where to find it'],
  [
    ['Average daily demand (d)', 'Units sold per day over a representative period', 'Total units sold &divide; days in the period, from your sales history'],
    ['Lead time (L)', 'Days from placing the order to stock being available to sell', 'Not the supplier\'s promise — your own measured average, including the day it sits in receiving'],
    ['Demand std. deviation (&sigma;<sub>d</sub>)', 'How much daily demand bounces around the average', '<code>STDEV.P</code> over daily sales in a spreadsheet'],
    ['Lead time std. deviation (&sigma;<sub>L</sub>)', 'How unreliable the supplier is', '<code>STDEV.P</code> over your recorded delivery times'],
    ['Service level (Z)', 'The share of cycles you are willing to get through without stocking out', 'A business decision, not a measurement — see below'],
  ]
)}

<h2 id="service-level">Choosing a service level</h2>
<p>Service level is the only input that is a choice rather than a fact. It sets how often you are prepared to run out during the replenishment window. 95% means you expect to stock out in roughly one cycle in twenty.</p>
<p>Higher is not automatically better. The safety stock term is linear in Z, so moving from 95% to 99.9% nearly doubles your buffer — and that stock is cash sitting on a shelf. A sensible split:</p>
<ul>
<li><b>98–99%</b> for A-class items and anything where a stockout loses the customer, not just the sale.</li>
<li><b>95%</b> for the ordinary middle of the catalogue.</li>
<li><b>85–90%</b> for the slow tail, where the carrying cost of a buffer outweighs the occasional wait.</li>
</ul>
<p><a href="/blog/abc-analysis-inventory">ABC analysis</a> is how you decide which product is in which bucket.</p>

<h2 id="example">A worked example</h2>
<p>You sell an average of 40 units a day. Your supplier takes 7 days, give or take a day and a half. Daily sales have a standard deviation of 12 units. You want a 95% service level.</p>
<ul>
<li>Lead time demand = 40 &times; 7 = <b>280 units</b></li>
<li>&sigma; = &radic;(7 &times; 12&sup2; + 40&sup2; &times; 1.5&sup2;) = &radic;(1,008 + 3,600) &asymp; <b>67.9 units</b></li>
<li>Safety stock = 1.65 &times; 67.9 &asymp; <b>112 units</b></li>
<li>Reorder point = 280 + 112 = <b>392 units</b></li>
</ul>
<p>Note where the risk actually came from: 3,600 of the 4,608 variance came from the supplier being unreliable, not from demand bouncing. Tightening that lead time by half a day would cut the buffer more than any demand forecasting exercise.</p>

<h2 id="mistakes">Three ways this goes wrong</h2>
<ol>
<li><b>Using the supplier's quoted lead time.</b> Use what you have actually measured, from order placed to stock available to sell. The gap between the two is usually several days and is the single most common cause of stockouts at a "correct" reorder point.</li>
<li><b>Setting one reorder point for the whole catalogue.</b> The formula depends on per-product demand and lead time. A global threshold is guaranteed to be wrong for almost every product.</li>
<li><b>Setting it once and never revisiting.</b> Demand drifts and suppliers change. Recalculate at least quarterly, and immediately after any change of supplier.</li>
</ol>

<h2 id="in-app">Making the number do something</h2>
<p>A reorder point in a spreadsheet is a number you have to remember to check. In <a href="/features/low-stock-alerts-and-reorder-points">SmartShelfKart</a> it is a field on the product, watched against live stock, so crossing it puts the product on the Low Stock list and into the reorder suggestions — where it becomes a purchase order instead of a note.</p>`,
  faqs: [
    { q: 'What is the reorder point formula?', a: 'Reorder point = (average daily demand × lead time in days) + safety stock. Safety stock is Z × the standard deviation of demand over the lead time, which combines demand variability and lead-time variability.' },
    { q: 'What service level should I use?', a: 'Around 95% is a reasonable default for most items. Use 98–99% for high-value or customer-critical lines, and 85–90% for the slow tail where the carrying cost of a buffer outweighs the occasional wait.' },
    { q: 'Should I use the supplier\'s quoted lead time?', a: 'No. Use your own measured lead time — from placing the order to the stock actually being available to sell, including receiving and put-away. Quoted lead times are consistently optimistic, and the difference is a leading cause of stockouts at an otherwise correct reorder point.' },
    { q: 'What if my demand is completely steady?', a: 'Set both standard deviations to 0. Safety stock becomes 0 and the reorder point is simply lead time demand. In practice almost nothing is that steady, and a small buffer is cheap insurance.' },
    { q: 'How often should I recalculate?', a: 'Quarterly for most items, and straight away whenever you change supplier or a product\'s demand pattern shifts. A reorder point set two years ago is describing a business that no longer exists.' },
    { q: 'Is this calculator free?', a: 'Yes — free, no sign-up, no email required. It runs entirely in your browser and nothing you enter is sent anywhere.' },
  ],
  links: [
    { href: '/blog/reorder-point-formula', label: 'Guide: the reorder point formula explained' },
    { href: '/tools/safety-stock-calculator', label: 'Safety stock calculator' },
    { href: '/tools/economic-order-quantity-calculator', label: 'EOQ calculator' },
    { href: '/features/low-stock-alerts-and-reorder-points', label: 'Low-stock alerts in SmartShelfKart' },
  ],
  howto: {
    '@type': 'HowTo',
    name: 'How to calculate a reorder point',
    description:
      'Calculate the stock level at which to place a replenishment order using average demand, lead time, variability and a chosen service level.',
    step: [
      { '@type': 'HowToStep', name: 'Measure average daily demand', text: 'Divide units sold over a representative period by the number of days in that period.' },
      { '@type': 'HowToStep', name: 'Measure your real lead time', text: 'Record the days from placing an order to the stock being available to sell, not the supplier quote.' },
      { '@type': 'HowToStep', name: 'Measure variability', text: 'Take the standard deviation of daily demand and of your recorded lead times.' },
      { '@type': 'HowToStep', name: 'Choose a service level', text: 'Pick the share of replenishment cycles you want to get through without a stockout, and use its Z-score.' },
      { '@type': 'HowToStep', name: 'Combine', text: 'Reorder point equals average daily demand times lead time, plus Z times the standard deviation of demand over the lead time.' },
    ],
  },
});

const safety = toolPage({
  slug: 'safety-stock-calculator',
  title: 'Safety Stock Calculator (Free) — Service Level & Z-Score',
  h1: 'Safety stock calculator',
  description:
    'Calculate safety stock from demand variability, lead-time variability and your target service level. Free, no sign-up, with the Z-score table and the formula explained.',
  lead: 'Safety stock is the buffer that absorbs the weeks when demand spikes and the supplier is late at the same time. This works it out properly — from your variability and your chosen service level, not a flat "two weeks of cover".',
  fields: [
    { id: 'd', label: 'Average demand', hint: 'Units per day', value: 40, step: '0.01' },
    { id: 'l', label: 'Average lead time', hint: 'Days', value: 7, step: '0.1' },
    { id: 'sd', label: 'Demand std. deviation', hint: 'Units per day', value: 12, step: '0.01' },
    { id: 'sl', label: 'Lead time std. deviation', hint: 'Days', value: 1.5, step: '0.01' },
    { id: 'c', label: 'Unit cost', hint: 'To price the buffer', value: 250, step: '0.01' },
    { id: 'z', label: 'Service level', hint: 'Target', options: Z_OPTIONS },
  ],
  compute: `function(v,nf){
    if(!isFinite(v.d)||!isFinite(v.l)||v.d<0||v.l<0) return {err:'Enter an average demand and a lead time.'};
    var sd=isFinite(v.sd)?v.sd:0, sl=isFinite(v.sl)?v.sl:0, c=isFinite(v.c)?v.c:0, z=v.z;
    var vd=v.l*sd*sd, vl=v.d*v.d*sl*sl, sigma=Math.sqrt(vd+vl);
    var ss=z*sigma, tot=vd+vl;
    return {
      main:nf(Math.ceil(ss))+' units',
      note:'Buffer to hold on top of lead time demand',
      rows:[
        ['Combined variability (&sigma;)', nf(sigma,1)+' units'],
        ['From demand variability', (tot>0?nf(100*vd/tot,0):'0')+'% of the risk'],
        ['From lead time variability', (tot>0?nf(100*vl/tot,0):'0')+'% of the risk'],
        ['Days of cover this buys', nf(v.d>0?ss/v.d:0,1)+' days'],
        ['Reorder point with this buffer', nf(Math.ceil(v.d*v.l+ss))+' units'],
        ['Cash tied up in the buffer', '&#8377;'+nf(ss*c,0)]
      ]
    };
  }`,
  prose: `
<h2 id="what">What safety stock is actually for</h2>
<p>If demand were perfectly steady and suppliers perfectly punctual, safety stock would be zero: you would order exactly lead time demand and it would arrive exactly as you ran out. Safety stock exists because neither of those is true, and it is sized by <em>how untrue</em> they are — not by how nervous you feel.</p>
<div class="formula">Safety stock = Z &times; &radic;( L &times; &sigma;<sub>d</sub>&sup2; + d&sup2; &times; &sigma;<sub>L</sub>&sup2; )</div>
<p>Two terms, two risks. <code>L &times; &sigma;<sub>d</sub>&sup2;</code> is demand bouncing around over a lead time of L days. <code>d&sup2; &times; &sigma;<sub>L</sub>&sup2;</code> is the supplier being late while you carry on selling at rate d. They are added as variances, then square-rooted, because they are independent — both going wrong at once is possible but not the common case, and sizing for it would be needlessly expensive.</p>

<h2 id="which-risk">Which risk is actually costing you?</h2>
<p>The calculator above splits the two, and the split is usually the most actionable output on this page. In the default example, roughly three quarters of the variance comes from lead-time unreliability rather than demand. That tells you where the fix is: a conversation with the supplier, or a second supplier, will cut your inventory investment far more than any amount of demand forecasting.</p>
<p>If the split runs the other way and demand variability dominates, the lever is different — smoothing demand through better promotion planning, or accepting the buffer as a cost of doing business in that category.</p>

<h2 id="z">The Z-score table</h2>
${table(
  ['Service level', 'Z', 'Stockouts per 20 cycles', 'Buffer vs. 95%'],
  [
    ['80%', '0.84', '4', '&minus;49%'],
    ['85%', '1.04', '3', '&minus;37%'],
    ['90%', '1.28', '2', '&minus;22%'],
    ['95%', '1.65', '1', 'baseline'],
    ['97%', '1.88', '~0.6', '+14%'],
    ['98%', '2.05', '~0.4', '+25%'],
    ['99%', '2.33', '~0.2', '+41%'],
    ['99.9%', '3.09', '~0.02', '+88%'],
  ]
)}
<p>Read the last column before choosing. Going from 95% to 99.9% eliminates roughly one stockout in twenty cycles and costs you 88% more buffer stock, permanently. For most products that is a bad trade; for a hospital consumable it is obviously the right one. The decision is per-product, which is precisely what <a href="/blog/abc-analysis-inventory">ABC analysis</a> is for.</p>

<h2 id="wrong">Why "two weeks of cover" costs you twice</h2>
<p>The flat-cover rule is popular because it is easy, and wrong in both directions at once. On a steady, reliably supplied product it holds far more stock than the risk justifies — cash sitting idle. On a volatile product with a flaky supplier it holds far too little, and you stock out anyway despite carrying the buffer. You pay for insurance you did not need and remain uninsured where you did.</p>

<h2 id="cost">Costing the decision</h2>
<p>The calculator prices the buffer at your unit cost so the trade-off is visible in money rather than units. Multiply that figure across the catalogue and safety stock stops being an abstract policy and becomes a line item — typically one of the larger ones a small business is carrying without ever having decided to.</p>

<h2 id="next">Turning it into a working number</h2>
<p>Safety stock on its own is not operational; it becomes operational as part of a <a href="/tools/reorder-point-calculator">reorder point</a>, which is the level a system can actually watch. In <a href="/features/low-stock-alerts-and-reorder-points">SmartShelfKart</a> that lives on the product as its low-stock threshold, monitored against live stock.</p>`,
  faqs: [
    { q: 'What is the safety stock formula?', a: 'Safety stock = Z × √(L × σd² + d² × σL²), where Z is the service-level factor, L is average lead time, σd is the standard deviation of daily demand, d is average daily demand and σL is the standard deviation of lead time.' },
    { q: 'Is "two weeks of stock" a good rule?', a: 'No. It ignores how variable the product and the supplier actually are, so it simultaneously over-stocks steady lines and under-stocks volatile ones. You pay for a buffer you did not need on one product and stock out on another despite carrying one.' },
    { q: 'What Z-score corresponds to a 95% service level?', a: '1.65. Common values are 1.28 for 90%, 1.65 for 95%, 2.05 for 98%, 2.33 for 99% and 3.09 for 99.9%.' },
    { q: 'Can safety stock be zero?', a: 'Mathematically yes, when both demand and lead time are perfectly stable. In practice a zero buffer means you stock out roughly half the time, since demand exceeds its own average about half the time.' },
    { q: 'Should safety stock be the same for every product?', a: 'No. It scales with each product\'s own variability and the service level you choose for it, so it is necessarily per-product. Use ABC analysis to decide which products deserve a high service level.' },
  ],
  links: [
    { href: '/blog/safety-stock-formula', label: 'Guide: the safety stock formula explained' },
    { href: '/tools/reorder-point-calculator', label: 'Reorder point calculator' },
    { href: '/blog/abc-analysis-inventory', label: 'Guide: ABC analysis' },
    { href: '/features/low-stock-alerts-and-reorder-points', label: 'Low-stock alerts in SmartShelfKart' },
  ],
});

const eoq = toolPage({
  slug: 'economic-order-quantity-calculator',
  title: 'EOQ Calculator — Economic Order Quantity (Free)',
  h1: 'Economic order quantity (EOQ) calculator',
  description:
    'Free EOQ calculator using the Wilson formula. Find the order quantity that minimises total ordering plus holding cost, with order frequency, cycle length and total cost shown.',
  lead: 'Order too often and you pay for the ordering. Order too rarely and you pay to hold the stock. EOQ is the quantity where those two costs are balanced — and the total cost curve around it is flatter than most people expect.',
  fields: [
    { id: 'dm', label: 'Annual demand', hint: 'Units per year', value: 12000, step: '1' },
    { id: 's', label: 'Cost per order', hint: 'Admin, freight, receiving', value: 1200, step: '0.01' },
    { id: 'h', label: 'Holding cost', hint: 'Per unit, per year', value: 45, step: '0.01' },
    { id: 'c', label: 'Unit cost', hint: 'For total-cost context', value: 250, step: '0.01' },
  ],
  compute: `function(v,nf){
    if(!isFinite(v.dm)||!isFinite(v.s)||!isFinite(v.h)||v.dm<=0||v.s<=0||v.h<=0)
      return {err:'Annual demand, cost per order and holding cost must all be greater than zero.'};
    var q=Math.sqrt(2*v.dm*v.s/v.h);
    var orders=v.dm/q, cycle=365/orders;
    var oc=orders*v.s, hc=(q/2)*v.h, tot=oc+hc;
    var c=isFinite(v.c)?v.c:0;
    return {
      main:nf(Math.round(q))+' units',
      note:'Order this much, this often',
      rows:[
        ['Orders per year', nf(orders,1)],
        ['Days between orders', nf(cycle,0)+' days'],
        ['Annual ordering cost', '&#8377;'+nf(oc,0)],
        ['Annual holding cost', '&#8377;'+nf(hc,0)],
        ['Total annual cost of the policy', '&#8377;'+nf(tot,0)],
        ['Average stock on hand', nf(q/2,0)+' units'+(c>0?' (&#8377;'+nf(q/2*c,0)+')':'')]
      ]
    };
  }`,
  prose: `
<h2 id="formula">The Wilson formula</h2>
<div class="formula">EOQ = &radic;( 2 &times; D &times; S / H )

D = annual demand in units
S = cost of placing one order
H = cost of holding one unit for one year</div>
<p>At the EOQ, annual ordering cost and annual holding cost are exactly equal — which is a useful sanity check on any answer, including this calculator's. If those two rows do not match, something is wrong with the inputs.</p>

<h2 id="inputs">Getting the inputs right</h2>
<p>EOQ has a reputation for being theoretical. That is almost entirely because people put bad numbers into it.</p>
<ul>
<li><b>Cost per order (S)</b> is the cost of the <em>act</em> of ordering, not the value of the goods. It is the time spent raising and chasing the order, inbound freight if it is charged per shipment, and receiving and put-away labour. For a small business this is often ₹500–₹3,000. It does not include the price of the items — that cost is the same however you split the orders.</li>
<li><b>Holding cost (H)</b> is what it costs to keep one unit on a shelf for a year: capital tied up, storage, insurance, shrinkage and obsolescence. A common approximation is 20–30% of the unit cost per year. At a ₹250 unit cost, ₹50–₹75 is a realistic H — and if you are borrowing to fund stock, use your actual cost of capital, not a textbook figure.</li>
<li><b>Annual demand (D)</b> should be forward-looking. Last year's number is a starting point, not the answer, for anything that is growing or declining.</li>
</ul>

<h2 id="flat">The most useful property: the curve is flat</h2>
<p>Total cost near the EOQ is remarkably insensitive to the quantity. Ordering 20% away from the optimum raises total cost by under 2%. Being out by 50% costs about 8%.</p>
<p>Two consequences follow, and they matter more than the formula:</p>
<ol>
<li>You do not need precise inputs. Rough estimates of S and H land you close enough that the residual error is negligible.</li>
<li>You can round freely to something practical — a full case, a pallet, a container, or a supplier minimum — and lose almost nothing. <b>Take the EOQ as guidance and round to whatever the real world orders in.</b></li>
</ol>
<div class="callout"><p>This flatness is why arguing about the third decimal place of holding cost is wasted effort, and why "we cannot calculate S precisely" is not a reason to skip EOQ entirely.</p></div>

<h2 id="limits">When EOQ does not apply</h2>
<p>The model assumes steady demand, a fixed cost per order, constant holding cost and no quantity discounts. Be careful where those break:</p>
<ul>
<li><b>Quantity discounts</b> — if the supplier prices in brackets, compare total cost (purchase + ordering + holding) at the EOQ and at each break point. The right answer is frequently the break point just above the EOQ.</li>
<li><b>Perishable or dated stock</b> — an EOQ larger than what you can sell before expiry is wrong regardless of the arithmetic. Cap it at shelf life.</li>
<li><b>Sharply seasonal demand</b> — the steady-demand assumption fails. Calculate per season, or use a different model.</li>
<li><b>Very slow movers</b> — an EOQ of eleven years' supply is arithmetically correct and commercially absurd.</li>
</ul>

<h2 id="rop">EOQ answers "how much", not "when"</h2>
<p>EOQ and the reorder point are two halves of one policy and neither works alone. EOQ sets the order quantity; the <a href="/tools/reorder-point-calculator">reorder point</a> sets the trigger level. Together they form the classic (Q, R) policy: <em>when stock falls to R, order Q.</em> Set only one and you have half a system.</p>`,
  faqs: [
    { q: 'What is the EOQ formula?', a: 'EOQ = √(2DS/H), where D is annual demand in units, S is the cost of placing one order and H is the cost of holding one unit for a year. At that quantity, annual ordering cost equals annual holding cost.' },
    { q: 'How do I estimate holding cost?', a: 'A common approximation is 20–30% of unit cost per year, covering capital tied up, storage, insurance, shrinkage and obsolescence. If you borrow to fund stock, use your real cost of capital rather than a textbook percentage.' },
    { q: 'Does the cost per order include the price of the goods?', a: 'No. It is the cost of the act of ordering — raising and chasing the order, per-shipment freight, receiving and put-away. The value of the goods is unaffected by how you split the orders.' },
    { q: 'Do I have to order exactly the EOQ?', a: 'No, and you should not try. The total cost curve is very flat near the optimum — being 20% off costs under 2% — so round to a case, pallet or supplier minimum without concern.' },
    { q: 'What about quantity discounts?', a: 'The basic model does not handle them. Compare total cost including purchase price at the EOQ and at each discount break point; the best answer is often the break point just above the EOQ.' },
  ],
  links: [
    { href: '/tools/reorder-point-calculator', label: 'Reorder point calculator' },
    { href: '/tools/inventory-turnover-calculator', label: 'Inventory turnover calculator' },
    { href: '/blog/what-is-inventory-management', label: 'Guide: what is inventory management?' },
    { href: '/features/purchase-orders-and-sales-orders', label: 'Purchase orders in SmartShelfKart' },
  ],
});

const turnover = toolPage({
  slug: 'inventory-turnover-calculator',
  title: 'Inventory Turnover Calculator — Ratio & Days of Supply',
  h1: 'Inventory turnover calculator',
  description:
    'Calculate inventory turnover ratio and days of inventory outstanding from COGS and average inventory. Free calculator with benchmarks by sector and what the number means.',
  lead: 'Turnover tells you how many times a year your shelf sells through. Days of supply says the same thing in a unit you can act on — and it is usually the one worth quoting in a meeting.',
  fields: [
    { id: 'cogs', label: 'Cost of goods sold', hint: 'Per year, at cost', value: 3000000, step: '1' },
    { id: 'open', label: 'Opening inventory', hint: 'At cost', value: 520000, step: '1' },
    { id: 'close', label: 'Closing inventory', hint: 'At cost', value: 480000, step: '1' },
    { id: 'days', label: 'Period length', hint: 'Days covered by the figures', value: 365, step: '1' },
  ],
  compute: `function(v,nf){
    if(!isFinite(v.cogs)||v.cogs<=0) return {err:'Enter the cost of goods sold for the period.'};
    var o=isFinite(v.open)?v.open:0, c=isFinite(v.close)?v.close:0;
    var avg=(o+c)/2;
    if(avg<=0) return {err:'Opening and closing inventory cannot both be zero.'};
    var days=isFinite(v.days)&&v.days>0?v.days:365;
    var t=v.cogs/avg, dio=days/t;
    var weeks=dio/7;
    return {
      main:nf(t,2)+'\u00d7 per period',
      note:'Inventory turnover ratio',
      rows:[
        ['Average inventory', '&#8377;'+nf(avg,0)],
        ['Days of inventory outstanding', nf(dio,0)+' days'],
        ['Weeks of supply on hand', nf(weeks,1)+' weeks'],
        ['Annualised turnover', nf(t*(365/days),2)+'&times; per year'],
        ['Stock as a share of annual COGS', nf(100*avg/(v.cogs*(365/days)),1)+'%']
      ]
    };
  }`,
  prose: `
<h2 id="formula">Two numbers, one idea</h2>
<div class="formula">Inventory turnover = cost of goods sold &divide; average inventory

Average inventory = (opening + closing) &divide; 2

Days of inventory outstanding = days in period &divide; turnover</div>
<p>Turnover of 6 means you sold through your average stockholding six times in the year. Days of inventory outstanding converts that into "about 61 days of stock on hand", which is the version people can actually reason about — and the version that makes the cash implication obvious.</p>

<h2 id="cogs">Use cost, not revenue</h2>
<p>The single most common error is dividing <em>sales</em> by average inventory. Inventory is carried at cost, so putting revenue on top inflates the ratio by your entire gross margin. A business with a 40% margin that uses revenue will report turnover roughly 1.7&times; its real figure and conclude it is running lean when it is not.</p>

<h2 id="benchmarks">What counts as good</h2>
<p>There is no universal target — turnover is a property of the sector far more than of the management. Rough ranges:</p>
${table(
  ['Sector', 'Typical annual turnover', 'Days of supply'],
  [
    ['Grocery and fresh food', '12–25&times;', '15–30 days'],
    ['Fast fashion and apparel', '4–8&times;', '45–90 days'],
    ['General retail', '4–8&times;', '45–90 days'],
    ['Consumer electronics', '6–10&times;', '35–60 days'],
    ['Wholesale and distribution', '5–10&times;', '35–75 days'],
    ['Auto and industrial spares', '2–4&times;', '90–180 days'],
    ['Jewellery and luxury', '1–2&times;', '180–365 days'],
  ]
)}
<p>Compare yourself with your own past figures and with your sector — never with a number from an unrelated industry. A spares business at 3&times; may be extremely well run; a grocer at 3&times; is in serious trouble.</p>

<h2 id="direction">Higher is not always better</h2>
<p>Rising turnover usually means less cash tied up and less obsolescence risk, which is good. Pushed too far it means you are running thin, and thin shows up as stockouts, expedited freight, more frequent ordering and lost sales — none of which appear in the turnover number itself.</p>
<p>That is why turnover should always be read next to a service-level or stockout measure. Turnover alone can be improved by simply refusing to hold stock, which is not an improvement.</p>

<h2 id="aggregate">The trap of the blended figure</h2>
<p>A single company-wide turnover figure hides the thing you most need to see. A business turning over 6&times; overall may consist of fast lines turning 20&times; and dead stock turning 0.3&times;, and the average tells you nothing about either. Calculate it per category, and read it alongside an <a href="/features/inventory-reports-and-analytics">ageing report</a> to find what is not moving at all.</p>
<p><a href="/blog/abc-analysis-inventory">ABC analysis</a> is the natural complement: it identifies which lines carry the value, and turnover then tells you how fast that value is cycling.</p>

<h2 id="improve">Moving the number honestly</h2>
<ul>
<li>Clear dead stock deliberately — discount, bundle, return or write it off. It is already a loss; carrying it just extends the payment.</li>
<li>Order smaller and more often where <a href="/tools/economic-order-quantity-calculator">EOQ</a> supports it.</li>
<li>Cut lead times. Shorter lead times mean less <a href="/tools/safety-stock-calculator">safety stock</a> for the same service level, which raises turnover without raising risk.</li>
<li>Prune the tail. Lines that sell twice a year rarely earn their shelf space or their working capital.</li>
</ul>`,
  faqs: [
    { q: 'What is a good inventory turnover ratio?', a: 'It depends almost entirely on sector. Grocery often runs 12–25× a year, general retail 4–8×, wholesale 5–10×, and spares or jewellery 1–4×. Compare against your own history and your sector rather than a universal target.' },
    { q: 'Should I use sales or cost of goods sold?', a: 'Cost of goods sold. Inventory is carried at cost, so using revenue inflates the ratio by your entire gross margin and makes the business look leaner than it is.' },
    { q: 'What is days of inventory outstanding?', a: 'Days in the period divided by the turnover ratio — the number of days of stock you are carrying. Turnover of 6 over a year is about 61 days of supply.' },
    { q: 'Is a higher turnover always better?', a: 'No. Beyond a point high turnover means running thin, which shows up as stockouts, expedited freight and lost sales that the ratio itself does not capture. Read it alongside a service-level measure.' },
    { q: 'How do I improve inventory turnover?', a: 'Clear dead stock deliberately, order in smaller and more frequent quantities where EOQ supports it, shorten lead times so less safety stock is needed, and prune slow-moving lines that do not earn their working capital.' },
  ],
  links: [
    { href: '/blog/inventory-turnover-ratio', label: 'Guide: the inventory turnover ratio' },
    { href: '/blog/abc-analysis-inventory', label: 'Guide: ABC analysis' },
    { href: '/tools/economic-order-quantity-calculator', label: 'EOQ calculator' },
    { href: '/features/inventory-reports-and-analytics', label: 'Reports in SmartShelfKart' },
  ],
});

/* ------------------------------------------------------------------ */

const indexPage = {
  path: '/tools',
  file: 'tools.html',
  title: 'Free Inventory Calculators — Reorder Point, EOQ, Safety Stock',
  description:
    'Four free inventory management calculators: reorder point, safety stock, economic order quantity and inventory turnover. No sign-up, no email, everything runs in your browser.',
  trail: [
    { href: '/', label: 'Home' },
    { href: '/tools', label: 'Free tools' },
  ],
  priority: '0.9',
  changefreq: 'monthly',
  body: `
<section class="hero">${wrap(`
  <p class="eyebrow">Free tools</p>
  <h1 style="max-width:20ch">Inventory calculators, free and without a sign-up wall</h1>
  <p class="hero__lead">The four calculations that decide how much stock you carry and when you reorder. Each page shows the formula, explains where every input comes from, and works through a real example — so you can check the answer rather than trust it.</p>
  <p class="hero__note">No account, no email, nothing stored. All four run entirely in your browser.</p>
`)}</section>

${section({
    tight: true,
    body: cards([
      { title: 'Reorder point calculator', body: 'The stock level that should trigger your next order, from demand, lead time, variability and service level.', href: '/tools/reorder-point-calculator', more: 'Open the calculator' },
      { title: 'Safety stock calculator', body: 'The buffer needed to hit a chosen service level, with the demand-risk and supplier-risk split shown separately.', href: '/tools/safety-stock-calculator', more: 'Open the calculator' },
      { title: 'EOQ calculator', body: 'The order quantity that balances ordering cost against holding cost, plus order frequency and total annual cost.', href: '/tools/economic-order-quantity-calculator', more: 'Open the calculator' },
      { title: 'Inventory turnover calculator', body: 'Turnover ratio and days of supply from COGS and average inventory, with benchmarks by sector.', href: '/tools/inventory-turnover-calculator', more: 'Open the calculator' },
    ]),
  })}

${section({
    alt: true,
    title: 'How the four fit together',
    lead: 'They are not four unrelated tools — they are the pieces of a single stock policy.',
    body: `<div class="prose" style="max-width:none">
    <div class="formula">EOQ            &rarr; how much to order
Reorder point  &rarr; when to order
Safety stock   &rarr; how much cushion sits inside the reorder point
Turnover       &rarr; whether the whole policy is leaving too much on the shelf</div>
    <p>Start with turnover to see whether you have a problem at all. If days of supply looks high, use ABC analysis to find where the money is sitting. Then set reorder points and safety stock properly on the items that matter, and use EOQ to decide the quantity on each order. Review quarterly.</p>
    <p>Each calculator page explains its own formula in full, including the assumptions it makes and the cases where it stops being the right model.</p>
  </div>`,
  })}

${cta({
    title: 'Or let the software watch the numbers for you',
    body: 'SmartShelfKart holds a reorder point on every product, checks it against live stock, and turns a breach into a suggested purchase order. Free on every tier during launch.',
  })}`,
};

export default [indexPage, reorder, safety, eoq, turnover];
