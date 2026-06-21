import Testing
import Foundation
@testable import AutopilotCore

@Suite struct IncludeResolutionTests {
    /// Write JSON to a temp dir and return (dir, fileURL).
    func writePlan(_ json: String, name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try json.data(using: .utf8)!.write(to: url)
        return url
    }

    func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("autopilot-inc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func prependsIncludedSteps() throws {
        let dir = try tempDir()
        _ = try writePlan("""
        {"schemaVersion":"1.0","name":"setup","target":{"bundleId":"a"},
         "steps":[{"id":"launch","action":"launch"}]}
        """, name: "setup.json", in: dir)
        let mainURL = try writePlan("""
        {"schemaVersion":"1.0","name":"main","include":["setup.json"],
         "target":{"bundleId":"a"},
         "steps":[{"id":"shot","action":"screenshot"}]}
        """, name: "main.json", in: dir)

        let data = try Data(contentsOf: mainURL)
        let plan = try PlanParser().parse(data: data, baseDirectory: dir)
        #expect(plan.steps.map(\.id) == ["launch", "shot"])
        #expect(plan.include == nil) // flattened away after resolution
    }

    @Test func detectsCycle() throws {
        let dir = try tempDir()
        _ = try writePlan("""
        {"schemaVersion":"1.0","name":"a","include":["b.json"],
         "target":{"bundleId":"a"},"steps":[{"id":"a1","action":"screenshot"}]}
        """, name: "a.json", in: dir)
        let bURL = try writePlan("""
        {"schemaVersion":"1.0","name":"b","include":["a.json"],
         "target":{"bundleId":"a"},"steps":[{"id":"b1","action":"screenshot"}]}
        """, name: "b.json", in: dir)
        let data = try Data(contentsOf: bURL)
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: data, baseDirectory: dir)
        }
    }

    @Test func missingIncludeThrows() throws {
        let dir = try tempDir()
        let mainURL = try writePlan("""
        {"schemaVersion":"1.0","name":"main","include":["nope.json"],
         "target":{"bundleId":"a"},"steps":[{"id":"s","action":"screenshot"}]}
        """, name: "main.json", in: dir)
        let data = try Data(contentsOf: mainURL)
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: data, baseDirectory: dir)
        }
    }
}
