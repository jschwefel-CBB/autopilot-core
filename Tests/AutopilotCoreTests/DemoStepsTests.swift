import Testing
import Foundation
@testable import AutopilotCore

/// Phase-1 demo-step type tests (schema v1.2): the new `highlight` / `caption` /
/// `pace` actions parse + validate, a v1.1 plan still parses (back-compat), and in
/// a normal (demo-off) run the demo steps are passing no-ops while a demo-on run
/// drives the driver's demo hooks.

// A reference sink so a value-type driver can record demo-hook calls.
final class DemoCallLog {
    var highlights: [Int] = []   // holdMs of each showHighlight call
    var captions: [(text: String, position: String, holdMs: Int)] = []
    /// Every `perform` the runner made, so we can prove `pace` did not itself act.
    var performed: [Action] = []
}

/// A driver that records the demo hooks + performed actions. Mirrors FakeDriver but
/// implements the new demo methods so we can observe them.
struct DemoRecordingDriver: AppDriver {
    var nodes: [[String: String]] = [["role": "AXButton", "identifier": "ok"],
                                     ["role": "AXTextField", "identifier": "nameField"]]
    var log: DemoCallLog
    func launch(_ target: TargetApp) throws -> LaunchedHandle { LaunchedHandle(pid: 1, appName: "Demo") }
    func attach(_ target: TargetApp) throws -> LaunchedHandle { LaunchedHandle(pid: 1, appName: "Demo") }
    func attach(pid: Int32) throws -> LaunchedHandle { LaunchedHandle(pid: pid, appName: "Demo") }
    func terminate(_ app: LaunchedHandle) {}
    func activate(_ app: LaunchedHandle, timeoutMs: Int, intervalMs: Int) -> Bool { true }
    func hasAccessibility() -> Bool { true }
    func hasScreenRecording() -> Bool { true }
    func accessibilityInstructions() -> String { "grant ax" }
    func screenRecordingInstructions() -> String { "grant sr" }
    func resolve(_ selector: AutopilotCore.Selector, app: LaunchedHandle, timeoutMs: Int, intervalMs: Int, baseDir: URL?) throws -> ResolvedElement {
        if nodes.contains(where: { AXResolver.matches(node: $0, selector: selector) }) { return .element(FakeElement("x")) }
        throw TargetingError.notFound(selector: "{}")
    }
    func waitForPresence(_ selector: AutopilotCore.Selector, present: Bool, app: LaunchedHandle, timeoutMs: Int, intervalMs: Int) -> Bool { present }
    func matchCount(_ selector: AutopilotCore.Selector, app: LaunchedHandle) -> Int { nodes.count }
    func findAll(_ selector: AutopilotCore.Selector, app: LaunchedHandle) -> [String] { [] }
    func perform(action: Action, args: ActionArgs?, on element: ResolvedElement?) throws { log.performed.append(action) }
    func point(for element: ResolvedElement) -> Point? { Point(x: 10, y: 20) }
    func performDrag(from: Point, to: Point) throws {}
    func performFileDrag(files: [String], to: Point) throws {}
    func selectMenuPath(_ path: [String], app: LaunchedHandle) throws {}
    func readProperty(_ property: AssertProperty, of element: any ElementHandle) -> String? { "fake" }
    func captureElementScreenshot(_ element: any ElementHandle, to path: String, padding: Int, metadata: [String: String]) -> String? { nil }
    func captureMainDisplay(to path: String, metadata: [String: String]) -> Bool { true }
    func captureRegion(_ rect: Rect, to path: String, metadata: [String: String]) -> Bool { true }
    func samplePixel(at point: Point) -> RGBColor? { RGBColor(r: 0, g: 0, b: 0) }
    func sampleRegion(_ rect: Rect) -> [RGBColor] { [] }
    func loadPNG(_ path: String) -> [RGBColor]? { nil }
    func dumpTree(app: LaunchedHandle) -> TreeSnapshot { TreeSnapshot(nodes: nodes, truncated: false) }
    func suggestSelectors(app: LaunchedHandle) -> [SelectorSuggester.Suggestion] { [] }
    // The new demo hooks — record instead of rendering.
    func showHighlight(_ element: any ElementHandle, holdMs: Int) { log.highlights.append(holdMs) }
    func showCaption(_ text: String, position: String, holdMs: Int) { log.captions.append((text, position, holdMs)) }
}

