// Single source of truth for the static marketing site.
//
// Why this exists at all: smartshelfkart.com is a Flutter CanvasKit app. Every
// heading and paragraph the app renders is a pixel painted into a <canvas>, so
// Googlebot's renderer finds no text nodes and nothing to index. The app cannot
// be made crawlable without abandoning CanvasKit. So the marketing site is a
// separate, hand-authored, static HTML site that shares the domain's authority
// with the app; the app keeps its own shell at /app.

export const site = {
  name: 'SmartShelfKart',
  legalName: 'SmartShelfKart',
  origin: 'https://smartshelfkart.com',
  locale: 'en_IN',
  lang: 'en',
  themeColor: '#0D9488',
  email: 'support@smartshelfkart.com',
  appUrl: '/app',
  playStoreUrl:
    'https://play.google.com/store/apps/details?id=com.stockmanager.stock_management',
  androidAppId: 'com.stockmanager.stock_management',
  github: 'https://github.com/himanshudixit2002/stock_management',
  // Bumped whenever the CSS changes; the filename is content-hashed at build
  // time so the year-long immutable cache header is safe.
  tagline: 'Inventory management software that a small team can actually run',
  // IndexNow lets Bing, Yandex, Seznam and Naver be told about new and
  // changed URLs directly, with no account and no verification beyond
  // hosting this key at /<key>.txt. Google does not participate — that
  // still needs Search Console. Changing this key invalidates it.
  indexNowKey: 'caf86a3dc77afe583a54be9a1c8931e5',
};

/** Top navigation. Kept short on purpose — every link here is a crawl path. */
export const nav = [
  { href: '/features', label: 'Features' },
  { href: '/pricing', label: 'Pricing' },
  { href: '/tools', label: 'Free tools' },
  { href: '/blog', label: 'Guides' },
];

/**
 * Plan tiers.
 *
 * The live catalogue comes from the root `plans` collection the platform
 * console edits — see seo/plans.mjs. These constants are only what
 * PlanCatalog.seedDefaults holds in lib/models/company_plan_model.dart, kept
 * as a last-resort fallback for a build with no network and no cache.
 *
 * They are known to be stale: the console has every tier at a tenth of these
 * figures. Never quote them on the site without saying where they came from.
 */
const SEED_PLANS = [
  { id: 'starter', label: 'Starter', nominalPrice: 999, promotionalPrice: 0, sortOrder: 0,
    description: 'For a single location finding its feet. Core stock control.',
    lockedFeatures: ['aiAssistant'],
    limits: { users: 3, products: 250, invoices: 100, salesOrders: 100, purchaseOrders: 100 } },
  { id: 'growth', label: 'Growth', nominalPrice: 2999, promotionalPrice: 0, sortOrder: 1,
    description: 'A growing team with real order volume and multiple locations.',
    lockedFeatures: ['aiAssistant'],
    limits: { users: 10, products: 2000, invoices: 1000, salesOrders: 1000, purchaseOrders: 1000 } },
  { id: 'pro', label: 'Pro', nominalPrice: 5999, promotionalPrice: 0, sortOrder: 2,
    description: 'Full operations suite with generous headroom.',
    lockedFeatures: [], limits: { users: 50, products: 20000 } },
  { id: 'max', label: 'MAX Tier', nominalPrice: 9999, promotionalPrice: 0, sortOrder: 3,
    description: 'Ultimate business suite. Full access to every feature including AI Assistant.',
    lockedFeatures: [], limits: {} },
];

/**
 * Live bindings. seo/build.mjs resolves the catalogue and calls
 * [setPlanCatalog] before it imports any page module, so a page that reads
 * `plans` at module scope gets the console's figures, not the seeds.
 */
export let plans = SEED_PLANS.map(seedToPlan);
export let promo = null;
export let planSource = 'seed';

export function setPlanCatalog(catalog) {
  if (catalog?.plans?.length) plans = catalog.plans;
  promo = catalog?.promo ?? null;
  planSource = catalog?.source ?? 'seed';
}

/** The seeds in the shape seo/plans.mjs produces, so both paths render alike. */
function seedToPlan(d) {
  const limits = d.limits || {};
  const labels = [
    ['users', 'Team members'], ['products', 'Products'], ['invoices', 'Invoices'],
    ['salesOrders', 'Sales orders'], ['purchaseOrders', 'Purchase orders'],
  ];
  return {
    id: d.id, label: d.label, description: d.description,
    listPrice: d.nominalPrice, promoPrice: d.promotionalPrice,
    sortOrder: d.sortOrder, archived: false, locked: d.lockedFeatures, rawLimits: limits,
    limits: Object.fromEntries(labels.map(([k, l]) => [
      l, typeof limits[k] === 'number' ? limits[k].toLocaleString('en-IN') : 'Unlimited',
    ])),
    get hasAi() { return !this.locked.includes('aiAssistant'); },
  };
}

