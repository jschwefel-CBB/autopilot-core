import Foundation

/// A passive tap on a plan run. `PlanRunner` calls these as it executes so a
/// UI (the cockpit) can light up live per-step progress without reimplementing
/// the run loop. All methods have empty default implementations, so a conformer
/// implements only the callbacks it needs. Platform-pure (Foundation only).
public protocol RunObserver: AnyObject, Sendable {
    /// Called once before the first step, after preflight/launch succeed.
    func runWillStart(plan: Plan)
    /// Called immediately before a step is attempted (or skipped). `index` is
    /// 0-based; `total` is `plan.steps.count`.
    func stepWillStart(_ step: Step, index: Int, of total: Int)
    /// Called once per step as its `StepResult` is recorded — including steps
    /// skipped by the level filter and steps that errored. Fires in plan order.
    func stepDidFinish(_ result: StepResult, index: Int)
    /// Called once after the report is finalized.
    func runDidFinish(_ report: Report)
}

public extension RunObserver {
    func runWillStart(plan: Plan) {}
    func stepWillStart(_ step: Step, index: Int, of total: Int) {}
    func stepDidFinish(_ result: StepResult, index: Int) {}
    func runDidFinish(_ report: Report) {}
}
