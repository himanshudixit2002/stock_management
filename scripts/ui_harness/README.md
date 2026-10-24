# UI harness

Runs the web app against the local Firebase emulators with a demo workspace,
and screenshots the main screens as the owner and as a staff member, at a phone
size (390x844) and a desktop size (1440x900). It also reports errors the page
logs while it runs.

It does not catch overflow: Flutter only reports a `RenderFlex overflowed` in
debug builds, and this runs a release build. The widget tests under
`test/screens/` pump screens at phone widths and large text for that.

Nothing here touches a real Firebase project. The app switches to the emulators
only when built with `--dart-define=USE_FIREBASE_EMULATORS=true` (see
`lib/config/dev_emulators.dart`), and then uses the `demo-smartshelf` project,
which only the emulators accept.

## Run it

From the repo root:

```bash
# 1. Placeholder Firebase config, if you have no real one (same as CI)
cp lib/firebase_options.dart.example lib/firebase_options.dart
cp lib/firebase_options_gpb.dart.example lib/firebase_options_gpb.dart

# 2. A web build pointed at the emulators, with CanvasKit bundled locally
flutter build web --no-web-resources-cdn --dart-define=USE_FIREBASE_EMULATORS=true

# 3. Emulators, with the repo's real firestore.rules (leave running)
firebase emulators:start --only auth,firestore --project demo-smartshelf

# 4. In another terminal: demo data, then screenshots
cd scripts/ui_harness
npm install
node seed.mjs
node shoot.mjs --label=before
```

Screenshots land in `scripts/ui_harness/screenshots/<label>/`, with a
`report.json` listing any errors per screen. Pass `--only=home,pos` to capture
a subset, `--scrolls=2` for two more shots further down each screen, and
`--tour` to leave the first-run tour on Home (it is skipped by default).

Playwright is loaded from a local or a global install. If you have neither:
`npm i -g playwright && npx playwright install chromium`.

## Signing in as the demo users

The seed creates `owner@demo.test` (the workspace owner) and
`staff@demo.test` (default Staff role), both with the password in `seed.mjs`.
Sign in as the owner first: the app seeds the workspace's roles on the owner's
first sign-in, exactly as it does for a new signup.

The same build also works for clicking around by hand: serve `build/web` with
any static server and sign in with those accounts.
