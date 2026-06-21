import Foundation

/// Aggregate result of running many plans (a suite).
public struct SuiteReport: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public var plan: String
        public var result: StepOutcome
        public var durationMs: Int
        public var reportPath: String?
        public init(plan: String, result: StepOutcome, durationMs: Int, reportPath: String? = nil) {
            self.plan = plan; self.result = result; self.durationMs = durationMs
            self.reportPath = reportPath
        }
    }

    public var total: Int
    public var passed: Int
    public var failed: Int
    public var errored: Int
    public var durationMs: Int
    public var result: StepOutcome      // overall: error > fail > pass
    public var plans: [Entry]

    /// Build a suite report from individual plan reports (in run order).
    public init(reports: [Report], reportPaths: [String?] = []) {
        plans = reports.enumerated().map { i, r in
            Entry(plan: r.plan, result: r.result, durationMs: r.durationMs,
                  reportPath: i < reportPaths.count ? reportPaths[i] : r.artifactsDir)
        }
        total = reports.count
        passed = reports.filter { $0.result == .pass }.count
        failed = reports.filter { $0.result == .fail }.count
        errored = reports.filter { $0.result == .error }.count
        durationMs = reports.reduce(0) { $0 + $1.durationMs }
        // An empty suite (no plans ran) is an error, not a pass — a directory
        // with no valid plans must not produce a green build.
        if reports.isEmpty { result = .error }
        else if errored > 0 { result = .error }
        else if failed > 0 { result = .fail }
        else { result = .pass }
    }

    /// One-line machine summary, e.g. `SUITE fail 18/20 (failed: find-bar, rename)`.
    public func summaryLine() -> String {
        var line = "SUITE \(result.rawValue) \(passed)/\(total)"
        let bad = plans.filter { $0.result != .pass }.map(\.plan)
        if !bad.isEmpty { line += " (failed: \(bad.joined(separator: ", ")))" }
        return line
    }

    /// Human-readable multi-line summary.
    public func humanSummary() -> String {
        var lines = ["Suite: \(passed)/\(total) passed  (\(failed) failed, \(errored) errored, \(durationMs)ms)"]
        for p in plans {
            lines.append("  [\(p.result.rawValue)] \(p.plan) (\(p.durationMs)ms)")
        }
        return lines.joined(separator: "\n")
    }
}
