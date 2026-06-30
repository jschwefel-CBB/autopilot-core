# Step `level` + Comprehensive (AX + Vision) Testing — Design Spec

**Date:** 2026-06-29
**Repo:** `autopilot-core` (canonical schema + Swift types + JSON Schema artifact). The macOS/iOS/Android runners **consume `autopilot-core` as a Swift package dependency** (they do NOT vendor their own copy of `Step`/`Plan`/`PlanParser`), so the Swift schema change happens **once** here; runners pick it up by bumping their `autopilot-core` dependency pin.
**Status:** Phase 1 IMPLEMENTED on branch `feat/step-level-coverage-tier` (core + schema + tests, 97 tests green). Phases 2–3 (runner dependency bumps, plan-file migration, `AUTHORING.md`) pending.

## Architecture note (corrected from initial draft)

- `Step`, `Plan`, `PlanParser`, `PlanRunner`, `Report` are **canonical in `autopilot-core` only**. `autopilot-macos` depends on the published `autopilot-core` package (`from: "2.0.0"`) and does not redeclare them. So there is **no three-way Swift edit** — the runner repos only thread `step.level` onto their `StepResult` construction and (optionally) honor `RunOptions.maxLevel`; both come from core.
- A **required** new field is a **breaking** change. Decision: release `autopilot-core` **3.0.0** (honest semver). Runner repos bump their pin to `3.0.0` when they adopt. **Tagging waits for explicit "go" per the release-gate rule.**
- The JSON Schema artifact `plan.schema.json` was previously only in `autopilot-macos`. Decision: **canonical copy now lives in `autopilot-core/schema/plan.schema.json`** (authored here with `level`). The macOS copy (`autopilot-macos/schema/plan.schema.json`, referenced by its docs) is updated to match in phase 2; whether macOS references core's copy or keeps a synced local one is a phase-2 cleanup. (Note: `autopilot-macos/autopilot/` is a stale nested git clone — its schema copy is untracked detritus, left alone.)

---

## 1. Goal

Two related additions to AutoPilot's authoring model, driven by one principle: **a test plan should be comprehensive — cover the expected flow, the broader integration, and the adversarial cases; and verify both structure (accessibility) and rendering (vision) where it adds signal.**

1. **`level` — a per-step, required coverage-tier field** with three values forming a cumulative hierarchy: `happyPath` ⊂ `integrationSuite` ⊂ `tryToBreakIt`. Machine-readable, so a run *at a level* selects that tier and the tiers it subsumes, and the report breaks down pass/fail per tier.
2. **A "comprehensive testing" authoring convention** (guide section, not schema): target via AX, and where it adds signal also verify via vision (`snapshot` / `assertRegion` / `assertPixel`), so a plan tests the accessibility tree *and* what actually painted.

The first is a schema change (Swift types + the `plan.schema.json` artifact). The second is documentation that leverages already-shipped capabilities (vision selector + visual assertions). They ship together as one coherent "how to write a good plan" story.

---

## 2. The `level` coverage hierarchy

Three tiers. A step is tagged at **exactly one** tier (no duplication). A run *at* a tier executes that tier **plus every tier below it** — cumulative coverage, so each test case is written once and reused by the higher tiers.

```
happyPath   ⊂   integrationSuite   ⊂   tryToBreakIt
(innermost)     (middle)               (full set)
```

| Tier | Meaning | The question it answers |
|---|---|---|
| **`happyPath`** | The expected flow works — valid input, the feature does what it's supposed to. The minimal "is it alive and correct" set. | "Does it do what I want it to?" |
| **`integrationSuite`** | The middle layer — features working together, realistic end-to-end flows, broader functional coverage beyond the single happy path. | "Do the pieces work together?" |
| **`tryToBreakIt`** | Adversarial — bad data, boundaries, out-of-order/rapid actions, exercise everything; assert the app refuses/degrades **gracefully**. | "Can we break it?" |

**Run semantics (cumulative, subsuming downward):**

| Run at level | Executes steps tagged | Skips |
|---|---|---|
| `happyPath` | `happyPath` | integrationSuite, tryToBreakIt |
| `integrationSuite` | `happyPath` + `integrationSuite` | tryToBreakIt |
| `tryToBreakIt` | `happyPath` + `integrationSuite` + `tryToBreakIt` | (nothing) |

This is the classic smoke ⊂ regression ⊂ full gating model. CI maps naturally: PR → `happyPath`, merge → `integrationSuite`, nightly → `tryToBreakIt`.

---

## 3. Design decisions (settled with the user)

