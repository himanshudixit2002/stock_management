const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const { initializeApp } = require("firebase-admin/app");
initializeApp();

setGlobalOptions({ region: "us-central1" });

/**
 * Triggered when a new user document is created in the users collection.
 * No longer notifies anyone — all signups are immediately usable.
 */
exports.onNewUserRegistration = onDocumentCreated(
  "users/{userId}",
  async () => {
    // No-op: approval flow removed; all users can use the app immediately.
  }
);
