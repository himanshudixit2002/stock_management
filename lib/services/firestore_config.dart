import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// The single place Firestore's [Settings] are applied.
///
/// Order matters more than it looks. `cloud_firestore_web` reads `settings`
/// exactly once — lazily, when the JS `Firestore` object is first created — and
/// silently discards any assignment made after that. This used to live in
/// [DatabaseService]'s constructor, which does not run until some provider
/// happens to need it, long after [PlanCatalogProvider.start] has already
/// touched `FirebaseFirestore.instance` and started the client. So on web the
/// settings had never taken effect at all: the deployed app was running on the
/// plain default configuration, with no IndexedDB database to show for the
/// `persistenceEnabled: true` it thought it had asked for.
///
/// Call this immediately after `Firebase.initializeApp`, before anything reads
/// `FirebaseFirestore.instance`.
class FirestoreConfig {
  const FirestoreConfig._();

  static bool _applied = false;

  /// Applies the settings once. Safe to call again; later calls do nothing,
  /// which matters because the web bootstrap can be retried from the error
  /// screen and re-assigning settings after the client has started throws.
  static void apply() {
    if (_applied) return;
    _applied = true;

    // Web deliberately keeps the in-memory cache. That is what the app has
    // actually been running on all along, so leaving it alone here is the
    // no-behaviour-change option; switching web to IndexedDB persistence is a
    // separate decision, not a side effect of fixing the ordering. It would
    // also need care: the plugin selects the single-tab manager, which fails
    // the second tab with `failed-precondition`.
    //
    // Transport is left at the SDK default on purpose. Firebase JS 11.x already
    // defaults `experimentalAutoDetectLongPolling` to true, so setting it here
    // would change nothing. If a browser turns out to need long polling
    // outright, that is `webExperimentalForceLongPolling: true` — a deliberate
    // trade, since it costs every user a chattier transport.
    FirebaseFirestore.instance.settings = kIsWeb
        ? const Settings(persistenceEnabled: false)
        : const Settings(persistenceEnabled: true);
  }
}
