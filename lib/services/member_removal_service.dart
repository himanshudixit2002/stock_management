import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/workspace_member_model.dart';
import 'membership_access.dart';

/// Removing people from a workspace, and finding out whether you were removed.
class MemberRemovalService {
  MemberRemovalService({FirebaseFirestore? firestore})
    : _injectedFirestore = firestore;

  final FirebaseFirestore? _injectedFirestore;

  /// Resolved lazily so the class can be built in a test without Firebase.
  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _company(String companyId) =>
      _firestore.collection('companies').doc(companyId);

  /// Removes [uid] from [companyId], and only from [companyId].
  ///
  /// Three writes, committed as one batch so they land together or not at all:
  ///
  ///  * The member doc is deleted. It is the server-verified record of
  ///    belonging: the assistant and reporting backends authorise on it, and
  ///    switching back into a workspace requires it. This step used to be
  ///    best-effort, and a failure was swallowed while the rest of the
  ///    removal went ahead. The person then kept backend access and could
  ///    re-create their own user doc and walk straight back in.
  ///  * A removal record is written. It stops the person rejoining with a
  ///    code they already know. Only an invite issued after this moment lets
  ///    them back in (see joinCodeAdmits in firestore.rules).
  ///  * If this is the account's active workspace, the user doc is detached
  ///    (see [MembershipAccess.detachFields]) rather than deleted. That is
  ///    what makes the security rules refuse them at once, and what the
  ///    person's own app watches to sign them out of this workspace.
  ///
  /// An account that is active in another workspace is not readable here. The
  /// rules only let an admin read user docs that point at the admin's own
  /// workspace. Its user doc is left alone: losing the member doc already stops
  /// it switching back in.
  Future<void> removeMember({
    required String companyId,
    required String uid,
    String removedByUid = '',
    String name = '',
    String email = '',
  }) async {
    final cid = companyId.trim();
    if (cid.isEmpty || uid.isEmpty) {
      throw StateError('No workspace or member to remove.');
    }

    final userRef = _firestore.collection('users').doc(uid);
    Map<String, dynamic>? userData;
    try {
      userData = (await userRef.get()).data();
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
    final detach = (userData != null && userData['companyId'] == cid)
        ? MembershipAccess.detachFields(userData, cid)
        : null;

    final batch = _firestore.batch();
    batch.delete(_company(cid).collection('members').doc(uid));
    batch.set(_company(cid).collection('removedMembers').doc(uid), {
      'uid': uid,
      'name': name,
      'email': email,
      'removedBy': removedByUid,
      // The rules require the server's clock here; see removedMembers.
      'removedAt': FieldValue.serverTimestamp(),
    });
    if (detach != null) batch.update(userRef, detach);
    await batch.commit();
  }

  /// Whether an admin removed [uid] from [companyId].
  ///
  /// The rules let an account read its own removal record, so the app can tell
  /// someone why a code or a switch was refused. Any failure reads as "not
  /// removed": this only chooses which message to show.
  Future<bool> wasRemovedFrom({
    required String companyId,
    required String uid,
  }) async {
    if (companyId.isEmpty || uid.isEmpty) return false;
    try {
      final snap = await _company(
        companyId,
      ).collection('removedMembers').doc(uid).get();
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  /// Everyone holding a member doc in [companyId].
  Stream<List<WorkspaceMember>> watchMembers(String companyId) {
    if (companyId.isEmpty) return Stream.value(const []);
    return _company(companyId)
        .collection('members')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => WorkspaceMember.fromMap(d.id, d.data()))
              .toList(),
        );
  }
}
