# Firestore security rules tests

Covers the workspace-takeover path these rules exist to close: a staff user
setting `role: 'admin'` on their own document made `isAdmin()` true, which
unlocked the admin branch of every other rule. It also pins the legitimate
flows (signup, staff provisioning, workspace switching) so tightening the
rules cannot silently break sign-in.

## Running

Needs a JDK 21+ on PATH (the emulator refuses older ones):

```bash
cd test/rules && npm install
JAVA_HOME=$(/usr/libexec/java_home -v 21+ 2>/dev/null || echo /opt/homebrew/opt/openjdk) \
  npx firebase emulators:exec --only firestore --project rules-test \
  "node firestore_rules_test.mjs"
```

Every test re-seeds first: an earlier version shared state between tests and
one test's write masked another's failure.
