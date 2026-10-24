import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Local Firebase emulators, for development and for `scripts/ui_harness`.
///
/// Off unless the build passes `--dart-define=USE_FIREBASE_EMULATORS=true`.
/// Release builds never do, so nothing here runs for real users and the
/// constant folds the branches away.
///
/// The emulators need no credentials, so the app runs against a `demo-`
/// project instead of the flavor's real one. No real Firebase project can have
/// that prefix, so a request that somehow escaped the emulators could not land
/// in production data.
class DevEmulators {
  const DevEmulators._();

  static const bool enabled = bool.fromEnvironment('USE_FIREBASE_EMULATORS');

  /// Where the emulators listen. `127.0.0.1` rather than `localhost`: the
  /// emulators bind IPv4 by default, and a browser that resolves `localhost`
  /// to `::1` first gets a refused connection that Firebase Auth reports as
  /// `auth/network-request-failed`. On an Android emulator the Firebase SDKs
  /// map this to the host machine (10.0.2.2) automatically.
  static const String host = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );

  static const int authPort = 9099;
  static const int firestorePort = 8080;

  /// Must match `PROJECT_ID` in scripts/ui_harness/seed.mjs.
  static const FirebaseOptions options = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:web:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-smartshelf',
    authDomain: 'demo-smartshelf.firebaseapp.com',
  );

  /// Points Auth and Firestore at the emulators. Call straight after
  /// `Firebase.initializeApp`, before anything signs in or reads data.
  static Future<void> connect() async {
    await FirebaseAuth.instance.useAuthEmulator(host, authPort);
    FirebaseFirestore.instance.useFirestoreEmulator(host, firestorePort);
  }
}
