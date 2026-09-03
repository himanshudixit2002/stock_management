// Ground truth for the dotted-key bug, against the real Firestore engine.
//
// `fake_cloud_firestore` does NOT reproduce this: it nests a dotted key in
// set() as well as update(), so the Dart unit tests cannot show the defect.
// The emulator is the real implementation, so this is what actually pins the
// behaviour CompanySettingsWriter is built around.
//
// Run:
//   cd test/rules && JAVA_HOME=/opt/homebrew/opt/openjdk \
//     PATH="/opt/homebrew/opt/openjdk/bin:$PATH" \
//     firebase emulators:exec --only firestore --project rules-test \
//     "node settings_write_semantics.mjs"

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, getDoc, deleteField } from 'firebase/firestore';

const env = await initializeTestEnvironment({
  projectId: 'rules-test',
  firestore: { rules: 'rules_version="2";service cloud.firestore{match /databases/{d}/documents{match /{p=**}{allow read,write:if true;}}}', host: '127.0.0.1', port: 8080 },
});

let pass = 0, fail = 0;
function check(name, ok, detail = '') {
  if (ok) { console.log(`  PASS  ${name}`); pass++; }
  else { console.log(`  FAIL  ${name}\n        ${detail}`); fail++; }
}

const db = (await env.unauthenticatedContext()).firestore();
const ref = () => doc(db, 'companies/c1');

console.log('\n--- THE BUG: set() takes a dotted key literally ---');
await env.clearFirestore();
await setDoc(ref(), { settings: {} });
await setDoc(ref(), { 'settings.pricingEnabled': false }, { merge: true });
let data = (await getDoc(ref())).data();
check(
  'set() creates a top-level field literally named "settings.pricingEnabled"',
  data['settings.pricingEnabled'] === false,
  JSON.stringify(data),
);
check(
  'the nested settings map the app reads is untouched',
  data.settings.pricingEnabled === undefined,
  JSON.stringify(data),
);

console.log('\n--- THE FIX: update() reads it as a field path ---');
await env.clearFirestore();
await setDoc(ref(), { settings: {} });
await updateDoc(ref(), { 'settings.pricingEnabled': false });
data = (await getDoc(ref())).data();
check(
  'update() writes into the nested map',
  data.settings.pricingEnabled === false,
  JSON.stringify(data),
);
check(
  'and creates no flat field',
  data['settings.pricingEnabled'] === undefined,
  JSON.stringify(data),
);

console.log('\n--- update() is field-scoped ---');
await env.clearFirestore();
await setDoc(ref(), { settings: { pricingEnabled: true, vendorsEnabled: true } });
await updateDoc(ref(), { 'settings.pricingEnabled': false });
data = (await getDoc(ref())).data();
check(
  'a sibling key survives the write',
  data.settings.pricingEnabled === false && data.settings.vendorsEnabled === true,
  JSON.stringify(data),
);

console.log('\n--- THE MIGRATION: fold a stranded value home and delete it ---');
await env.clearFirestore();
// Reproduce a workspace as the old write path left it.
await setDoc(ref(), { companyName: 'Acme', settings: {} });
await setDoc(ref(), { 'settings.locations': ['Bay 3'] }, { merge: true });
data = (await getDoc(ref())).data();
check('precondition: value is stranded flat', Array.isArray(data['settings.locations']));

// The repair, exactly as CompanySettingsWriter.healFlatKeys performs it: the
// path form to write it home, and a single-segment FieldPath to delete the
// literal field. A plain string for both would collide and the delete would
// swallow the write.
const { FieldPath } = await import('firebase/firestore');
await updateDoc(
  ref(),
  'settings.locations', ['Bay 3'],
  new FieldPath('settings.locations'), deleteField(),
);
data = (await getDoc(ref())).data();
check('value is now in the nested map', JSON.stringify(data.settings.locations) === '["Bay 3"]', JSON.stringify(data));
check('the flat field is gone', data['settings.locations'] === undefined, JSON.stringify(data));
check('unrelated fields untouched', data.companyName === 'Acme', JSON.stringify(data));

console.log('\n--- MIGRATION: a properly nested value wins over a stranded one ---');
await env.clearFirestore();
await setDoc(ref(), { settings: { locations: ['Nested'] } });
await setDoc(ref(), { 'settings.locations': ['Stranded'] }, { merge: true });
data = (await getDoc(ref())).data();
check(
  'precondition: both exist side by side',
  JSON.stringify(data.settings.locations) === '["Nested"]' &&
    JSON.stringify(data['settings.locations']) === '["Stranded"]',
  JSON.stringify(data),
);
// healFlatKeys skips the write when the nested key is already populated — that
// value is what the app has been reading and showing — and only drops the junk.
await updateDoc(ref(), new FieldPath('settings.locations'), deleteField());
data = (await getDoc(ref())).data();
check(
  'the nested value is kept and the stranded one dropped',
  JSON.stringify(data.settings.locations) === '["Nested"]' &&
    data['settings.locations'] === undefined,
  JSON.stringify(data),
);

console.log('\n--- MIGRATION: a deeper path lands at the right depth ---');
await env.clearFirestore();
await setDoc(ref(), { settings: {} });
await setDoc(ref(), { 'settings.billing.currencySymbol': '$' }, { merge: true });
await updateDoc(
  ref(),
  'settings.billing.currencySymbol', '$',
  new FieldPath('settings.billing.currencySymbol'), deleteField(),
);
data = (await getDoc(ref())).data();
check(
  'currencySymbol is nested under settings.billing',
  data.settings.billing.currencySymbol === '$',
  JSON.stringify(data),
);
check(
  'the flat field is gone',
  data['settings.billing.currencySymbol'] === undefined,
  JSON.stringify(data),
);

console.log(`\n${pass} passed, ${fail} failed`);
await env.cleanup();
process.exit(fail === 0 ? 0 : 1);
