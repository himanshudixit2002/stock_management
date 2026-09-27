import 'package:flutter/services.dart' show appFlavor;

/// Which brand — and therefore which Firebase project — this build talks to.
///
/// One codebase, two independent backends. Nothing is shared between them: a
/// company created in one is invisible to the other, because they are separate
/// Firebase projects with separate Firestore databases and separate auth user
/// pools.
///
/// Two inputs select it, because neither one covers every platform:
///
///  * `--flavor` (Android, iOS). This is the one that matters on a device:
///    Gradle uses it to pick the product flavor, which is what decides the
///    `applicationId` and bakes the matching `google-services.json` into the
///    APK. Flutter mirrors the value into [appFlavor].
///  * `--dart-define=FLAVOR=` (everywhere, and the *only* option on web —
///    `flutter build web` does not accept `--flavor` at all).
///
/// When both are present [appFlavor] wins, because by the time Dart runs on a
/// device the native config is already fixed. A dart-define that disagreed
/// would hand `Firebase.initializeApp` one project's options while the
/// platform plugins read another's — signing in against project A and reading
/// Firestore from project B. That is a build-command mistake rather than a
/// runtime condition, so it throws here instead of being quietly resolved.
enum AppBrand {
  /// The original app: smartshelfkart.com, `com.stockmanager.stock_management`.
  smartshelf(id: 'smartshelf', firebaseProjectId: 'stockmanagement-27af8'),

  /// The parallel deployment: `com.gbp.android`.
  gpb(id: 'gpb', firebaseProjectId: 'gpbstockinventory');

  const AppBrand({required this.id, required this.firebaseProjectId});

  /// Matches the Gradle product flavor name and the `--dart-define=FLAVOR`
  /// value. Keep the three spellings identical.
  final String id;

  /// Cross-checked against the `FirebaseOptions` actually selected, so a
  /// `firebase_options` file regenerated against the wrong project fails an
  /// assert at startup instead of silently writing to the other tenant.
  final String firebaseProjectId;

  static const String _dartDefine = String.fromEnvironment('FLAVOR');

  /// The brand this binary was built for. Defaults to [AppBrand.smartshelf]
  /// when neither input is given, which keeps every existing build command —
  /// `flutter run`, `flutter build web` — pointed where it always was.
  static final AppBrand current = _resolve();

  static AppBrand _resolve() {
    final native = appFlavor;
    final defined = _dartDefine.isEmpty ? null : _dartDefine;

    if (native != null && defined != null && native != defined) {
      throw StateError(
        'Flavor mismatch: built with --flavor=$native but '
        '--dart-define=FLAVOR=$defined. The native Firebase config is already '
        'fixed to "$native"; drop the dart-define, or make the two agree.',
      );
    }

    final id = native ?? defined;
    if (id == null) return AppBrand.smartshelf;

    return AppBrand.values.firstWhere(
      (brand) => brand.id == id,
      orElse: () => throw StateError(
        'Unknown flavor "$id". Known flavors: '
        '${AppBrand.values.map((b) => b.id).join(', ')}.',
      ),
    );
  }
}