| Decision | Choice | Rationale |
|---|---|---|
| Granularity | **Per-step** | One feature's plan interleaves all three tiers in one file; "do it right → succeeds", "exercise the integration", "do it wrong → rejected cleanly". |
| Implementation | **Real schema field** | The point is to *run* and *report* by tier and let CI gate per tier. A naming convention can't do that. |
| Field key | **`level`** | Holds a ranked, cumulative hierarchy — reads as a level, not a boolean flag or a 2-way intent. |
| Values | **`happyPath`**, **`integrationSuite`**, **`tryToBreakIt`** | The user's terms (`integrationSuite` is the named middle tier). |
| Direction | **`happyPath` is innermost/minimal; `tryToBreakIt` is the full set** | happyPath = narrowest "does it work"; tryToBreakIt = widest "everything". |
| Pass semantics | **Label only — does NOT invert pass/fail** | A `tryToBreakIt` step still passes by asserting the app *refused correctly* (error shown, button stayed disabled, value rejected). No expected-failure magic; the assertions already express "should reject." |
| Required-ness | **Hard-required** | Schema bump makes `level` mandatory on every step. No ambiguous untagged steps. Existing plans must be migrated (small, known set — see §7). |
| Default when absent | **None — absence is an error** | A missing `level` throws a friendly `PlanError.decode` (see §4.3). Authors and AI agents must choose a tier deliberately. |
| Schema version | **Bump minor** (`schemaVersion`) | This is a breaking, mandatory-field change; the version must move. Exact value in §6. |

---

## 4. Schema change (`autopilot-core`)

### 4.1 New enum — `Plan/Level.swift`

```swift
/// The coverage tier of a step, forming a cumulative hierarchy:
/// happyPath ⊂ integrationSuite ⊂ tryToBreakIt. A run AT a level executes that
/// level and every level below it. This is a coverage LABEL — it does NOT change
/// pass/fail semantics. A `tryToBreakIt` step still passes by asserting the app
/// refused correctly (e.g. an error message appears, a submit button stays
/// disabled, a bad value is rejected).
public enum StepLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case happyPath          // innermost: the expected flow works
    case integrationSuite   // middle: features working together
    case tryToBreakIt       // full set: adversarial / boundary

    /// Rank for cumulative subsumption. A run at level L includes all steps
    /// whose level.rank <= L.rank.
    public var rank: Int {
        switch self {
        case .happyPath: return 0
        case .integrationSuite: return 1
        case .tryToBreakIt: return 2
        }
    }
    public static func < (a: StepLevel, b: StepLevel) -> Bool { a.rank < b.rank }
}
```

### 4.2 `Step` gains a REQUIRED field — `Plan/Plan.swift`

```swift
public struct Step: Codable, Equatable, Sendable {
    public var id: String
    public var action: Action
    public var level: StepLevel              // <-- NEW, REQUIRED (non-optional)
    public var target: Selector?
    public var args: ActionArgs?
    public var assert: Assertion?
    public var timeoutMs: Int?
    public var captureTarget: Bool?
    public init(id: String, action: Action, level: StepLevel,   // <-- required, no default
                target: Selector? = nil, args: ActionArgs? = nil,
                assert: Assertion? = nil, timeoutMs: Int? = nil,
                captureTarget: Bool? = nil) {
        self.id = id; self.action = action; self.level = level
        self.target = target; self.args = args; self.assert = assert
        self.timeoutMs = timeoutMs; self.captureTarget = captureTarget
    }
}
```

Because `level` is **non-optional**, synthesized `Codable` already makes a missing key a decode error and an invalid string a decode error. §4.3 upgrades both into friendly, step-scoped messages.

### 4.3 Friendly validation — `Plan/PlanParser.swift` (Q2 = both human + agent readable)

`PlanParser` already rejects non-functional fields with step-scoped `PlanError.decode("step \(id): …")`. The raw Codable errors for `level` are cryptic — e.g. *"keyNotFound CodingKeys(stringValue: \"level\")"* or *"Cannot initialize StepLevel from invalid String value wat"* — with no step id and no list of valid values. An AI coding agent generating plans needs an actionable message to self-correct. So:

- **Missing `level`:**
  `PlanError.decode("step \(id): missing required field `level` — use happyPath, integrationSuite, or tryToBreakIt")`
- **Invalid `level` value:**
  `PlanError.decode("step \(id): invalid level '\(bad)' — use happyPath, integrationSuite, or tryToBreakIt")`

Implementation: parse steps in a way that catches the per-key error and re-throws with the step id and the valid-value list. (Either a light pre-validation pass over the raw JSON before `decode`, or a custom `init(from:)` on `Step` for just this field. Pre-validation pass is simpler and keeps `Step` on synthesized Codable — preferred.)

### 4.4 `StepResult` echoes the level — `Report/Report.swift`

```swift
public struct StepResult: Codable, Sendable {
    public var id: String
    public var result: StepOutcome
    public var durationMs: Int
    // ... existing fields (expected, actual, message, screenshot, axDump) ...
    public var level: StepLevel              // <-- NEW, required
    // init gains `level: StepLevel`
}
```

