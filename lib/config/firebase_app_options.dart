import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

import '../firebase_options.dart' as smartshelf;
import '../firebase_options_gpb.dart' as gpb;
import 'flavor.dart';

/// [FirebaseOptions] for the brand this build was compiled for.
///
/// Both imports are FlutterFire CLI output and both are gitignored, for the
/// reason given in `lib/firebase_options.dart.example`: a clone gets the
/// `.example` placeholders and generates or copies the real ones. Regenerate
/// either with an explicit `--out`, so one never overwrites the other:
///
///     flutterfire configure --project=stockmanagement-27af8 \
///       --out=lib/firebase_options.dart
///     flutterfire configure --project=gpbstockinventory \
///       --out=lib/firebase_options_gpb.dart
///
/// Use this instead of `DefaultFirebaseOptions` directly — that name now
/// exists twice, and picking one by hand is how a build ends up talking to the
/// wrong tenant.
class FlavoredFirebaseOptions {
  const FlavoredFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    final brand = AppBrand.current;
    final options = switch (brand) {
      AppBrand.smartshelf => smartshelf.DefaultFirebaseOptions.currentPlatform,
      AppBrand.gpb => gpb.DefaultFirebaseOptions.currentPlatform,
    };

    // Cheap guard against the mistake this whole file exists to prevent:
    // regenerating one flavor's options against the other's project, which
    // otherwise shows up as data quietly landing in the wrong tenant.
    // The `.example` files carry deliberate placeholders and are exempt — a
    // fresh clone and CI run on those, and never reach a live project.
    assert(
      options.projectId.startsWith('CI_PLACEHOLDER') ||
          options.projectId == brand.firebaseProjectId,
      'Flavor "${brand.id}" expects Firebase project '
      '"${brand.firebaseProjectId}" but its options file names '
      '"${options.projectId}". One of the firebase_options files was '
      'generated against the wrong project.',
    );

    return options;
  }
}
