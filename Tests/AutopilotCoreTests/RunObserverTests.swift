import Testing
import Foundation
@testable import AutopilotCore

/// Records observer callbacks for assertion.
final class RecordingObserver: RunObserver, @unchecked Sendable {
    var willStartPlan: String?
    var stepStarts: [(index: Int, total: Int, id: String)] = []
    var stepFinishes: [(index: Int, id: String, outcome: StepOutcome)] = []
    var finishedReport: Report?
    func runWillStart(plan: Plan) { willStartPlan = plan.name }
    func stepWillStart(_ step: Step, index: Int, of total: Int) {
        stepStarts.append((index, total, step.id))
    }
    func stepDidFinish(_ result: StepResult, index: Int) {
        stepFinishes.append((index, result.id, result.result))
    }
    func runDidFinish(_ report: Report) { finishedReport = report }
}

@Suite struct RunObserverTests {
    /// Build a 3-step plan: 2 happyPath launch/wait steps + 1 tryToBreakIt step
    /// that will be SKIPPED when maxLevel = .happyPath. (`.wait` with no args
    /// defaults to a 0-second wait — `ActionArgs` has only an empty init.)
    private func plan() -> Plan {
        Plan(schemaVersion: "1.1", name: "obs-test",
             target: TargetApp(bundleId: "com.fake"),
             steps: [
                Step(id: "s1", action: .launch, level: .happyPath),
                Step(id: "s2", action: .wait, level: .happyPath),
                Step(id: "s3", action: .wait, level: .tryToBreakIt),
             ])
    }

    @Test func firesPerStepInOrderIncludingSkipped() throws {
        let obs = RecordingObserver()
        let runner = PlanRunner(driver: FakeDriver(nodes: [["role": "AXWindow"]]))
        let opts = RunOptions(artifactsDir: FileManager.default.temporaryDirectory,
                              maxLevel: .happyPath, observer: obs)
        _ = try runner.run(plan(), options: opts)

        #expect(obs.willStartPlan == "obs-test")
        #expect(obs.stepStarts.map(\.id) == ["s1", "s2", "s3"])
        #expect(obs.stepStarts.allSatisfy { $0.total == 3 })
        #expect(obs.stepStarts.map(\.index) == [0, 1, 2])
        #expect(obs.stepFinishes.map(\.id) == ["s1", "s2", "s3"])
        #expect(obs.stepFinishes.map(\.index) == [0, 1, 2])
        // s3 is above maxLevel -> skipped.
        #expect(obs.stepFinishes.last?.outcome == .skipped)
        #expect(obs.finishedReport?.plan == "obs-test")
    }

    @Test func nilObserverIsDefaultAndRunsUnchanged() throws {
        let runner = PlanRunner(driver: FakeDriver(nodes: [["role": "AXWindow"]]))
        // No observer passed — proves the default keeps existing callers working.
        let report = try runner.run(plan(),
            options: RunOptions(artifactsDir: FileManager.default.temporaryDirectory,
                                maxLevel: .happyPath))
        #expect(report.steps.count == 3)
    }
}
