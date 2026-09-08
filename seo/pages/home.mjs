import { site, plans } from '../site.mjs';
import { faqLd, esc } from '../layout.mjs';
import {
  section, wrap, cards, featureList, faqBlock, cta, softwareLd, table,
} from '../blocks.mjs';

const faqs = [
  {
    q: 'Is SmartShelfKart free?',
    a: 'Yes. Every plan tier is priced at ₹0 during the current launch period, including the tiers that normally carry a monthly list price. You do not need a card to create a workspace, and nothing expires into a paywall without notice.',
  },
  {
    q: 'Does it work without installing anything?',
    a: 'Yes. The web app runs in any modern browser at smartshelfkart.com/app. The Android app on Google Play is the same product against the same database — stock counted on a phone on the floor shows up on the office browser immediately.',
  },
  {
    q: 'Can more than one person use the same stock list?',
    a: 'That is the normal case. You invite staff by email, give each of them a role, and the role decides which screens they can open and which actions they can take. Every change is attributed to a person in the audit log.',
  },
  {
    q: 'Can I move my existing spreadsheet in?',
    a: 'Yes. Import from Excel reads an .xlsx file and creates products in bulk; Update from Excel matches on SKU or barcode and edits what already exists, so a supplier price list becomes a single bulk update rather than hundreds of edits. Export to Excel goes the other way whenever you want your data back.',
  },
  {
    q: 'Does it handle barcodes?',
    a: 'Yes. On Android and iOS the camera scans the barcode directly. On the web a USB or Bluetooth barcode scanner works as a keyboard wedge — focus the field, scan, and the product is found. Each product can carry both a SKU and a barcode.',
  },
  {
    q: 'What happens when stock runs low?',
    a: 'Each product carries its own low-stock threshold rather than one global number. Anything under its threshold appears on the Low Stock screen, and the Reorder screen turns that into a suggested order quantity based on how the product has actually been moving.',
  },
  {
    q: 'Is my data isolated from other businesses?',
    a: 'Yes. Every record is scoped to a company workspace, and access is enforced in Firestore security rules on the server — not merely hidden in the interface. A user who is not a member of your workspace cannot read a single document in it.',
  },
  {
    q: 'Does it work offline?',
    a: 'Partly. The app caches your working set locally, so it keeps rendering and lets you keep reading while the connection is out, and queued writes sync when you come back. It is not designed for long stretches fully offline.',
  },
];

const body = `
<section class="hero">${wrap(`
  <p class="eyebrow">Inventory management software</p>
  <h1>Know exactly what you have, and what you are about to run out of</h1>
  <p class="hero__lead">SmartShelfKart is inventory management software for small and growing businesses — stock, purchase and sales orders, invoicing, and reports that all trace back to the same ledger. It runs in a browser and on Android, against one live database, so the count on the shop floor and the number in the office are never two different numbers.</p>
  <div class="btnrow" style="margin-top:26px">
    <a class="btn" href="${site.appUrl}" data-app-link>Open the web app</a>
    <a class="btn btn--ghost" href="${site.playStoreUrl}" rel="noopener">Get it on Google Play</a>
  </div>
  <p class="hero__note">Free on every tier during launch &middot; No card &middot; Works in the browser, nothing to install</p>
  <div class="stats">
    <div><b>43</b><span>features across six areas of the business</span></div>
    <div><b>3</b><span>platforms — web, Android and iOS, one workspace</span></div>
    <div><b>&#8377;0</b><span>on every plan tier during launch</span></div>
  </div>
