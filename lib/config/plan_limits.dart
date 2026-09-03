import '../models/company_plan_model.dart';

/// How a workspace stands against one of its plan's caps.
enum PlanLimitState {
  /// Comfortably inside the cap, or not capped at all.
  ok,

  /// At or past 80% of the cap — worth warning about before it bites.
  warning,

  /// At or past the cap. The next write of this kind is refused.
  blocked,
}

/// One cap, measured against current usage.
class PlanLimitResult {
  const PlanLimitResult({
    required this.key,
    required this.current,
    required this.limit,
    required this.state,
  });

  final String key;
  final int current;

  /// Null when nothing caps this key.
  final int? limit;
  final PlanLimitState state;

  bool get isCapped => limit != null;
  bool get isBlocked => state == PlanLimitState.blocked;

  /// 0..1 against the cap, or null when uncapped. Clamped so an over-limit
  /// workspace does not overflow a progress bar.
  double? get fraction {
    final cap = limit;
    if (cap == null || cap <= 0) return null;
    final value = current / cap;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }

  String get label => PlanLimitKeys.labelOf(key);

  /// "12 / 250", or "12" when uncapped.
  String get usageText => limit == null ? '$current' : '$current / $limit';
}

/// Thrown when a write would take a workspace past its plan's cap.
///
/// This is a product guardrail, not a security boundary. Firestore rules cannot
/// count documents, so the cap is enforced here at the write path — a
/// determined client could bypass it. Enforcing it server-side would mean a
/// Cloud Function maintaining usage counters that the rules can `get()`.
class PlanLimitException implements Exception {
  const PlanLimitException({
    required this.key,
    required this.limit,
    required this.planLabel,
  });

  final String key;
  final int limit;
  final String planLabel;

  String get message =>
      '${PlanLimitKeys.labelOf(key)} limit reached. The $planLabel plan allows '
      '$limit. Ask your platform administrator to raise the limit or move this '
      'workspace to a higher plan.';

  @override
  String toString() => message;
}

/// Plan caps, measured and enforced.
class PlanLimits {
  PlanLimits._();

  /// Usage at or above this fraction of a cap is worth flagging.
  static const double warningFraction = 0.8;

  /// Where [current] usage of [key] stands against [plan]'s caps.
  static PlanLimitResult check(CompanyPlan plan, String key, int current) {
    final limit = plan.limitFor(key);
    if (limit == null || limit <= 0) {
      return PlanLimitResult(
        key: key,
        current: current,
        limit: null,
        state: PlanLimitState.ok,
      );
    }
    final state = current >= limit
        ? PlanLimitState.blocked
        : (current >= limit * warningFraction
              ? PlanLimitState.warning
              : PlanLimitState.ok);
    return PlanLimitResult(
      key: key,
      current: current,
      limit: limit,
      state: state,
    );
  }

  /// Every cap on [plan], measured against [usage].
  ///
  /// Keys absent from [usage] are reported as 0 rather than skipped, so the
  /// console always shows the full set of caps a tier carries.
  static List<PlanLimitResult> checkAll(
    CompanyPlan plan,
    Map<String, int> usage,
  ) {
    return [
      for (final key in PlanLimitKeys.all)
        check(plan, key, usage[key] ?? 0),
    ];
  }

  /// Throws [PlanLimitException] if adding one more [key] would breach the cap.
  ///
  /// Call this immediately before the write. [current] may be a cached count:
  /// a slightly stale number can let one extra record through, which is the
  /// right trade for not paying an aggregation query on every create.
  static void enforce(CompanyPlan plan, String key, int current) {
    final result = check(plan, key, current);
    if (!result.isBlocked) return;
    throw PlanLimitException(
      key: key,
      limit: result.limit!,
      planLabel: plan.label,
    );
  }
}
