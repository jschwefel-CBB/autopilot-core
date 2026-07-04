import Testing
import Foundation
@testable import AutopilotCore

/// A driver whose captures all FAIL, and whose Screen Recording status is
/// configurable — to exercise the "never fail silently" screenshot path and the
/// snapshot reference-write diagnostic.
struct CaptureFailDriver: AppDriver {
    var screenRecording: Bool
    var nodes: [[String: String]] = [["role": "AXWindow"]]
    func launch(_ target: TargetApp) throws -> LaunchedHandle { LaunchedHandle(pid: 1, appName: "Fake") }
    func attach(_ target: TargetApp) throws -> LaunchedHandle { LaunchedHandle(pid: 1, appName: "Fake") }
    func attach(pid: Int32) throws -> LaunchedHandle { LaunchedHandle(pid: pid, appName: "Fake") }
    func terminate(_ app: LaunchedHandle) {}
    func activate(_ app: LaunchedHandle, timeoutMs: Int, intervalMs: Int) -> Bool { true }
    func hasAccessibility() -> Bool { true }
    func hasScreenRecording() -> Bool { screenRecording }
    func accessibilityInstructions() -> String { "grant ax" }
    func screenRecordingInstructions() -> String { "grant Screen Recording in System Settings" }
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
    func captureElementScreenshot(_ element: any ElementHandle, to path: String, padding: Int, metadata: [String: String]) -> String? { "element capture failed" }
    func captureMainDisplay(to path: String, metadata: [String: String]) -> Bool { false }
    func captureRegion(_ rect: Rect, to path: String, metadata: [String: String]) -> Bool { false }
    func samplePixel(at point: Point) -> RGBColor? { nil }
    func sampleRegion(_ rect: Rect) -> [RGBColor] { [] }
    func loadPNG(_ path: String) -> [RGBColor]? { nil }
    func dumpTree(app: LaunchedHandle) -> TreeSnapshot { TreeSnapshot(nodes: nodes, truncated: false) }
    func suggestSelectors(app: LaunchedHandle) -> [SelectorSuggester.Suggestion] { [] }
}

@Suite struct ScreenshotMessageTests {
    /// A full-display screenshot that fails must carry a non-nil message (SC-1:
    /// never a silent fail with no artifact and no reason).
    @Test func fullDisplayScreenshotFailureCarriesMessage() throws {
        let plan = Plan(schemaVersion: "1.1", name: "shot",
                        target: TargetApp(bundleId: "x"),
                        steps: [Step(id: "shot", action: .screenshot, level: .happyPath)])
        // SR present: the message names the capture failure (not a permission issue).
        let report = try PlanRunner(driver: CaptureFailDriver(screenRecording: true)).run(
            plan, options: RunOptions(artifactsDir: FileManager.default.temporaryDirectory))
        let step = report.steps.first
        #expect(step?.result == .fail)
        #expect(step?.message != nil)
        #expect(step?.message?.contains("screen capture failed") == true)
    }

    @Test func screenshotFailureNamesScreenRecordingWhenMissing() throws {
        let plan = Plan(schemaVersion: "1.1", name: "shot2",
                        target: TargetApp(bundleId: "x"),
                        steps: [Step(id: "shot", action: .screenshot, level: .happyPath)])
        // SR missing: the message points at the permission.
        let report = try PlanRunner(driver: CaptureFailDriver(screenRecording: false)).run(
            plan, options: RunOptions(artifactsDir: FileManager.default.temporaryDirectory))
        #expect(report.steps.first?.message?.contains("Screen Recording") == true)
    }
}
