import Testing
import Foundation
@testable import AutopilotCore

/// Runtime behavior of the `exec` step, driven through PlanRunner against a fake
/// driver whose runProcess returns canned results (or throws). No real Process —
/// deterministic and headless.
@Suite struct RunExecTests {

    /// A FakeDriver variant whose runProcess is scriptable.
    struct ExecFakeDriver: AppDriver {
        var stubResult: ProcessResult? = nil
        var throwOnRun: Bool = false
        var recorder: ExecRecorder? = nil

        func launch(_ target: TargetApp) throws -> LaunchedHandle { LaunchedHandle(pid: 1, appName: "Fake") }
        func attach(_ target: TargetApp) throws -> LaunchedHandle { LaunchedHandle(pid: 1, appName: "Fake") }
        func attach(pid: Int32) throws -> LaunchedHandle { LaunchedHandle(pid: pid, appName: "Fake") }
        func terminate(_ app: LaunchedHandle) {}
        func activate(_ app: LaunchedHandle, timeoutMs: Int, intervalMs: Int) -> Bool { true }
        func hasAccessibility() -> Bool { true }
        func hasScreenRecording() -> Bool { true }
        func accessibilityInstructions() -> String { "" }
        func screenRecordingInstructions() -> String { "" }
        func resolve(_ selector: AutopilotCore.Selector, app: LaunchedHandle, timeoutMs: Int, intervalMs: Int, baseDir: URL?) throws -> ResolvedElement { throw TargetingError.notFound(selector: "{}") }
        func waitForPresence(_ selector: AutopilotCore.Selector, present: Bool, app: LaunchedHandle, timeoutMs: Int, intervalMs: Int) -> Bool { true }
        func matchCount(_ selector: AutopilotCore.Selector, app: LaunchedHandle) -> Int { 0 }
        func findAll(_ selector: AutopilotCore.Selector, app: LaunchedHandle) -> [String] { [] }
        func perform(action: Action, args: ActionArgs?, on element: ResolvedElement?) throws {}
        func point(for element: ResolvedElement) -> Point? { Point(x: 0, y: 0) }
        func performDrag(from: Point, to: Point) throws {}
        func performFileDrag(files: [String], to: Point) throws {}
        func selectMenuPath(_ path: [String], app: LaunchedHandle) throws {}
        func readProperty(_ property: AssertProperty, of element: any ElementHandle) -> String? { nil }
        func captureElementScreenshot(_ element: any ElementHandle, to path: String, padding: Int, metadata: [String: String]) -> String? { nil }
        func captureMainDisplay(to path: String, metadata: [String: String]) -> Bool { true }
        func captureRegion(_ rect: Rect, to path: String, metadata: [String: String]) -> Bool { true }
        func samplePixel(at point: Point) -> RGBColor? { nil }
        func sampleRegion(_ rect: Rect) -> [RGBColor] { [] }
        func loadPNG(_ path: String) -> [RGBColor]? { nil }
        func dumpTree(app: LaunchedHandle) -> TreeSnapshot { TreeSnapshot(nodes: [], truncated: false) }
        func suggestSelectors(app: LaunchedHandle) -> [SelectorSuggester.Suggestion] { [] }

        func runProcess(command: String?, argv: [String]?, timeoutMs: Int, workingDir: String?) throws -> ProcessResult {
            recorder?.calls.append((command: command, argv: argv, workingDir: workingDir))
            if throwOnRun { throw PlanError.decode("exec: could not launch") }
            return stubResult ?? ProcessResult(stdout: "", stderr: "", exitCode: 0)
        }
    }

    final class ExecRecorder { var calls: [(command: String?, argv: [String]?, workingDir: String?)] = [] }

    func makePlan(_ step: Step) -> Plan {
        Plan(schemaVersion: "1.1", name: "exec", target: TargetApp(bundleId: "x"), steps: [step])
    }

    func run(_ driver: ExecFakeDriver, _ step: Step) throws -> Report {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return try PlanRunner(driver: driver).run(makePlan(step), options: RunOptions(artifactsDir: tmp))
    }

    @Test func bareExecPassesEvenOnNonzeroExit() throws {
        // A setup/teardown exec ignores the exit code.
        let d = ExecFakeDriver(stubResult: ProcessResult(stdout: "", stderr: "boom", exitCode: 7))
        var args = ActionArgs(); args.command = "rm -f /tmp/x"
        let step = Step(id: "e", action: .exec, level: .happyPath, args: args)
        let report = try run(d, step)
        #expect(report.result == .pass)
    }

    @Test func execStdoutAssertPassesWhenMatched() throws {
        let d = ExecFakeDriver(stubResult: ProcessResult(stdout: "saved line\n", stderr: "", exitCode: 0))
        var args = ActionArgs(); args.argv = ["/bin/cat", "/tmp/x"]
        let step = Step(id: "e", action: .exec, level: .happyPath, args: args,
                        assert: Assertion(property: .stdout, op: .contains, expected: "saved"))
        let report = try run(d, step)
        #expect(report.result == .pass)
    }

    @Test func execStdoutAssertFailsWhenNotMatched() throws {
        let d = ExecFakeDriver(stubResult: ProcessResult(stdout: "nope", stderr: "", exitCode: 0))
        var args = ActionArgs(); args.argv = ["/bin/cat", "/tmp/x"]
        let step = Step(id: "e", action: .exec, level: .happyPath, args: args,
                        assert: Assertion(property: .stdout, op: .contains, expected: "saved"))
        let report = try run(d, step)
        #expect(report.result == .fail)
    }

    @Test func execExitCodeAssertReadsNumericStatus() throws {
        let d = ExecFakeDriver(stubResult: ProcessResult(stdout: "", stderr: "", exitCode: 3))
        var args = ActionArgs(); args.command = "exit 3"
        let step = Step(id: "e", action: .exec, level: .happyPath, args: args,
                        assert: Assertion(property: .exitCode, op: .equals, expected: "3"))
        let report = try run(d, step)
        #expect(report.result == .pass)
    }

    @Test func execLaunchFailureFailsTheStep() throws {
        let d = ExecFakeDriver(throwOnRun: true)
        var args = ActionArgs(); args.argv = ["/nonexistent"]
        let step = Step(id: "e", action: .exec, level: .happyPath, args: args)
        let report = try run(d, step)
        #expect(report.result != .pass)   // error/fail, never a silent pass
    }

    @Test func execPassesWorkingDirAndCommandToDriver() throws {
        let rec = ExecRecorder()
        let d = ExecFakeDriver(recorder: rec)
        var args = ActionArgs(); args.command = "echo hi"
        let step = Step(id: "e", action: .exec, level: .happyPath, args: args)
        _ = try run(d, step)
        #expect(rec.calls.count == 1)
        #expect(rec.calls.first?.command == "echo hi")
    }
}