`)}</section>

${section({
  alt: true,
  eyebrow: 'The problem',
  title: 'Most small businesses do not lose stock. They lose track of it.',
  lead: 'A spreadsheet works until two people open it, until a return needs unwinding, until someone asks what margin you made on a category last quarter. Then it stops working all at once.',
  body: `<div class="grid">
    <div class="card"><h3>The count is a guess</h3><p>Nobody edits the sheet at the moment stock actually moves, so the number on screen is always some hours or some days behind the shelf.</p></div>
    <div class="card"><h3>Stockouts arrive as surprises</h3><p>Without a per-product threshold and a reorder signal, you find out you are out when a customer asks for it.</p></div>
    <div class="card"><h3>Nobody can answer "why"</h3><p>A quantity changed. There is no reason attached, no timestamp, and no name — so the same argument happens again next month.</p></div>
    <div class="card"><h3>Orders live somewhere else</h3><p>Purchase orders in email, sales in a bill book, stock in a sheet. Reconciling the three is a weekend job.</p></div>
  </div>`,
})}

${section({
  eyebrow: 'What you get',
  title: 'One ledger under everything',
  lead: 'Every screen in SmartShelfKart writes to the same transaction record. That is what makes the reports trustworthy — open any number and you can walk it back to the individual movement that produced it.',
  body: `<div class="grid grid--2">
  <div class="card"><h3>Stock movement, recorded properly</h3><p style="margin-bottom:14px">Receive, issue, transfer, adjust, write off damage, hold stock for a customer and release it again. Every one of those is a typed transaction with a reason and a person against it, not a number someone overtyped.</p>${featureList([
    ['Stock In and Stock Out', 'Against a purchase order, a sales order, or ad hoc.'],
    ['Transfer', 'Between locations, without either side losing the trail.'],
    ['Adjust and Damage', 'Corrections and write-offs kept separate, on purpose.'],
    ['Hold and Release', 'Reserve stock for a customer before it ships.'],
  ])}</div>
  <div class="card"><h3>Orders on both sides</h3><p style="margin-bottom:14px">Raise a purchase order, receive it in parts, and watch the stock land. Take a sales order, allocate against stock, despatch it and bill it — all from the same catalogue.</p>${featureList([
    ['Purchase orders', 'Draft, approve, receive and part-receive.'],
    ['Sales orders', 'Allocate, despatch, and convert to an invoice.'],
    ['Returns', 'Inward and outward, restoring the correct quantity.'],
    ['Vendors and customers', 'With their full history and running statements.'],
  ])}</div>
  <div class="card"><h3>Alerts before the sale is lost</h3><p style="margin-bottom:14px">A per-product low-stock threshold, a reorder screen that reads real movement history, batch and expiry tracking for dated stock, and a forecast of when each line runs out.</p>${featureList([
    ['Low Stock', 'Everything under its own threshold, live.'],
    ['Reorder', 'A suggested quantity, not just a red flag.'],
    ['Expiry alerts', 'Before dated stock becomes unsellable.'],
    ['Stock forecast', 'Projected run-out date per product.'],
  ])}</div>
  <div class="card"><h3>Reports that survive scrutiny</h3><p style="margin-bottom:14px">Profit and loss by product and category, ABC analysis, valuation, ageing buckets, the stock ledger and a full filterable history. Numbers are derived from transactions — never typed in.</p>${featureList([
    ['Profit &amp; Loss', 'Margin by product, category and period.'],
    ['ABC analysis', 'Which fifth of the catalogue carries the value.'],
    ['Ageing and valuation', 'What is sitting, for how long, worth what.'],
    ['Audit log', 'Who changed what, when, from where.'],
  ])}</div>
  </div>
  <p style="margin-top:26px"><a href="/features">See the full feature list &rarr;</a></p>`,
})}

${section({
  alt: true,
  eyebrow: 'How it works',
  title: 'Running by the end of the afternoon',
  body: `<div class="grid">
    <div class="card"><h3>1. Create a workspace</h3><p>Sign in with an email address. A workspace is created for your business, and everything you enter is scoped to it.</p></div>
    <div class="card"><h3>2. Load the catalogue</h3><p>Import an existing Excel sheet, or add products by hand with SKU, barcode, category, cost, price and a low-stock threshold.</p></div>
    <div class="card"><h3>3. Invite the team</h3><p>Add staff by email and give each a role. A role decides exactly which screens open and which actions are allowed.</p></div>
    <div class="card"><h3>4. Move stock through it</h3><p>Receive, sell, transfer and count. From that point the reports have something real to read, and the alerts have something to watch.</p></div>
  </div>`,
})}

${section({
  eyebrow: 'Who it fits',
  title: 'Built for the size of business that cannot run a rollout',
  lead: 'SmartShelfKart is aimed squarely at teams between a spreadsheet and an ERP — where a proper system is overdue, but a six-month implementation is out of the question.',
  body: `<div class="grid">
    <div class="card"><h3>Retail and shops</h3><p>A fast POS screen for counter trade, barcode scanning, and per-product reorder points so shelves refill before they empty.</p></div>
    <div class="card"><h3>Wholesale and distribution</h3><p>Purchase and sales orders on both sides, part-receipts, customer statements, credit notes and ageing.</p></div>
    <div class="card"><h3>Warehouses</h3><p>Zones and bins, transfers between locations, structured stock takes with variance, and a hold-and-release workflow.</p></div>
    <div class="card"><h3>Pharmacy and food</h3><p>Batch and lot tracking carried through every movement, with expiry alerts before dated stock turns into a write-off.</p></div>
    <div class="card"><h3>Manufacturing and workshops</h3><p>Consumption recorded as a typed movement with a reason, damage kept separate from shrinkage, and price history over time.</p></div>
    <div class="card"><h3>Anyone outgrowing a sheet</h3><p>If two people need the file open at once, or you have ever asked "who changed this?", the spreadsheet has already stopped being the right tool.</p></div>
  </div>`,
})}

${section({
  alt: true,
  eyebrow: 'Nova',
  title: 'Ask the inventory a question in plain language',
  lead: 'Nova is a built-in assistant that reads your live data and answers in words — in English or Hinglish. It is not a chatbot bolted onto a marketing page; it queries the same transaction record the reports use, so its numbers and the Reports screen agree.',
  body: `<div class="grid grid--2">
    <div class="card"><h3>Ask what happened</h3><p>&ldquo;Which products did we lose money on last month?&rdquo; &ldquo;What is sitting in stock over 90 days?&rdquo; &ldquo;How much did we buy from this vendor this quarter?&rdquo;</p></div>
    <div class="card"><h3>Ask it to do something</h3><p>Describe a stock adjustment and Nova prepares the action card for you to confirm. Nothing is written without an explicit confirmation, and nothing is invented — if a product is not in your catalogue, it says so instead of making one up.</p></div>
  </div>
  <p style="margin-top:22px"><a href="/features/ai-inventory-assistant">How the AI assistant works &rarr;</a></p>`,
})}

${section({
  eyebrow: 'Pricing',
  title: 'Free on every tier, right now',
  lead: 'Four tiers exist, and each carries a monthly list price. All four are currently set to ₹0 while the product is in its launch period — including the top tier with the AI assistant.',
  body:
    table(
      ['Plan', 'List price', 'Now', 'Team members', 'Products'],
      plans.map((p) => [
        esc(p.label),
        '<span style="text-decoration:line-through;opacity:.6">&#8377;' + p.listPrice.toLocaleString('en-IN') + '/mo</span>',
        '<b>Free</b>',
        esc(p.limits['Team members']),
        esc(p.limits.Products),
      ])
    ) + `<p><a href="/pricing">Full plan comparison, limits and what happens after launch &rarr;</a></p>`,
})}

${section({
  alt: true,
  eyebrow: 'Free tools',
  title: 'Work out the numbers before you commit to software',
  lead: 'Four calculators, free, no sign-up, no email wall. They run entirely in your browser — nothing you type is sent anywhere.',
  body: cards([
    { icon: 'alert', title: 'Reorder point calculator', body: 'The stock level at which you should place the next order, from your lead time, demand and service level.', href: '/tools/reorder-point-calculator', more: 'Calculate' },
    { icon: 'shield', title: 'Safety stock calculator', body: 'How much buffer you need to hit a chosen service level given how variable your demand and lead time actually are.', href: '/tools/safety-stock-calculator', more: 'Calculate' },
    { icon: 'layers', title: 'EOQ calculator', body: 'The order quantity that balances what ordering costs against what holding costs, using the Wilson formula.', href: '/tools/economic-order-quantity-calculator', more: 'Calculate' },
    { icon: 'chart', title: 'Inventory turnover calculator', body: 'How many times a year your stock sells through, and how many days of supply that leaves on the shelf.', href: '/tools/inventory-turnover-calculator', more: 'Calculate' },
  ]),
})}

${section({
  eyebrow: 'Guides',
  title: 'How inventory management actually works',
  lead: 'Practical explanations of the methods the software implements — written so you could apply them on paper if you had to.',
  body: cards([
    { title: 'What is inventory management?', body: 'The whole discipline in one page: what it covers, the terms that matter, and the four decisions every stock system exists to answer.', href: '/blog/what-is-inventory-management', more: 'Read the guide' },
    { title: 'The reorder point formula', body: 'Why lead time demand plus safety stock is the whole formula, and the three ways businesses get it wrong.', href: '/blog/reorder-point-formula', more: 'Read the guide' },
    { title: 'Safety stock, properly', body: 'Where the service-level Z-score comes from, and why a flat "two weeks of cover" costs you money at both ends.', href: '/blog/safety-stock-formula', more: 'Read the guide' },
    { title: 'ABC analysis', body: 'Sorting a catalogue by the value it actually carries, so your counting effort goes where the money is.', href: '/blog/abc-analysis-inventory', more: 'Read the guide' },
    { title: 'Inventory turnover ratio', body: 'What the number means, what counts as good in your sector, and why days-of-supply is easier to act on.', href: '/blog/inventory-turnover-ratio', more: 'Read the guide' },
    { title: 'Moving off a spreadsheet', body: 'An honest comparison — what Excel is genuinely better at, and the specific point at which it stops being enough.', href: '/compare/inventory-management-software-vs-excel', more: 'Read the comparison' },
  ]),
})}

${section({
  alt: true,
  title: 'Common questions',
  body: faqBlock(faqs),
})}

${cta()}
`;