/**
 * The real feature catalogue, taken from lib/config/feature_map.dart. Grouped
 * the way the app groups it so the site never promises a screen that does not
 * exist.
 */
export const featureGroups = [
  {
    title: 'Daily stock movements',
    blurb:
      'The handful of screens a warehouse or shop floor touches every hour.',
    items: [
      ['Stock In', 'Receive goods against a purchase order or ad hoc.'],
      ['Stock Out', 'Issue, despatch or sell stock and cut the ledger entry.'],
      ['Transfer', 'Move quantity between locations without losing the trail.'],
      ['Adjust', 'Correct a count with a reason code attached.'],
      ['Damage', 'Write off breakage separately from ordinary shrinkage.'],
      ['Hold / Release', 'Reserve stock for a customer before it ships.'],
      ['Fast POS', 'A counter-speed sale screen for walk-in trade.'],
      ['Barcode Scanner', 'Camera scanning on mobile, keyboard wedge on web.'],
    ],
  },
  {
    title: 'Orders and customers',
    blurb: 'Both sides of the order book, end to end.',
    items: [
      ['Purchase Orders', 'Raise, approve, receive and part-receive POs.'],
      ['Sales Orders', 'Quote to despatch, with allocation against stock.'],
      ['Returns', 'Inward and outward returns that restore the right quantity.'],
      ['Customers', 'Ledger, contact history and statement per customer.'],
      ['Vendors', 'Supplier records tied to purchase history and pricing.'],
    ],
  },
  {
    title: 'Billing',
    blurb: 'Invoices that come out of the same catalogue as your stock.',
    items: [
      ['Billing', 'Create invoices straight from a sales order or POS sale.'],
      ['Payments', 'Record receipts and part-payments against an invoice.'],
      ['Credit notes', 'Issue a credit that reconciles with the ledger.'],
      ['Customer statements', 'A running account statement per customer.'],
      ['Billing reports', 'Collected, outstanding and overdue at a glance.'],
    ],
  },
  {
    title: 'Inventory control',
    blurb: 'The parts that stop stockouts before they cost you a sale.',
    items: [
      ['Low Stock', 'A live list of everything under its own threshold.'],
      ['Reorder', 'Suggested reorder quantities from real movement history.'],
      ['Stock Forecast', 'Projected run-out dates per product.'],
      ['Batch Tracking', 'Batch and lot numbers carried through every move.'],
      ['Expiry Alerts', 'Warnings before dated stock becomes unsellable.'],
      ['Stock Take', 'Structured counts with variance against the system.'],
      ['Warehouse Zones', 'Bin and zone locations inside a warehouse.'],
      ['Categories', 'A catalogue tree that the reports group by.'],
    ],
  },
  {
    title: 'Reports and analytics',
    blurb:
      'Every number traces back to an individual transaction you can open.',
    items: [
      ['Dashboard', 'Today in one screen: value, movement, alerts, orders.'],
      ['Profit & Loss', 'Margin by product, category and period.'],
      ['ABC Analysis', 'Which 20% of the catalogue carries the value.'],
      ['Inventory Valuation', 'What the shelf is worth, and how it moved.'],
      ['Ageing', 'How long stock has been sitting, in buckets.'],
      ['Stock Ledger', 'Every in and out for a product, in order.'],
      ['Price History', 'What you paid and charged, over time.'],
      ['Full History', 'The complete transaction record, filterable.'],
    ],
  },
  {
    title: 'Administration',
    blurb: 'Multi-user from the start, without an enterprise rollout.',
    items: [
      ['User Management', 'Invite staff and set what each of them can open.'],
      ['Roles', 'Build a role once and apply it to a whole shift.'],
      ['Audit Log', 'Who changed what, when, and from where.'],
      ['Activity Timeline', 'A readable feed of everything that happened.'],
      ['Data Health', 'Finds duplicate, orphaned and impossible records.'],
      ['Excel Import / Update / Export', 'Bulk load and bulk edit by spreadsheet.'],
    ],
  },
];

/** Cross-link targets used in page footers and related-content strips. */
export const money = {
  home: '/',
  pricing: '/pricing',
  app: '/app',
};