@Suite struct DemoStepDecodingTests {
    @Test func decodesV12PlanWithDemoActions() throws {
        let json = """
        {
          "schemaVersion": "1.2",
          "name": "demo",
          "target": { "bundleId": "com.example.app" },
          "steps": [
            { "id": "pace1", "level": "happyPath", "action": "pace",
              "args": { "typeMsPerChar": 60, "stepDelayMs": 500 } },
            { "id": "cap1", "level": "happyPath", "action": "caption",
              "args": { "text": "Enter your name", "position": "bottom", "holdMs": 1500 } },
            { "id": "hi1", "level": "happyPath", "action": "highlight",
              "target": { "identifier": "nameField" }, "args": { "holdMs": 1200 } }
          ]
        }
        """.data(using: .utf8)!
        let plan = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        #expect(plan.schemaVersion == "1.2")
        #expect(plan.steps.count == 3)
        #expect(plan.steps[0].action == .pace)
        #expect(plan.steps[0].args?.typeMsPerChar == 60)
        #expect(plan.steps[0].args?.stepDelayMs == 500)
        #expect(plan.steps[1].action == .caption)
        #expect(plan.steps[1].args?.text == "Enter your name")
        #expect(plan.steps[1].args?.position == "bottom")
        #expect(plan.steps[1].args?.holdMs == 1500)
        #expect(plan.steps[2].action == .highlight)
        #expect(plan.steps[2].args?.holdMs == 1200)
    }

    @Test func stillParsesV11Plan() throws {
        // Back-compat: an existing v1.1 plan must parse unchanged under the new parser.
        let json = """
        {
          "schemaVersion": "1.1",
          "name": "legacy",
          "target": { "bundleId": "com.example.app" },
          "steps": [
            { "id": "c1", "level": "happyPath", "action": "click",
              "target": { "identifier": "ok" } }
          ]
        }
        """.data(using: .utf8)!
        let plan = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        #expect(plan.schemaVersion == "1.1")
        #expect(plan.steps[0].action == .click)
    }
}

@Suite struct DemoStepValidationTests {
    private func parse(_ json: String) throws -> Plan {
        try PlanParser().parse(data: json.data(using: .utf8)!, baseDirectory: URL(fileURLWithPath: "/tmp"))
    }

    @Test func captionRequiresText() throws {
        let json = """
        {"schemaVersion":"1.2","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"c","level":"happyPath","action":"caption","args":{"holdMs":100}}]}
        """
        #expect(throws: (any Error).self) { _ = try parse(json) }
    }

    @Test func highlightRequiresTarget() throws {
        let json = """
        {"schemaVersion":"1.2","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"h","level":"happyPath","action":"highlight","args":{"holdMs":100}}]}
        """
        #expect(throws: (any Error).self) { _ = try parse(json) }
    }

    @Test func paceRequiresAtLeastOneCadence() throws {
        let json = """
        {"schemaVersion":"1.2","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"p","level":"happyPath","action":"pace","args":{}}]}
        """
        #expect(throws: (any Error).self) { _ = try parse(json) }
    }

    @Test func validDemoStepsPass() throws {
        let json = """
        {"schemaVersion":"1.2","name":"x","target":{"bundleId":"a"},
         "steps":[
           {"id":"p","level":"happyPath","action":"pace","args":{"typeMsPerChar":40}},
           {"id":"c","level":"happyPath","action":"caption","args":{"text":"hi"}},
           {"id":"h","level":"happyPath","action":"highlight","target":{"identifier":"nameField"}}
         ]}
        """
        let plan = try parse(json)
        #expect(plan.steps.count == 3)
    }
}

@Suite struct DemoRunSemanticsTests {
    private func demoPlan() -> Plan {
        Plan(schemaVersion: "1.2", name: "demo-run",
             target: TargetApp(bundleId: "com.example.app"),
             steps: [
                Step(id: "pace1", action: .pace, level: .happyPath,
                     args: { var a = ActionArgs(); a.typeMsPerChar = 5; a.stepDelayMs = 0; return a }()),
                Step(id: "cap1", action: .caption, level: .happyPath,
                     args: { var a = ActionArgs(); a.text = "hello"; a.position = "bottom"; a.holdMs = 0; return a }()),
                Step(id: "hi1", action: .highlight, level: .happyPath,
                     target: Selector(identifier: "nameField"),
                     args: { var a = ActionArgs(); a.holdMs = 0; return a }()),
             ])
    }

    @Test func demoOffTreatsDemoStepsAsPassingNoOps() throws {
        let log = DemoCallLog()
        let driver = DemoRecordingDriver(log: log)
        let opts = RunOptions(artifactsDir: URL(fileURLWithPath: NSTemporaryDirectory()))
        let report = try PlanRunner(driver: driver, clock: SystemClock()).run(demoPlan(), options: opts)
        // All three demo steps pass, and the demo hooks were NOT called (demo off).
        #expect(report.steps.allSatisfy { $0.result == .pass })
        #expect(log.highlights.isEmpty)
        #expect(log.captions.isEmpty)
    }

    @Test func demoOnDrivesHighlightAndCaption() throws {
        let log = DemoCallLog()
        let driver = DemoRecordingDriver(log: log)
        var opts = RunOptions(artifactsDir: URL(fileURLWithPath: NSTemporaryDirectory()))
        opts.demoMode = true
        let report = try PlanRunner(driver: driver, clock: SystemClock()).run(demoPlan(), options: opts)
        #expect(report.steps.allSatisfy { $0.result == .pass })
        #expect(log.captions.count == 1)
        #expect(log.captions.first?.text == "hello")
        #expect(log.captions.first?.position == "bottom")
        #expect(log.highlights.count == 1)
    }
}
