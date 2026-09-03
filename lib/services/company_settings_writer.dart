import 'package:cloud_firestore/cloud_firestore.dart';

/// Writes into the nested `settings` map on a `companies/{id}` document.
///
/// This exists because of one easily-missed Firestore rule: **a dotted string
/// key is a field path in `update()`, and a literal field name in `set()`.**
///
/// Every settings write in the app used to be
/// `set({'settings.locations': ...}, SetOptions(merge: true))`, which created a
/// top-level field genuinely named `"settings.locations"` and never touched the
/// nested `settings` map the providers read back. Nothing failed: the providers
/// update their own state optimistically and notify, so the change appeared on
/// screen and was gone on the next cold start. Feature toggles, locations,
/// sizes, companies and the whole billing configuration were all affected.
///
/// Routing writes through here keeps that distinction in one place, next to the
/// explanation, rather than in nineteen call sites that each looked correct.
class CompanySettingsWriter {
  const CompanySettingsWriter(this.doc);

  final DocumentReference<Map<String, dynamic>> doc;

  /// Sets `settings.<key>` (or `settings.<prefix>.<key>`) to [value].
  Future<void> write(String key, Object? value, {String prefix = ''}) =>
      writeAll({key: value}, prefix: prefix);

  /// Merges [fields] into `settings` (or `settings.<prefix>`).
  ///
  /// Field-scoped, so concurrent writes to different settings do not clobber
  /// each other the way re-sending the whole map would. `FieldValue` sentinels
  /// such as `arrayUnion` pass through unchanged.
  Future<void> writeAll(
    Map<String, Object?> fields, {
    String prefix = '',
  }) async {
    if (fields.isEmpty) return;
    final head = prefix.isEmpty ? 'settings' : 'settings.$prefix';
    try {
      await doc.update({
        for (final entry in fields.entries) '$head.${entry.key}': entry.value,
      });
    } on FirebaseException catch (e) {
      // update() requires the document to exist. A workspace whose company doc
      // has not been created yet still needs its settings to land, so re-send
      // them as a properly *nested* map — which set() does interpret correctly.
      if (e.code != 'not-found') rethrow;
      await doc.set({
        'settings': prefix.isEmpty ? fields : {prefix: fields},
      }, SetOptions(merge: true));
    }
  }

  /// Folds values stranded in top-level `settings.*` fields back into `settings`.
  ///
  /// [data] is the company document as already read by the caller, so this
  /// costs no extra read on the common path where there is nothing to heal.
  /// Returns the repaired nested map, or null when nothing needed doing (or the
  /// repair could not be written).
  ///
  /// Idempotent — the flat keys are deleted as they are folded in, so a second
  /// run finds nothing. Where both a flat and a nested value exist the nested
  /// one wins: that is the value the app has actually been reading and showing.
  Future<Map<String, dynamic>?> healFlatKeys(Map<String, dynamic> data) async {
    final flatKeys = data.keys
        .where((k) => k.startsWith('settings.') && k.length > 'settings.'.length)
        .toList();
    if (flatKeys.isEmpty) return null;

    final nested = Map<String, dynamic>.from(
      data['settings'] as Map<String, dynamic>? ?? const {},
    );
    // Keys are Objects, not Strings, because the two halves of this repair need
    // the *opposite* interpretations of the same text:
    //
    //   'settings.locations'          -> a field PATH: settings -> locations
    //   FieldPath(['settings.locations']) -> the single top-level field whose
    //                                        NAME contains a dot
    //
    // The flat field can only be addressed the second way; writing the value
    // home can only be done the first way. Using a plain string for both would
    // make them the same key, and the delete would simply eat the write.
    final updates = <Object, Object?>{};
    for (final flat in flatKeys) {
      final path = flat.substring('settings.'.length);
      final head = path.split('.').first;
      if (!nested.containsKey(head)) {
        // The path form, so a nested key such as
        // 'settings.billing.currencySymbol' lands at the right depth.
        updates[flat] = data[flat];
        _assignPath(nested, path, data[flat]);
      }
      updates[FieldPath([flat])] = FieldValue.delete();
    }

    try {
      await doc.update(updates);
    } catch (_) {
      // Offline, or a member without write access to the company doc. Reading
      // still works from whatever the nested map already holds.
      return null;
    }
    return nested;
  }

  /// Writes [value] at dotted [path] inside [target], creating maps as needed.
  static void _assignPath(
    Map<String, dynamic> target,
    String path,
    Object? value,
  ) {
    final parts = path.split('.');
    var cursor = target;
    for (var i = 0; i < parts.length - 1; i++) {
      final next = cursor[parts[i]];
      final child = next is Map<String, dynamic>
          ? Map<String, dynamic>.from(next)
          : <String, dynamic>{};
      cursor[parts[i]] = child;
      cursor = child;
    }
    cursor[parts.last] = value;
  }
}