### 4.5 Typed report breakdown — `Report/Report.swift` (Q3 = typed)

Overall `result` semantics are **unchanged** (any `fail`/`error` ⇒ that). ADD a typed per-tier breakdown:

```swift
public struct OutcomeCounts: Codable, Sendable {
    public var pass: Int; public var fail: Int; public var error: Int; public var skipped: Int
    public var total: Int { pass + fail + error + skipped }
}

public struct LevelBreakdown: Codable, Sendable {
    /// Counts for steps tagged exactly at each tier.
    public var happyPath: OutcomeCounts
    public var integrationSuite: OutcomeCounts
    public var tryToBreakIt: OutcomeCounts
    /// Cumulative view: coverage achieved when running AT each level
    /// (i.e. that tier plus all lower tiers). Mirrors the run semantics.
    public var cumulativeAtHappyPath: OutcomeCounts        // = happyPath
    public var cumulativeAtIntegration: OutcomeCounts      // = happyPath + integrationSuite
    public var cumulativeAtTryToBreakIt: OutcomeCounts     // = all three
}

// Report gains: public var levelBreakdown: LevelBreakdown?
// finalize() tallies steps by result.level into both the per-tier and cumulative views.
```

This is purely additive to the report; it does not affect `result`.

### 4.6 Run-level filtering (RunOptions)

`RunOptions` gains an optional `maxLevel: StepLevel?`. When set, the runner executes only steps with `step.level <= maxLevel` (by `rank`), and records the rest as `StepOutcome.skipped`. When unset, all steps run (equivalent to `maxLevel == .tryToBreakIt`). CLI surface: `autopilot run plan.json --level integrationSuite`.

> Note the empty-plan guard in `finalize()` (a plan that executed nothing reports `.error`, fail-closed). When `--level happyPath` filters everything out, that guard correctly flags it rather than reporting a false green.

---

## 5. JSON Schema artifact (`plan.schema.json`)

There is a real Draft-07 JSON Schema at `autopilot-macos/schema/plan.schema.json` (`$defs/step` with `properties`, `required`, conditional `allOf` per action). This is the **machine contract an AI coding agent validates generated plans against** — so it must move in lockstep:

1. Add to `$defs/step/properties`:
   ```json
   "level": {
     "type": "string",
     "enum": ["happyPath", "integrationSuite", "tryToBreakIt"],
     "description": "Coverage tier (cumulative: happyPath ⊂ integrationSuite ⊂ tryToBreakIt). Required."
   }
   ```
2. Add `"level"` to the step-level `required` array.
3. Bump the schema's version identifier to match §6.

(There appear to be two copies — `schema/plan.schema.json` and a nested `autopilot/schema/plan.schema.json`. Reconcile to one source of truth during implementation; do not leave them divergent.)

---

## 6. Schema version bump (Q1 = bump)

`schemaVersion` moves up a minor. Current value to be confirmed from the canonical plan/`$id` (sampling shows `"1.0"` in plan files) → **`"1.1"`**. The parser should accept `1.1` and, for `1.0` plans, emit a clear error directing the author to add `level` (rather than silently treating them as valid). Exact accept/reject policy for old versions is an implementation detail to confirm at build time, but a `1.0` plan must NOT silently pass.

---

## 7. Migration (hard-required ⇒ existing plans must be updated)

Hard-required means every existing source plan must tag every step. Known set (build-output copies regenerate, ignore them):

| Repo | Plan file(s) | Notes |
|---|---|---|
| `autopilot-macos` | `Fixtures/TestHostApp/test-all-capabilities.json` | canonical unified plan |
| `autopilot-ios` | `TestHostAppUITests/Resources/test-all-capabilities.json` | |
| `autopilot-android` | `app/src/androidTest/assets/{test-all-capabilities, compose-fixture, compose-scroll-fixture, compose-churn-fixture, compose-wrapper-fixture}.json` | 5 source fixtures |

Plus the `plan.schema.json` artifact(s) in §5. Each existing step gets `"level": "happyPath"` unless it is clearly integration/adversarial (most fixture steps are happy-path capability checks). This is a mechanical edit; ~7 files.

---

## 8. Runner changes (per platform)

Identical in shape across macOS / iOS / Android:

1. Read `step.level` (now always present — required).
2. If `RunOptions.maxLevel` is set and `step.level > maxLevel`, record `skipped` and continue.
3. Thread `step.level` onto the `StepResult`.
4. No change to how a step executes or how pass/fail is decided — `level` is coverage metadata.

The breakdown is computed in core (`finalize`); runners only thread the value and honor the filter.

---

## 9. Comprehensive testing convention (guide → `docs/AUTHORING.md`, Q4)

Documentation using capabilities **already in the schema** (`VisionSelector`, `assertPixel`, `assertRegion`, `snapshot`). The section states the practice, written to be read by a human **and** consumed by an AI coding agent generating plans:

