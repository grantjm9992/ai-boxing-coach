/// Stable internal error codes for technical faults — V2 brief §25.
///
/// These are identity, not display text. Display strings (coaching voice) live
/// on the [Observation.coachingText]; they change freely. The code does not: it
/// is what analytics, the regression dataset and the AI reasoning layer key on,
/// so once shipped a code's meaning must not drift.
///
/// Grouped by family with a numeric suffix. Add new codes; do not renumber.
class FaultCode {
  const FaultCode._();

  // Guard (§11.5)
  static const guardLeadHandLow = 'GUARD_001';
  static const guardRearHandLow = 'GUARD_002';
  static const guardLeadDropsDuringRear = 'GUARD_003';
  static const guardRearDropsDuringLead = 'GUARD_004';
  static const guardSlowRecovery = 'GUARD_005';
  static const guardBothHandsLow = 'GUARD_006';

  // Rotation (§11.2)
  static const rotInsufficient = 'ROT_001';
  static const rotOver = 'ROT_002';
  static const rotTooEarly = 'ROT_003';
  static const rotTooLate = 'ROT_004';
  static const rotNotRecovered = 'ROT_005';

  // Balance (§11.7)
  static const balOffAfterPunch = 'BAL_001';
  static const balOffAfterCombination = 'BAL_002';
  static const balWeightForward = 'BAL_003';
  static const balWeightBackward = 'BAL_004';
  static const balCorrectiveStep = 'BAL_005';

  // Footwork (§11.4)
  static const footFeetCrossing = 'FOOT_001';
  static const footStanceTooNarrow = 'FOOT_002';
  static const footStanceTooWide = 'FOOT_003';
  static const footFeetTooSquare = 'FOOT_004';
  static const footRearFootLagging = 'FOOT_005';
  static const footLeadFootLagging = 'FOOT_006';
  static const footStanceNotRecovered = 'FOOT_007';
  static const footBalanceLostAfterStep = 'FOOT_008';
  static const footFlatFooted = 'FOOT_009';

  // Body lean (§11.1)
  static const leanForward = 'LEAN_001';
  static const leanBackward = 'LEAN_002';
  static const leanLeft = 'LEAN_003';
  static const leanRight = 'LEAN_004';

  // Body position (§11.3)
  static const posHeadTooFarForward = 'POS_001';
  static const posHeadOverFrontKnee = 'POS_002';
  static const posTooUpright = 'POS_003';
  static const posNotRecovered = 'POS_004';
  static const posOffCentreAfterPunch = 'POS_005';

  // Punch recovery (§11.6)
  static const recSlow = 'REC_001';
  static const recHandNotReturned = 'REC_002';
  static const recOverextended = 'REC_003';

  // Head movement (existing rule)
  static const headStatic = 'HEAD_001';
}
