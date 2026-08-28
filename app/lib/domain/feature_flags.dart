/// V2 feature flags — brief §22.
///
/// A deliberately small scaffold: compile-time constants gating V2 subsystems so
/// half-built work can land on main behind a switch. When a feature is proven it
/// either flips to `true` permanently or the flag is deleted and the branch
/// inlined. This is not a remote-config system — it exists so phases can merge
/// incrementally without shipping unfinished UI.
class FeatureFlags {
  const FeatureFlags._();

  static const shadowBoxingV2 = true;
  static const footworkAnalysis = true;
  static const rotationAnalysis = true;

  /// Combination detection (Phase 3). Off until that phase lands.
  static const combinationDetection = false;

  /// Combination drills UI + library (Phase 5). Off until that phase lands.
  static const combinationDrills = false;

  /// Full-round advanced AI analysis (Phase 6) — also gated by a configured
  /// vision endpoint at runtime.
  static const advancedAiAnalysis = false;
}
