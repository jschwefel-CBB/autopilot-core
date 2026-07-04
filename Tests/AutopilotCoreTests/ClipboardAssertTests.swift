import Testing
import Foundation
@testable import AutopilotCore

/// A FakeDriver variant whose clipboard returns a fixed string, to drive the
/// clipboard-assert path without a real pasteboard.
struct ClipboardFakeDriver: AppDriver {
    var clipboard: String?
    var nodes: [[String: String]] = []
    func launch(_ target: TargetApp) throws -> LaunchedHandle { LaunchedHandle(pid: 1, appName: "Fake") }
    func attach(_ target: TargetApp) throws -> LaunchedHandle { LaunchedHandle(pid: 1, appName: "Fake") }
    func attach(pid: Int32) throws -> LaunchedHandle { LaunchedHandle(pid: pid, appName: "Fake") }
    func terminate(_ app: LaunchedHandle) {}
    func activate(_ app: LaunchedHandle, timeoutMs: Int, intervalMs: Int) -> Bool { true }
    func hasAccessibility() -> Bool { true }
    func hasScreenRecording() -> Bool { true }
    func accessibilityInstructions() -> String { "grant ax" }
    func screenRecordingInstructions() -> String { "grant sr" }
    func resolve(_ selector: AutopilotCore.Selector, app: LaunchedHandle, timeoutMs: Int, intervalMs: Int, baseDir: URL?) throws -> ResolvedElement { throw TargetingError.notFound(selector: "{}") }
    func waitForPresence(_ selector: AutopilotCore.Selector, present: Bool, app: LaunchedHandle, timeoutMs: Int, intervalMs: Int) -> Bool { present }
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
    func dumpTree(app: LaunchedHandle) -> TreeSnapshot { TreeSnapshot(nodes: nodes, truncated: false) }
    func suggestSelectors(app: LaunchedHandle) -> [SelectorSuggester.Suggestion] { [] }
    func readClipboard() -> String? { clipboard }
    func listMenu(path: [String], app: LaunchedHandle) throws -> [MenuItemInfo] { [] }
}

@Suite struct ClipboardAssertTests {
    private func plan(op: AssertOp, expected: String) -> Plan {
        Plan(schemaVersion: "1.1", name: "clip",
             target: TargetApp(bundleId: "com.fake"),
             steps: [
                Step(id: "assert-clip", action: .assert, level: .happyPath,
                     assert: Assertion(property: .clipboard, op: op, expected: expected))
             ])
    }

    @Test func clipboardEqualsPasses() throws {
        let driver = ClipboardFakeDriver(clipboard: "hello world", nodes: [["role": "AXWindow"]])
        let report = try PlanRunner(driver: driver).run(
            plan(op: .equals, expected: "hello world"),
            options: RunOptions(artifactsDir: FileManager.default.temporaryDirectory))
        #expect(report.steps.first?.result == .pass)
        #expect(report.steps.first?.actual == "hello world")
    }

    @Test func clipboardContainsPasses() throws {
        let driver = ClipboardFakeDriver(clipboard: "the quick brown fox", nodes: [["role": "AXWindow"]])
        let report = try PlanRunner(driver: driver).run(
            plan(op: .contains, expected: "quick"),
            options: RunOptions(artifactsDir: FileManager.default.temporaryDirectory))
        #expect(report.steps.first?.result == .pass)
    }

    @Test func clipboardMismatchFails() throws {
        let driver = ClipboardFakeDriver(clipboard: "actual text", nodes: [["role": "AXWindow"]])
        let report = try PlanRunner(driver: driver).run(
            plan(op: .equals, expected: "expected text"),
            options: RunOptions(artifactsDir: FileManager.default.temporaryDirectory))
        #expect(report.steps.first?.result == .fail)
        #expect(report.steps.first?.actual == "actual text")
    }

    @Test func clipboardAssertParsesWithoutTarget() throws {
        // A clipboard assert is target-less and must pass parse validation.
        let json = """
        {"schemaVersion":"1.1","name":"p","target":{"bundleId":"x"},
         "steps":[{"id":"c","action":"assert","level":"happyPath",
           "assert":{"property":"clipboard","op":"equals","expected":"hi"}}]}
        """
        let plan = try PlanParser().parse(data: Data(json.utf8),
                                          baseDirectory: FileManager.default.temporaryDirectory)
        #expect(plan.steps.count == 1)
    }

    @Test func nonClipboardAssertStillRequiresTarget() {
        // A value assert with no target must still be rejected at parse.
        let json = """
        {"schemaVersion":"1.1","name":"p","target":{"bundleId":"x"},
         "steps":[{"id":"v","action":"assert","level":"happyPath",
           "assert":{"property":"value","op":"equals","expected":"hi"}}]}
        """
        #expect(throws: (any Error).self) {
            _ = try PlanParser().parse(data: Data(json.utf8),
                                       baseDirectory: FileManager.default.temporaryDirectory)
        }
    }

    @Test func emptyClipboardReadsAsEmptyString() throws {
        let driver = ClipboardFakeDriver(clipboard: nil, nodes: [["role": "AXWindow"]])
        let report = try PlanRunner(driver: driver).run(
            plan(op: .equals, expected: ""),
            options: RunOptions(artifactsDir: FileManager.default.temporaryDirectory))
        #expect(report.steps.first?.result == .pass)
    }
}
