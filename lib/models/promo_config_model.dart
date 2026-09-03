import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/parse_helpers.dart';
import 'company_plan_model.dart';

/// The founding-member offer shown on the signed-out screens.
///
/// Lives in `publicConfig/promo`, which is world-readable — the register and
/// login screens read it before anyone has authenticated — and writable only by
/// a platform admin, so the copy and the cap are changed from the console
/// rather than by a redeploy.
///
/// [claimedCount] is **advisory**. Nothing counts signups atomically: the value
/// is whatever a platform admin last synced from the workspace count. The copy
/// must not promise that the offer ends when it reaches [capCount] — see
/// [isFull], which changes the message but grants nothing different.
class PromoConfig {
  const PromoConfig({
    this.enabled = false,
    this.headline = 'Founding member offer',
    this.subtext =
        'The first 1000 workspaces get the full MAX plan — every feature, '
        'no limits — free.',
    this.fullHeadline = 'The founding cohort is full',
    this.fullSubtext =
        'Signing up still gets you the full MAX plan while it lasts.',
    this.capCount = 1000,
    this.claimedCount = 0,
    this.grantPlanId = PlanCatalog.maxId,
    this.updatedAt,
  });

  final bool enabled;
  final String headline;
  final String subtext;
  final String fullHeadline;
  final String fullSubtext;
  final int capCount;
  final int claimedCount;

  /// The tier a new signup is put on. Only [PlanCatalog.maxId] is actually
  /// writable by the client at company-create time — the security rules permit
  /// nothing else — so this exists to document intent, not to widen it.
  final String grantPlanId;

  final DateTime? updatedAt;

  bool get isFull => capCount > 0 && claimedCount >= capCount;

  /// How far through the cohort, 0..1, or null when nothing is capped.
  double? get progress {
    if (capCount <= 0) return null;
    final value = claimedCount / capCount;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }

  int get remaining {
    final left = capCount - claimedCount;
    return left < 0 ? 0 : left;
  }

  String get activeHeadline => isFull ? fullHeadline : headline;
  String get activeSubtext => isFull ? fullSubtext : subtext;

  factory PromoConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PromoConfig();
    const fallback = PromoConfig();
    return PromoConfig(
      enabled: map['enabled'] == true,
      headline: safeString(map['headline'], fallback.headline),
      subtext: safeString(map['subtext'], fallback.subtext),
      fullHeadline: safeString(map['fullHeadline'], fallback.fullHeadline),
      fullSubtext: safeString(map['fullSubtext'], fallback.fullSubtext),
      capCount: _asInt(map['capCount']) ?? fallback.capCount,
      claimedCount: _asInt(map['claimedCount']) ?? 0,
      grantPlanId: safeString(map['grantPlanId'], PlanCatalog.maxId),
      updatedAt: map['updatedAt'] == null
          ? null
          : safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'headline': headline,
    'subtext': subtext,
    'fullHeadline': fullHeadline,
    'fullSubtext': fullSubtext,
    'capCount': capCount,
    'claimedCount': claimedCount,
    'grantPlanId': grantPlanId,
    'updatedAt': Timestamp.now(),
  };

  PromoConfig copyWith({
    bool? enabled,
    String? headline,
    String? subtext,
    String? fullHeadline,
    String? fullSubtext,
    int? capCount,
    int? claimedCount,
    String? grantPlanId,
  }) {
    return PromoConfig(
      enabled: enabled ?? this.enabled,
      headline: headline ?? this.headline,
      subtext: subtext ?? this.subtext,
      fullHeadline: fullHeadline ?? this.fullHeadline,
      fullSubtext: fullSubtext ?? this.fullSubtext,
      capCount: capCount ?? this.capCount,
      claimedCount: claimedCount ?? this.claimedCount,
      grantPlanId: grantPlanId ?? this.grantPlanId,
      updatedAt: updatedAt,
    );
  }

  static int? _asInt(dynamic value) => value is num ? value.toInt() : null;
}