/* Client-side routing courtesies. Neither is user-agent based, so a crawler
   always gets the same page a signed-out visitor gets.
     1. Old bookmarks are of the form "/#/home" — the app used a hash router
        and the server never saw the fragment. Forward those to /app.
     2. A signed-in visitor who typed the bare domain wants the app, not the
        brochure. We look for a Firebase auth session in IndexedDB. An internal
        referrer means the visitor navigated here on purpose (clicked the logo,
        came from a guide), so we leave them alone — that also makes a redirect
        loop between / and /app impossible. */
const bootScript = `<script>
(function(){
  if(location.pathname!=='/')return;
  var h=location.hash;
  if(h&&h.charAt(1)==='/'){location.replace('/app'+h);return;}
  if(location.search)return;
  try{
    var r=document.referrer;
    if(r&&r.indexOf(location.origin)===0)return;
  }catch(e){}
  function go(){location.replace('/app');}
  function scan(){
    try{
      var q=indexedDB.open('firebaseLocalStorageDb');
      q.onupgradeneeded=function(){try{q.transaction.abort();}catch(e){}};
      q.onsuccess=function(){
        var db=q.result;
        try{
          if(!db.objectStoreNames.contains('firebaseLocalStorage')){db.close();return;}
          var k=db.transaction('firebaseLocalStorage','readonly')
                  .objectStore('firebaseLocalStorage').getAllKeys();
          k.onsuccess=function(){
            var hit=(k.result||[]).some(function(x){
              return String(x).indexOf('firebase:authUser:')===0;});
            db.close();
            if(hit)go();
          };
          k.onerror=function(){db.close();};
        }catch(e){try{db.close();}catch(_){}}
      };
    }catch(e){}
  }
  try{
    if(indexedDB.databases){
      indexedDB.databases().then(function(list){
        if((list||[]).some(function(d){return d.name==='firebaseLocalStorageDb';}))scan();
      }).catch(function(){});
    }else{scan();}
  }catch(e){}
})();
</script>`;

export default [
  {
    path: '/',
    file: 'index.html',
    title: 'Inventory Management Software for Small Business | SmartShelfKart',
    ogTitle: 'SmartShelfKart — inventory management software for small business',
    description:
      'Free inventory management software for small business. Track stock, barcodes, purchase and sales orders, invoices and reports on web and Android from one live database.',
    priority: '1.0',
    changefreq: 'weekly',
    trail: [{ href: '/', label: 'Home' }],
    schema: [softwareLd(), faqLd(faqs)],
    script: bootScript,
    body,
  },
];
