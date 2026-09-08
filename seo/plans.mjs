/**
 * The tier catalogue, read from the same place the app reads it.
 *
 * Prices used to be mirrored by hand from `PlanCatalog.seedDefaults` in
 * lib/models/company_plan_model.dart. Those constants are only the seed and the
 * offline fallback — the live catalogue lives in the root `plans` collection
 * that the platform console edits, and it had drifted: the console had every
 * tier at a tenth of the seeded price, so the site was quoting figures ten
 * times too high.
 *
 * `plans` and `publicConfig` are world-readable in firestore.rules ("a price
 * list is public information, and the signed-out register screen needs it"), so
 * this needs no service account — a plain REST read with the web API key.
 *
 * Resolution order: Firestore, then the last successful fetch cached in
 * seo/assets/plans.json, then the compiled seeds. A build with no network
 * publishes the last known real prices rather than the stale constants.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CACHE = path.join(ROOT, 'seo', 'assets', 'plans.json');

const PROJECT = 'stockmanagement-27af8';
const API_KEY = 'AIzaSyDVb670T1cgplCfwewmTmc1eFyOHhdHTDY'; // the web app's key, as in lib/firebase_options.dart
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

/** Firestore's REST value wrapper -> a plain JS value. */
function decode(f) {
  if (f == null) return null;
  if ('integerValue' in f) return Number(f.integerValue);
  if ('doubleValue' in f) return Number(f.doubleValue);
  if ('stringValue' in f) return f.stringValue;
  if ('booleanValue' in f) return f.booleanValue;
  if ('timestampValue' in f) return f.timestampValue;
  if ('nullValue' in f) return null;
  if ('arrayValue' in f) return (f.arrayValue.values || []).map(decode);
  if ('mapValue' in f) return decodeFields(f.mapValue.fields || {});
  return null;
}
const decodeFields = (fields) =>
  Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, decode(v)]));

/** Labels, verbatim from PlanLimitKeys.labelOf, in the order it lists them. */
export const LIMIT_LABELS = [
  ['users', 'Team members'],
  ['products', 'Products'],
  ['invoices', 'Invoices'],
  ['salesOrders', 'Sales orders'],
  ['purchaseOrders', 'Purchase orders'],
];

/**
 * A tier as the site needs it. `limitFor` returns null when a tier does not cap
 * a key, so an absent limit means unlimited — the same reading the app's plan
 * screen gives it.
 */
function normalisePlan(id, d) {
  const limits = d.limits || {};
  return {
    id,
    label: d.label || id,
    description: d.description || '',
    listPrice: typeof d.nominalPrice === 'number' ? d.nominalPrice : null,
    promoPrice: typeof d.promotionalPrice === 'number' ? d.promotionalPrice : null,
    sortOrder: typeof d.sortOrder === 'number' ? d.sortOrder : 99,
    archived: d.archived === true,
    locked: Array.isArray(d.lockedFeatures) ? d.lockedFeatures : [],
    rawLimits: limits,
    limits: Object.fromEntries(
      LIMIT_LABELS.map(([key, label]) => [
        label,
        typeof limits[key] === 'number' ? limits[key].toLocaleString('en-IN') : 'Unlimited',
      ])
    ),
    get hasAi() {
      return !this.locked.includes('aiAssistant');
    },
  };
}

/** The founding-member offer from publicConfig/promo, or null when it is off. */
function normalisePromo(d) {
  if (!d || d.enabled !== true) return null;
  const cap = typeof d.capCount === 'number' ? d.capCount : 0;
  const claimed = typeof d.claimedCount === 'number' ? d.claimedCount : 0;
  const full = cap > 0 && claimed >= cap;
  return {
    // The console owns this copy; the site must not rewrite it.
    headline: full ? d.fullHeadline : d.headline,
    subtext: full ? d.fullSubtext : d.subtext,
    capCount: cap,
    // Advisory only. PromoConfig is explicit that nothing counts signups
    // atomically, so the site must never present this as a live countdown or
    // promise the offer ends when it is reached.
    claimedCount: claimed,
    isFull: full,
    grantPlanId: d.grantPlanId || 'max',
  };
}

async function getJson(url, ms = 12000) {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), ms);
  try {
    const r = await fetch(url, { signal: ac.signal });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return await r.json();
  } finally {
    clearTimeout(t);
  }
}