- **Target via AX first.** Match on the most stable handle — on web, the element's `id` (exposed as `AXDOMIdentifier`; that driver enhancement is tracked separately, §11); on native, the accessibility identifier. Fall back to role+title only when no id exists.
- **Add vision where it adds signal.** AX confirms an element *exists and is named X*; it cannot confirm it *rendered correctly*. For appearance requirements — a chart drew, a badge is the right color, a layout didn't regress, an AX-opaque canvas/`<div>` control — add `snapshot` / `assertRegion` / `assertPixel`, or use a `vision` selector to find an AX-opaque target.
- **Tag every step's `level`.** Author the `happyPath` core, the `integrationSuite` cross-feature flows, and the `tryToBreakIt` adversarial cases in one plan. Each test once; higher tiers reuse lower ones via cumulative run semantics.

### 9.1 Worked example (illustrative JSON)

```json
{
  "schemaVersion": "1.1",
  "name": "login-comprehensive",
  "target": { "bundleId": "com.apple.Safari" },
  "steps": [
    { "id": "type-valid-user", "action": "type", "level": "happyPath",
      "target": { "identifier": "username" }, "args": { "text": "alice" } },
    { "id": "submit-valid", "action": "click", "level": "happyPath",
      "target": { "identifier": "submit" } },
    { "id": "assert-landed", "action": "assert", "level": "happyPath",
      "target": { "identifier": "dashboard-heading" },
      "assert": { "property": "value", "op": "exists" } },
    { "id": "snapshot-dashboard", "action": "snapshot", "level": "happyPath",
      "target": { "identifier": "dashboard-heading" },
      "args": { "reference": "refs/dashboard.png", "maxDiff": 0.02 } },

    { "id": "logout-then-relogin", "action": "click", "level": "integrationSuite",
      "target": { "identifier": "logout" } },
    { "id": "assert-back-at-login", "action": "assert", "level": "integrationSuite",
      "target": { "identifier": "login-form" },
      "assert": { "property": "value", "op": "exists" } },

    { "id": "submit-empty", "action": "click", "level": "tryToBreakIt",
      "target": { "identifier": "submit" } },
    { "id": "assert-error-shown", "action": "assert", "level": "tryToBreakIt",
      "target": { "identifier": "form-error" },
      "assert": { "property": "value", "op": "contains", "expected": "required" } },
    { "id": "assert-submit-disabled", "action": "assert", "level": "tryToBreakIt",
      "target": { "identifier": "submit" },
      "assert": { "property": "enabled", "op": "equals", "expected": "false" } }
  ]
}
```

Every `tryToBreakIt` step **passes** by asserting the app refused correctly — `level` labels coverage, it did not invert anything. `autopilot run --level happyPath` runs the first four steps; `--level integrationSuite` runs the first six; default/`--level tryToBreakIt` runs all nine.

---

## 10. Backward compatibility

- **Breaking by design.** `level` is hard-required; `1.0` plans without it are rejected with a friendly, step-scoped message. `schemaVersion` bumps to `1.1`.
- Migration is the ~7 known files in §7.
- Report consumers: `levelBreakdown` is additive/optional; `result` semantics unchanged.

---

## 11. Out of scope (tracked separately)

- **`AXDOMIdentifier` matching** for web content — makes web `id` selectors robust. Referenced by §9 but is its own change/spec when web-driving begins.
- Per-browser AX enablement (Chromium launch flag / Firefox specifics) — web-driving concern.
- Inverted/expected-failure pass logic — explicitly rejected (§3).

---

## 12. Implementation order (once approved)

1. `autopilot-core`: add `StepLevel`, required `Step.level`, friendly parse validation, `StepResult.level`, typed `LevelBreakdown` + `finalize` tally, `RunOptions.maxLevel` filter. Unit tests via FakeDriver. Purity gate stays green.
2. `plan.schema.json`: add `level` enum + required; reconcile the duplicate copies; bump version.
3. Thread `level` + honor `maxLevel` in each runner: macOS, iOS, Android (one small edit each).
4. Migrate the ~7 existing plan files (§7) — tag every step.
5. `docs/AUTHORING.md`: the comprehensive-testing + `level` section (§9), human- and agent-readable.
6. A sample comprehensive plan committed as a runnable reference (the §9.1 example).

---

## 13. Remaining confirmations (none blocking; defaults chosen)

These are settled with sensible defaults unless you object:

- **`schemaVersion` target = `1.1`** (minor bump from `1.0`). Confirm the exact string.
- **Old-version policy:** a `1.0` plan is rejected (not silently upgraded). Confirm.
- **CLI flag name `--level`** with the tier as value. Confirm.
- **Breakdown includes both per-tier and cumulative views** (§4.5). Confirm typed shape is what you want.
