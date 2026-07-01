import Foundation

public enum StepOutcome: String, Codable, Sendable { case pass, fail, error, skipped }

public struct StepResult: Codable, Sendable {
    public var id: String
    public var result: StepOutcome
    public var durationMs: Int
    /// The coverage tier of the step that produced this result. Echoed from the
    /// plan so the report can break results down per tier (see `LevelBreakdown`).
    public var level: StepLevel
    public var expected: String?
    public var actual: String?
    public var message: String?
    public var screenshot: String?
    public var axDump: String?
    public init(id: String, result: StepOutcome, durationMs: Int,
                level: StepLevel = .happyPath,
                expected: String? = nil, actual: String? = nil, message: String? = nil,
                screenshot: String? = nil, axDump: String? = nil) {
        self.id = id; self.result = result; self.durationMs = durationMs
        self.level = level
        self.expected = expected; self.actual = actual; self.message = message
        self.screenshot = screenshot; self.axDump = axDump
    }
}

/// Outcome tallies for a set of steps.
public struct OutcomeCounts: Codable, Sendable, Equatable {
    public var pass: Int
    public var fail: Int
    public var error: Int
    public var skipped: Int
    public init(pass: Int = 0, fail: Int = 0, error: Int = 0, skipped: Int = 0) {
        self.pass = pass; self.fail = fail; self.error = error; self.skipped = skipped
    }
    public var total: Int { pass + fail + error + skipped }
    mutating func add(_ outcome: StepOutcome) {
        switch outcome {
        case .pass: pass += 1
        case .fail: fail += 1
        case .error: error += 1
        case .skipped: skipped += 1
        }
    }
    static func + (a: OutcomeCounts, b: OutcomeCounts) -> OutcomeCounts {
        OutcomeCounts(pass: a.pass + b.pass, fail: a.fail + b.fail,
                      error: a.error + b.error, skipped: a.skipped + b.skipped)
    }
}

/// Per-tier and cumulative pass/fail breakdown of a run. Additive to the report;
/// does not affect the overall `Report.result`.
public struct LevelBreakdown: Codable, Sendable, Equatable {
    /// Counts for steps tagged exactly at each tier.
    public var happyPath: OutcomeCounts
    public var integrationSuite: OutcomeCounts
    public var tryToBreakIt: OutcomeCounts
    /// Cumulative coverage when running AT each level (that tier plus all lower
    /// tiers) — mirrors the run/`maxLevel` semantics.
    public var cumulativeAtHappyPath: OutcomeCounts
    public var cumulativeAtIntegration: OutcomeCounts
    public var cumulativeAtTryToBreakIt: OutcomeCounts

    public init(steps: [StepResult]) {
        var hp = OutcomeCounts(), it = OutcomeCounts(), tb = OutcomeCounts()
        for s in steps {
            switch s.level {
            case .happyPath: hp.add(s.result)
            case .integrationSuite: it.add(s.result)
            case .tryToBreakIt: tb.add(s.result)
            }
        }
        happyPath = hp; integrationSuite = it; tryToBreakIt = tb
        cumulativeAtHappyPath = hp
        cumulativeAtIntegration = hp + it
        cumulativeAtTryToBreakIt = hp + it + tb
    }
}

public struct PermissionStatus: Codable, Sendable {
    public var accessibility: Bool
    /// Whether Screen Recording is granted (a real, probed value — replaces the
    /// former hardcoded `automation: true`, which was never checked).
    public var screenRecording: Bool
    public init(accessibility: Bool, screenRecording: Bool) {
        self.accessibility = accessibility; self.screenRecording = screenRecording
    }
}

public struct Report: Codable, Sendable {
    public var plan: String
    public var result: StepOutcome
    public var durationMs: Int
    public var steps: [StepResult]
    public var permissions: PermissionStatus?
    /// The per-plan directory where this report and its artifacts were written.
    public var artifactsDir: String?
    /// Per-tier and cumulative pass/fail breakdown (additive; does not affect
    /// `result`). Populated by `finalize`.
    public var levelBreakdown: LevelBreakdown?

    public init(plan: String) {
        self.plan = plan; self.result = .pass; self.durationMs = 0
        self.steps = []; self.permissions = nil; self.artifactsDir = nil
        self.levelBreakdown = nil
    }

    public mutating func add(_ step: StepResult) { steps.append(step) }

    /// Compute overall result (any fail/error => that) and total duration.
    public mutating func finalize(permissions: PermissionStatus) {
        self.permissions = permissions
        durationMs = steps.reduce(0) { $0 + $1.durationMs }
        levelBreakdown = LevelBreakdown(steps: steps)
        if steps.isEmpty {
            // A plan that executed nothing is an error, not a pass — fail-closed,
            // so a dropped/over-filtered plan can't silently report green.
            result = .error
        } else if steps.contains(where: { $0.result == .error }) { result = .error }
        else if steps.contains(where: { $0.result == .fail }) { result = .fail }
        else { result = .pass }
    }
}
