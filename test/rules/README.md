# Firestore security rules tests

Covers the workspace-takeover paths these rules exist to close:

- a staff user setting `role: 'admin'` on their own document made `isAdmin()`
  true, which unlocked the admin branch of every other rule;
- the same escalation through `roleId`, which the `role` guard did not cover —
  permissions resolve through `companies/{cid}/roles/{roleId}`, and the seeded
  admin/owner role docs carry every permission, so a viewer could grant
  themselves everything in one self-write while `role` stayed `'staff'`;
- delete-then-recreate of your own user doc pointed at someone else's
  `companyId`, which `create` never constrained — a complete cross-tenant read.

It also pins the legitimate flows (signup, staff provisioning, workspace
switching, join codes) so tightening the rules cannot silently break sign-in.

## Running

Needs a JDK 21+ (the emulator refuses older ones):

```bash
cd test/rules && npm install
JAVA_HOME=/opt/homebrew/opt/openjdk PATH="/opt/homebrew/opt/openjdk/bin:$PATH" \
  firebase emulators:exec --only firestore --project rules-test \
  "node firestore_rules_test.mjs"
```

Two gotchas that cost time before:

- Use the `firebase` binary directly, **not** `npx firebase`. Under `npx` the
  CLI resolved a different `java` and reported the system JDK 17 even with a 21+
  JDK first on `PATH`, failing with "no longer supports Java version before 21".
- `/usr/libexec/java_home -v 21+` returns nothing on a Homebrew-only install.
  Homebrew's current `openjdk` lives at `/opt/homebrew/opt/openjdk` while
  `openjdk@17` owns the default `java` on `PATH`, so point `JAVA_HOME` at the
  unversioned formula explicitly, as above.

Every test re-seeds first: an earlier version shared state between tests and
one test's write masked another's failure.

## `settings_write_semantics.mjs`

A second suite in this directory, run the same way (`npm run test:semantics`,
or `test:all` for both). It is not about rules — it pins Firestore's dotted-key
behaviour, which a whole class of settings bugs turned on:

> A dotted string key is a field **path** in `update()`, and a literal field
> **name** in `set()`.

Every settings write in the app was `set({'settings.locations': …}, merge)`,
which therefore created a top-level field genuinely called
`"settings.locations"` and never touched the nested map the providers read back.
Nothing errored — the providers update their own state optimistically — so each
change appeared to work and was gone on the next cold start.

It lives here rather than in `flutter test` because **`fake_cloud_firestore`
does not reproduce the distinction**: it nests a dotted key in `set()` too, so
the bug is invisible to it. The emulator is the real engine. The Dart-side unit
tests in `test/services/company_settings_writer_test.dart` cover the parts the
fake does model.
