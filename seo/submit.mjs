/**
 * Tells IndexNow about every URL in the sitemap.
 *
 * IndexNow is a push protocol: Bing, Yandex, Seznam and Naver accept a list of
 * changed URLs directly, with no account and no verification beyond the key
 * file that seo/build.mjs writes to /<key>.txt. Google does not participate —
 * for Google you still have to submit the sitemap in Search Console, which
 * needs the site owner's login.
 *
 * Run after deploying (the key file has to be live first):
 *   node seo/submit.mjs
 */

import { site } from './site.mjs';

if (!site.indexNowKey) {
  console.error('No indexNowKey in seo/site.mjs.');
  process.exit(1);
}

const sitemapUrl = `${site.origin}/sitemap.xml`;
const sitemap = await (await fetch(sitemapUrl)).text();
const urlList = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);

if (!urlList.length) {
  console.error(`No URLs found in ${sitemapUrl}. Is the site deployed?`);
  process.exit(1);
}

// The key file must be reachable before submitting, or the whole batch is
// rejected as unverified.
const keyUrl = `${site.origin}/${site.indexNowKey}.txt`;
const keyRes = await fetch(keyUrl);
const keyBody = keyRes.ok ? (await keyRes.text()).trim() : '';
if (keyBody !== site.indexNowKey) {
  console.error(`Key file check failed: ${keyUrl} returned ${keyRes.status}.`);
  console.error('Deploy first, then run this.');
  process.exit(1);
}
console.log(`key      ${keyUrl} verified`);

const res = await fetch('https://api.indexnow.org/indexnow', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json; charset=utf-8' },
  body: JSON.stringify({
    host: new URL(site.origin).host,
    key: site.indexNowKey,
    keyLocation: keyUrl,
    urlList,
  }),
});

// 200 = accepted, 202 = accepted, key validation pending. Both are success.
console.log(`submit   ${urlList.length} URLs -> HTTP ${res.status} ${res.statusText}`);
if (res.status !== 200 && res.status !== 202) {
  console.error(await res.text());
  process.exit(1);
}
console.log('Done. Bing, Yandex, Seznam and Naver have the list.');
console.log('Google still needs the sitemap submitted in Search Console.');
