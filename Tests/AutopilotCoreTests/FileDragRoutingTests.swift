import Testing
import Foundation
@testable import AutopilotCore

/// A `drag` step carrying `toFiles` must route to the driver's `performFileDrag`
/// (real file drop) and PASS — not return the old "not supported" error result.
@Suite struct FileDragRoutingTests {

    private func run(step: Step, driver: FakeDriver) throws -> Report {
        let plan = Plan(schemaVersion: "1.1", name: "filedrag",
                        target: TargetApp(bundleId: "x"), steps: [step])
        let opts = RunOptions(artifactsDir: URL(fileURLWithPath: "/tmp/filedrag-artifacts"))
        return try PlanRunner(driver: driver).run(plan, options: opts)
    }

    @Test func dragWithToFilesRoutesToPerformFileDrag() throws {
        let log = DriverCallLog()
        // The fake resolves a target only if a matching node exists.
        var driver = FakeDriver(nodes: [["role": "AXTextArea", "identifier": "Editor"]])
        driver.callLog = log

        var args = ActionArgs()
        args.toFiles = ["/tmp/a.txt", "/tmp/b.txt"]
        let step = Step(id: "drop", action: .drag, level: .happyPath,
                        target: Selector(identifier: "Editor"), args: args)

        let report = try run(step: step, driver: driver)

        // Routed to the real-drop path exactly once, with both files…
        #expect(log.fileDragCalls.count == 1)
        #expect(log.fileDragCalls.first?.files == ["/tmp/a.txt", "/tmp/b.txt"])
        // …and the step passed (was `.error` under the old stub).
        #expect(report.steps.first(where: { $0.id == "drop" })?.result == .pass)
    }

    @Test func dragWithoutToFilesDoesNotRouteToFileDrag() throws {
        let log = DriverCallLog()
        var driver = FakeDriver(nodes: [["role": "AXButton", "identifier": "Src"],
                                        ["role": "AXButton", "identifier": "Dst"]])
        driver.callLog = log

        var args = ActionArgs()
        args.to = Selector(identifier: "Dst")
        let step = Step(id: "elemdrag", action: .drag, level: .happyPath,
                        target: Selector(identifier: "Src"), args: args)

        let report = try run(step: step, driver: driver)

        // Element-to-element drag must NOT hit the file-drop path.
        #expect(log.fileDragCalls.isEmpty)
        #expect(report.steps.first(where: { $0.id == "elemdrag" })?.result == .pass)
    }
}
