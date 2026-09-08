/** Prints the tier catalogue the next build will publish. `npm run seo:plans` */
import { fetchPlanCatalog, rupees, priceLabel, listLabel, aiTiers, nonAiTiers, listPriceRange } from './plans.mjs';
import { plans as seeds } from './site.mjs';

const c = await fetchPlanCatalog(seeds);
console.log(`source: ${c.source} — ${c.note}\n`);
for (const p of c.plans) {
  console.log(
    `  ${p.label.padEnd(11)} list ${listLabel(p).padEnd(9)} now ${priceLabel(p).padEnd(9)} ` +
    `AI ${p.hasAi ? 'yes' : 'no '}  ${Object.entries(p.limits).map(([k, v]) => `${k}=${v}`).join('  ')}`
  );
}
console.log(`\n  range: ${listPriceRange(c.plans)}`);
console.log(`  AI on: ${aiTiers(c.plans)}   not on: ${nonAiTiers(c.plans)}`);
console.log(c.promo ? `  promo: "${c.promo.headline}" grants ${c.promo.grantPlanId} (${c.promo.claimedCount}/${c.promo.capCount}, advisory)` : '  promo: off');
