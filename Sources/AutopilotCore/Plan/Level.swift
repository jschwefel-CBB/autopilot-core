import Foundation

/// The coverage tier of a step, forming a cumulative hierarchy:
/// `happyPath` ⊂ `integrationSuite` ⊂ `tryToBreakIt`.
///
/// A run AT a level executes that level and every level below it (see
/// `RunOptions.maxLevel`), so each test case is written once and reused by the
/// higher tiers — no duplication.
///
/// This is a coverage LABEL — it does NOT change pass/fail semantics. A
/// `tryToBreakIt` step still passes by asserting the app refused correctly
/// (e.g. an error message appears, a submit button stays disabled, a bad value
/// is rejected). The assertions express "should reject"; the level only says
/// which tier the step belongs to.
public enum StepLevel: String, Codable, Sendable, CaseIterable, Comparable {
    /// Innermost / minimal: the expected flow works with valid input.
    /// "Does it do what I want it to?"
    case happyPath
    /// Middle: features working together, realistic end-to-end flows, broader
    /// functional coverage beyond the single happy path. "Do the pieces work together?"
    case integrationSuite
    /// Full set: adversarial / boundary — bad data, out-of-order or rapid
    /// actions; assert the app refuses or degrades gracefully. "Can we break it?"
    case tryToBreakIt

    /// Rank for cumulative subsumption. A run at level L includes all steps
    /// whose `level.rank <= L.rank`.
    public var rank: Int {
        switch self {
        case .happyPath: return 0
        case .integrationSuite: return 1
        case .tryToBreakIt: return 2
        }
    }

    public static func < (lhs: StepLevel, rhs: StepLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}
