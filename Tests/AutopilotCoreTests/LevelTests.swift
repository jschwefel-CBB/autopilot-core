import Testing
import Foundation
@testable import AutopilotCore

@Suite struct StepLevelEnumTests {
    @Test func rankOrdersHappyPathBelowIntegrationBelowBreakIt() {
        #expect(StepLevel.happyPath.rank == 0)
        #expect(StepLevel.integrationSuite.rank == 1)
        #expect(StepLevel.tryToBreakIt.rank == 2)
        #expect(StepLevel.happyPath < .integrationSuite)
        #expect(StepLevel.integrationSuite < .tryToBreakIt)
        #expect(StepLevel.happyPath < .tryToBreakIt)
    }

    @Test func allCasesPresent() {
        #expect(StepLevel.allCases == [.happyPath, .integrationSuite, .tryToBreakIt])
    }

    @Test func codableRoundTrip() throws {
        for lvl in StepLevel.allCases {
            let data = try JSONEncoder().encode(lvl)
            let back = try JSONDecoder().decode(StepLevel.self, from: data)
            #expect(back == lvl)
        }
    }
}

@Suite struct LevelParseValidationTests {
    func parse(_ json: String) throws -> Plan {
        try PlanParser().parse(data: json.data(using: .utf8)!,
                               baseDirectory: URL(fileURLWithPath: "/tmp"))
    }

    @Test func missingLevelIsFriendlyError() {
        let json = """
        {"schemaVersion":"1.1","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"c1","action":"screenshot"}]}
        """
        do {
            _ = try parse(json)
            Issue.record("expected a PlanError for missing level")
        } catch let e as PlanError {
            let msg = e.description
            #expect(msg.contains("c1"))
            #expect(msg.contains("level"))
            #expect(msg.contains("happyPath"))
            #expect(msg.contains("integrationSuite"))
            #expect(msg.contains("tryToBreakIt"))
        } catch { Issue.record("wrong error type: \(error)") }
    }

    @Test func invalidLevelValueIsFriendlyError() {
        let json = """
        {"schemaVersion":"1.1","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"c2","level":"wat","action":"screenshot"}]}
        """
        do {
            _ = try parse(json)
            Issue.record("expected a PlanError for invalid level")
        } catch let e as PlanError {
            let msg = e.description
            #expect(msg.contains("c2"))
            #expect(msg.contains("wat"))
            #expect(msg.contains("happyPath"))
        } catch { Issue.record("wrong error type: \(error)") }
    }

    @Test func allThreeValidLevelsParse() throws {
        let json = """
        {"schemaVersion":"1.1","name":"x","target":{"bundleId":"a"},
         "steps":[
           {"id":"h","level":"happyPath","action":"screenshot"},
           {"id":"i","level":"integrationSuite","action":"screenshot"},
           {"id":"b","level":"tryToBreakIt","action":"screenshot"}
         ]}
        """
        let plan = try parse(json)
        #expect(plan.steps.map(\.level) == [.happyPath, .integrationSuite, .tryToBreakIt])
    }
}

@Suite struct LevelBreakdownTests {
    func r(_ id: String, _ outcome: StepOutcome, _ level: StepLevel) -> StepResult {
        StepResult(id: id, result: outcome, durationMs: 1, level: level)
    }

    @Test func perTierTalliesAreExact() {
        let b = LevelBreakdown(steps: [
            r("a", .pass, .happyPath), r("b", .pass, .happyPath), r("c", .fail, .happyPath),
            r("d", .pass, .integrationSuite),
            r("e", .pass, .tryToBreakIt), r("f", .error, .tryToBreakIt),
        ])
        #expect(b.happyPath == OutcomeCounts(pass: 2, fail: 1))
        #expect(b.integrationSuite == OutcomeCounts(pass: 1))
        #expect(b.tryToBreakIt == OutcomeCounts(pass: 1, error: 1))
    }

    @Test func cumulativeViewsSubsumeLowerTiers() {
        let b = LevelBreakdown(steps: [
            r("a", .pass, .happyPath),
            r("d", .pass, .integrationSuite),
            r("e", .pass, .tryToBreakIt),
        ])
        #expect(b.cumulativeAtHappyPath.total == 1)
        #expect(b.cumulativeAtIntegration.total == 2)   // happy + integration
        #expect(b.cumulativeAtTryToBreakIt.total == 3)  // all three
        #expect(b.cumulativeAtTryToBreakIt.pass == 3)
    }
}

@Suite struct LevelRunFilterTests {
    /// A plan with one step at each tier; FakeDriver passes every step.
    func threeTierPlan() -> Plan {
        Plan(schemaVersion: "1.1", name: "tiers", target: TargetApp(bundleId: "a"), steps: [
            Step(id: "hp", action: .screenshot, level: .happyPath),
            Step(id: "it", action: .screenshot, level: .integrationSuite),
            Step(id: "tb", action: .screenshot, level: .tryToBreakIt),
        ])
    }

    func run(maxLevel: StepLevel?) throws -> Report {
        let driver = FakeDriver(nodes: [["role": "AXWindow"]])
        let runner = PlanRunner(driver: driver, clock: SystemClock())
        let opts = RunOptions(keepGoing: true,
                              artifactsDir: FileManager.default.temporaryDirectory
                                  .appendingPathComponent("ap-level-\(UUID().uuidString)"),
                              maxLevel: maxLevel)
        return try runner.run(threeTierPlan(), options: opts)
    }

    @Test func noCapRunsAllThree() throws {
        let rep = try run(maxLevel: nil)
        let ran = rep.steps.filter { $0.result != .skipped }.map(\.id)
        #expect(ran == ["hp", "it", "tb"])
    }

    @Test func capAtHappyPathSkipsHigherTiers() throws {
        let rep = try run(maxLevel: .happyPath)
        let ran = rep.steps.filter { $0.result != .skipped }.map(\.id)
        let skipped = rep.steps.filter { $0.result == .skipped }.map(\.id)
        #expect(ran == ["hp"])
        #expect(skipped == ["it", "tb"])
    }

    @Test func capAtIntegrationRunsHappyAndIntegration() throws {
        let rep = try run(maxLevel: .integrationSuite)
        let ran = rep.steps.filter { $0.result != .skipped }.map(\.id)
        let skipped = rep.steps.filter { $0.result == .skipped }.map(\.id)
        #expect(ran == ["hp", "it"])
        #expect(skipped == ["tb"])
    }

    @Test func reportCarriesLevelBreakdown() throws {
        let rep = try run(maxLevel: nil)
        let b = try #require(rep.levelBreakdown)
        #expect(b.happyPath.pass == 1)
        #expect(b.integrationSuite.pass == 1)
        #expect(b.tryToBreakIt.pass == 1)
        #expect(b.cumulativeAtTryToBreakIt.pass == 3)
    }

    @Test func stepResultsEchoTheirLevel() throws {
        let rep = try run(maxLevel: nil)
        #expect(rep.steps.first { $0.id == "it" }?.level == .integrationSuite)
        #expect(rep.steps.first { $0.id == "tb" }?.level == .tryToBreakIt)
    }
}