/**
 * @param {object[]} seedPlans compiled fallback, shaped like normalisePlan output
 * @returns {Promise<{plans:object[], promo:object|null, source:string, note:string}>}
 */
export async function fetchPlanCatalog(seedPlans) {
  try {
    const [plansDoc, promoDoc] = await Promise.all([
      getJson(`${BASE}/plans?key=${API_KEY}`),
      getJson(`${BASE}/publicConfig/promo?key=${API_KEY}`).catch(() => null),
    ]);

    const plans = (plansDoc.documents || [])
      .map((doc) => normalisePlan(doc.name.split('/').pop(), decodeFields(doc.fields || {})))
      .filter((p) => !p.archived)
      .sort((a, b) => a.sortOrder - b.sortOrder);

    if (!plans.length) throw new Error('plans collection is empty');

    const promo = promoDoc && promoDoc.fields ? normalisePromo(decodeFields(promoDoc.fields)) : null;
    const payload = { plans, promo, fetchedAt: new Date().toISOString() };

    fs.mkdirSync(path.dirname(CACHE), { recursive: true });
    fs.writeFileSync(CACHE, JSON.stringify(payload, null, 2) + '\n');

    return { ...payload, source: 'firestore', note: `${plans.length} tiers live from the platform console` };
  } catch (err) {
    if (fs.existsSync(CACHE)) {
      const cached = JSON.parse(fs.readFileSync(CACHE, 'utf8'));
      // The getter is lost through JSON, so put it back.
      cached.plans = cached.plans.map((p) => normalisePlan(p.id, {
        label: p.label, description: p.description, nominalPrice: p.listPrice,
        promotionalPrice: p.promoPrice, sortOrder: p.sortOrder, archived: p.archived,
        lockedFeatures: p.locked, limits: p.rawLimits,
      }));
      return { ...cached, source: 'cache', note: `Firestore unreachable (${err.message}) — using the fetch cached ${cached.fetchedAt}` };
    }
    return {
      plans: seedPlans,
      promo: null,
      source: 'seed',
      note: `Firestore unreachable (${err.message}) and no cache — falling back to the compiled seeds, which may be stale`,
    };
  }
}

/* ------------------------------------------------------------------ */
/* copy helpers                                                        */
/* ------------------------------------------------------------------ */
/* Every sentence on the site that states a price, a tier name or which tiers
   include the AI assistant is built from these. Nothing about the catalogue is
   written out by hand twice — that is exactly how the site came to be quoting
   figures ten times too high. */

export const rupees = (n) => '₹' + Number(n).toLocaleString('en-IN');

/** What a tier costs today: its promotional price when one is set. */
export const priceNow = (p) => (p.promoPrice ?? p.listPrice ?? 0);
export const isFree = (p) => priceNow(p) === 0;
export const isDiscounted = (p) =>
  p.listPrice != null && p.promoPrice != null && p.promoPrice < p.listPrice;

export const priceLabel = (p) => (isFree(p) ? 'Free' : rupees(priceNow(p)) + '/mo');
export const listLabel = (p) => (p.listPrice == null ? '' : rupees(p.listPrice) + '/mo');

export const allFree = (plans) => plans.length > 0 && plans.every(isFree);

/** "₹99 to ₹999 a month", from whatever the console currently holds. */
export function listPriceRange(plans) {
  const prices = plans.map((p) => p.listPrice).filter((n) => typeof n === 'number');
  if (!prices.length) return '';
  const lo = Math.min(...prices), hi = Math.max(...prices);
  return lo === hi ? `${rupees(lo)} a month` : `${rupees(lo)} to ${rupees(hi)} a month`;
}

/* "MAX Tier" is the console's label; in a sentence it reads better without the
   redundant word, but the pricing table still shows the label verbatim. */
export const shortLabel = (p) => p.label.replace(/\s+Tier$/i, '');

export const andList = (items) =>
  items.length <= 1 ? items[0] || ''
  : items.slice(0, -1).join(', ') + ' and ' + items[items.length - 1];

export const aiTiers = (plans) => andList(plans.filter((p) => p.hasAi).map(shortLabel));
export const nonAiTiers = (plans) => andList(plans.filter((p) => !p.hasAi).map(shortLabel));

/** The tier to highlight: whatever the live promo grants, else the top one. */
export const featuredId = (plans, promo) =>
  (promo && plans.some((p) => p.id === promo.grantPlanId) && promo.grantPlanId) ||
  (plans.length ? plans[plans.length - 1].id : null);
