/**
 * Screenshots key screens of the web build, signed in as each demo user, at a
 * phone and a desktop size. Also records errors the page logs (exceptions,
 * failed layouts). Overflow warnings ("RenderFlex overflowed") are debug-only
 * in Flutter, so a release build never prints them: check overflow with the
 * widget tests under test/screens, which pump screens at phone widths.
 *
 * Needs: the emulators running and seeded (seed.mjs), and a web build made with
 *   flutter build web --no-web-resources-cdn --dart-define=USE_FIREBASE_EMULATORS=true
 *
 * Usage:
 *   node shoot.mjs                       # all users, sizes and screens
 *   node shoot.mjs --label=before        # write into screenshots/before/
 *   node shoot.mjs --only=home,invoices  # a subset of screens
 *   node shoot.mjs --scrolls=2           # also 2 shots further down each page
 *   node shoot.mjs --tour                # leave the first-run tour on Home
 *
 * The page never needs the internet: the Firebase JS SDK, which the web plugin
 * would fetch from www.gstatic.com, is served from node_modules/firebase, and
 * every other outside request is refused.
 */

import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { PASSWORD, USERS } from './seed.mjs';

const require = createRequire(import.meta.url);
// Resolved through `require` so a global Playwright install works as well as a
// local one (npm i -g playwright && npx playwright install chromium).
const { chromium } = require('playwright');

const here = path.dirname(fileURLToPath(import.meta.url));
const buildDir = path.resolve(here, '../../build/web');
const firebaseJsDir = path.dirname(require.resolve('firebase/package.json'));

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => a.replace(/^--/, '').split('=')),
);
const label = args.label ?? 'current';
const only = args.only ? new Set(args.only.split(',')) : null;
const outDir = path.join(here, 'screenshots', label);
const scrolls = Number(args.scrolls ?? 0);
const keepTour = 'tour' in args;

/** Screens to capture: a name, and the route pushed after Home has loaded. */
const SCREENS = [
  ['home', null],
  ['invoices', '/billing/invoices'],
  ['create-invoice', '/billing/invoices/create'],
  ['pos', '/pos/fast'],
  ['reports', '/reports'],
  ['dashboard', '/dashboard'],
  ['settings', '/settings'],
  ['customers', '/customers'],
  ['users', '/users'],
  ['company', '/company-switcher'],
  ['profile', '/profile'],
  ['features', '/settings/features'],
  ['home-layout', '/settings/home-customization'],
  ['billing-settings', '/billing/settings'],
  ['search', '/search'],
].filter(([name]) => !only || only.has(name));

const SIZES = [
  { name: 'phone', viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 },
  { name: 'desktop', viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 },
];

const TYPES = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png',
  '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.otf': 'font/otf', '.ttf': 'font/ttf',
  '.css': 'text/css', '.txt': 'text/plain', '.bin': 'application/octet-stream',
};

function serve(dir) {
  const server = http.createServer((req, res) => {
    const urlPath = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    let file = path.join(dir, urlPath);
    if (!file.startsWith(dir) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      file = path.join(dir, 'index.html');
    }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] ?? 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

async function openApp(browser, size, origin) {
  const context = await browser.newContext({
    viewport: size.viewport,
    deviceScaleFactor: size.deviceScaleFactor,
  });
  const page = await context.newPage();
  if (!keepTour) {
    // shared_preferences on the web is localStorage with a "flutter." prefix.
    await page.addInitScript(() => {
      localStorage.setItem('flutter.feature_tour_completed', 'true');
    });
  }
  // Registered first, so it is matched last: refuse anything not served here.
  await page.route(/^https?:\/\/(?!127\.0\.0\.1|localhost)/, (route) => route.abort());
  await page.route(/^https:\/\/www\.gstatic\.com\/firebasejs\/[^/]+\/(firebase-[a-z-]+\.js)$/, (route) => {
    const name = route.request().url().split('/').pop();
    route.fulfill({
      path: path.join(firebaseJsDir, name),
      contentType: 'text/javascript',
      headers: { 'Access-Control-Allow-Origin': '*' },
    });
  });
  const problems = [];
  // The Auth SDK logs this exactly when the app calls useAuthEmulator. Signing
  // in any earlier would create an Auth instance pointed at production.
  let emulatorReady;
  const ready = new Promise((resolve) => { emulatorReady = resolve; });
  page.on('console', (msg) => {
    const text = msg.text();
    if (text.includes('using the Auth Emulator')) emulatorReady();
    if (/overflowed|RenderFlex|was not laid out|Exception/i.test(text)) problems.push(text.split('\n')[0]);
  });
  page.on('pageerror', (err) => problems.push(`pageerror: ${err.message}`));
  await page.goto(`${origin}/`);
  await Promise.race([
    ready,
    new Promise((_, reject) => setTimeout(() => reject(new Error('The app never connected to the Auth emulator. Was it built with --dart-define=USE_FIREBASE_EMULATORS=true?')), 90_000)),
  ]);
  await page.waitForTimeout(1500);
  return { context, page, problems };
}

async function signIn(page, email) {
  await page.evaluate(
    async ({ email, password }) => {
      const a = window.firebase_auth;
      await a.signInWithEmailAndPassword(a.getAuth(), email, password);
    },
    { email, password: PASSWORD },
  );
  // Home binds its providers in phases; give the first ones time to land.
  await page.waitForTimeout(7000);
}

async function main() {
  if (!fs.existsSync(path.join(buildDir, 'index.html'))) {
    throw new Error(`No web build at ${buildDir}. See README.md.`);
  }
  fs.mkdirSync(outDir, { recursive: true });
  const server = await serve(buildDir);
  const origin = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch();
  const report = [];
  try {
    // The owner goes first: their first sign-in seeds the workspace's roles.
    for (const who of ['owner', 'staff']) {
      for (const size of SIZES) {
        const { context, page, problems } = await openApp(browser, size, origin);
        await signIn(page, USERS[who].email);
        for (const [name, route] of SCREENS) {
          problems.length = 0;
          if (route) {
            await page.evaluate((r) => { window.location.hash = r; }, route);
            await page.waitForTimeout(3500);
          }
          const file = path.join(outDir, `${size.name}-${who}-${name}.png`);
          await page.screenshot({ path: file });
          // Flutter paints only the viewport, so further down means scrolling.
          for (let i = 1; i <= scrolls; i++) {
            const { width, height } = size.viewport;
            await page.mouse.move(width / 2, height / 2);
            await page.mouse.wheel(0, height * 0.8);
            await page.waitForTimeout(900);
            await page.screenshot({ path: file.replace(/\.png$/, `-${i + 1}.png`) });
          }
          report.push({ who, size: size.name, screen: name, problems: [...new Set(problems)] });
          if (route) {
            await page.evaluate(() => window.history.back());
            await page.waitForTimeout(1500);
          }
        }
        await context.close();
      }
    }
  } finally {
    await browser.close();
    server.close();
  }
  fs.writeFileSync(path.join(outDir, 'report.json'), JSON.stringify(report, null, 2));
  const bad = report.filter((r) => r.problems.length);
  for (const r of bad) console.log(`${r.size}/${r.who}/${r.screen}:\n  ${r.problems.join('\n  ')}`);
  console.log(`${report.length} screenshots in ${outDir}; ${bad.length} with layout errors.`);
}

await main();
