# Platform Agents — Design Spec

**Date:** 2026-06-25
**Status:** Approved (brainstorm complete; ready for implementation planning)
**Repos affected:** `autopilot-core` (contract owner), `autopilot-ios`, `autopilot-android`

## Goal

Make iOS and Android into thin, core-controlled **agents** — the same architecture macOS already has — so that plan semantics (the execution loop, action dispatch, every assertion operator) live in **one** place instead of being re-implemented per platform. Core parses the plan and drives; each platform agent only supplies OS primitives and reports back.

## Terminology

The per-platform backend is called an **agent**, not a "runner" — in prose, module names, and docs (e.g. the Android `:agent` module, `AndroidAgent`). Core's orchestrator remains `PlanRunner` (it runs the plan; it is not a platform agent).

One carve-out for consistency: the **Swift type that conforms to `AppDriver` keeps the `…Driver` suffix**, because the shipped macOS type is already `MacOSDriver` and the protocol is `AppDriver`. So the iOS conformer is `IOSDriver` (the *role* is "the iOS agent"; the *type name* matches `MacOSDriver`). New non-conforming Swift/Kotlin pieces and module names use "agent." This avoids renaming the shipped `MacOSDriver` while honoring the agent naming everywhere it doesn't fight existing types.

## Background / why

`autopilot-core` already is the brain and already defines the agent contract:

- `Sources/AutopilotCore/Driver/AppDriver.swift` — `public protocol AppDriver`, ~25 methods. Its doc comment states core "depends only on this protocol and never on any platform API."
- Core owns `PlanParser`, `PlanRunner` (`run(_ plan:options:) throws -> Report`), `AssertionEngine`, targeting, `Reporter`.
- **macOS** (`MacOSDriver`) conforms to `AppDriver` and is driven by core's `PlanRunner`.
- **iOS and Android do NOT.** Each re-implements the entire loop + assertions standalone (~920-line `AutoPilotRunner.swift`, ~725-line `AutoPilotRunner.kt`). This triplicated, drift-prone logic is the problem this design removes.

**Stale doc to fix:** `AppDriver.swift` says "Android via Appium." Android is UiAutomator2/Espresso — never Appium. Fix the comment as part of this work.

## Architecture

```
        ┌──────────── autopilot-core (THE BRAIN) ─────────────┐
        │ PlanParser → PlanRunner loop → AssertionEngine →     │
        │ Reporter. Depends ONLY on the AppDriver protocol.    │
        └───────────────────────┬─────────────────────────────┘
              calls AppDriver    │   agent reports back
        ┌──────────────┬─────────┴───────────┐
   ┌────▼─────┐   ┌────▼─────┐         ┌──────▼──────────────┐
   │MacOSDriver│  │IOSDriver  │        │ AndroidAgent (Kotlin)│
   │ ✅ exists │  │ ❌ build  │        │ ❌ build — mirrors   │
   │ AX/CGEvent│  │ XCUITest  │        │ AppDriver + core's   │
   │           │  │           │        │ loop; conformance    │
   └──────────┘   └──────────┘         │ suite keeps it honest│
   Swift, real    Swift, real          └──────────────────────┘
   protocol       protocol             Kotlin parity (no Swift import)
```

- **macOS** — already conforms. No model change.
- **iOS** — Swift, so it conforms to the **real** `AppDriver` and reuses core's **real** `PlanRunner`. Its standalone agent collapses to ~25 primitive method bodies.
- **Android** — cannot import Swift in-process. Per decision, it uses **protocol parity**: a Kotlin `AppDriver` interface + a Kotlin port of core's `PlanRunner`, kept in lockstep with core by a shared plan + a conformance suite. No Swift-on-Android, no out-of-process transport.

## The agent surface (~25 AppDriver methods)

Each agent's entire job is these methods. The action/assertion logic is **not** re-written per platform — core's loop maps every `Action` and `AssertProperty` to `AppDriver` calls. Most primitive code already exists inside the current standalone agents; it is re-homed behind the protocol, not rewritten.

| `AppDriver` method | macOS ✅ | iOS (build) | Android (Kotlin parity) |
|---|---|---|---|
| **Lifecycle** launch / attach / attach(pid) | done | XCUIApplication launch/activate | `am start` + package; pid via pidof |
| terminate / activate | done | app.terminate / activate | force-stop; bring to front |
| **Permissions** hasAccessibility / hasScreenRecording / *instructions | done (TCC) | return `true` / "" (pre-granted) | return `true` / "" (pre-granted) |
| **Resolution** resolve / waitForPresence / matchCount / findAll | done | XCUIElement queries (exist) | UiSelector/By queries (exist) |
| **Actions** perform(action:args:on:) [click, doubleClick, rightClick, press, type, keyPress, setValue, scroll, menu, waitFor, screenshot] | done | tap/doubleTap/press/typeText/swipe (exist) | click/longClick/setText/swipe (exist, minus MainActivity hooks) |
| point(for:) / performDrag(from:to:) | done | frame center; press-drag (exist) | bounds center; device.drag (exist) |
| selectMenuPath | done (menu bar) | best-effort nav-bar; else no-op | options menu; else no-op |
| **Property read** readProperty [value, title, enabled, focused, position, size, marked, count] | done | value/label/isEnabled/hasFocus/frame | text/isChecked/isEnabled/isFocused/bounds |
| **Visual** captureElementScreenshot / captureMainDisplay | done (ScreenCaptureKit) | XCUIScreen.screenshot | UiDevice screenshot |
| captureRegion / samplePixel / sampleRegion / loadPNG | done | **return nil/false** → drives SKIPs | **return nil/false** → drives SKIPs |
| **Inspection** dumpTree / suggestSelectors | done | flatten tree / [] | flatten tree / [] |

**Enumerated contract (from core source):**
- `Action`: launch, terminate, click, doubleClick, rightClick, press, menu, type, keyPress, setValue, scroll, drag, assertPixel, assertRegion, snapshot, waitFor, screenshot, assert, wait.
- `AssertProperty`: value, title, enabled, focused, position, size, marked, count.
- Assert ops: equals, notEquals, contains, matches, exists, notExists, greaterThan, lessThan.

### Consequences

1. **The standalone agents shrink; the duplicated brain is deleted.** Each `executeStep` switch, plus `compare()` / `assertString()` / `assertNumeric()` and the plan-walking loop, are removed — core does dispatch + comparison. What remains is the primitive method bodies above.
2. **The 3 SKIPs become automatic.** No hand-written `if action in [assertPixel, assertRegion, snapshot] skip`. Visual-capture methods return nil/false; core's existing `runAssertPixel` / `runAssertRegion` / `runSnapshot` already interpret "driver can't capture → skip." 75 PASS + 3 SKIP is produced uniformly by core.
3. **Platform quirks survive, relocated.** Permissions, menu handling, focus/timing tricks move from the middle of a bespoke loop into the corresponding `AppDriver` method, called by core at the right time.

## Android Kotlin parity agent

New **`:agent` Gradle library module** in `autopilot-android` (replaces the welded `androidTest` code), containing:
- `AppDriver` — Kotlin interface mirroring the Swift protocol's ~25 methods (same names, same semantics).
- `AndroidAgent` — implements it with **pure UIAutomator**. Drops the three calls into the sample app's `MainActivity` (`simulateDoubleTap`, `requestFocusOnField`, `scrollInnerScrollViewToEnd`); those become gesture-based and may need timing tuning. The sample app keeps its `MainActivity` helpers for its own purposes; the agent does not depend on them.
- `PlanRunner` — Kotlin port of core's loop: same dispatch, same operators, same skip-on-nil-capture behavior.
- `Plan` / `Step` / `Selector` / `Assertion` / `Report` — Kotlin data classes aligned field-for-field with core's Codable types (existing `PlanModel.kt`, reconciled).

### Conformance suite (keeps the mirror from drifting)

- **Unified 78-step plan** is the cross-platform contract already. Add **golden `Report` fixtures**: core (Swift) runs the plan → `report.json`; Android's `PlanRunner` must produce a structurally-equal report (same per-step pass/skip verdicts).
- **Operator truth-table**: one shared JSON of `(actual, op, expected) → bool` cases, asserted by BOTH a Swift test in core and a Kotlin test in `:agent`. Changing an operator's meaning on one side without the other turns this red.

## Plan input API

Each agent's public entry accepts a plan three ways (same shape on both platforms; mirrors the macOS CLI):
- `run(plan: Plan)` — core/typed entry point (most testable).
- `run(json: …)` — thin wrapper: decode → `run(plan:)`.
- bundled-resource convenience (`run(resourceName:)` / asset) — used by the sample app's own tests.

On iOS, the agent **returns `StepResult`/`Report` and never calls `XCTFail`**. Assertions belong to core; the thin XCUITest wrapper does the `XCTAssert` on results — matching how Android's wrapper already works. (The agent still uses `XCUIApplication`/`XCUIElement` — that is the driver API, not assertion coupling, and is fine.)

## Sample-app wiring & testing

- **iOS** — `TestHostAppUITests` becomes a thin entry point: build `IOSDriver`, hand it + the bundled plan to core's `PlanRunner`, `XCTAssert(report.failures == 0)`.
- **Android** — `androidTest` builds `AndroidAgent` + the Kotlin `PlanRunner`, runs the bundled plan, `assertTrue(report.failures.isEmpty())`.
- **Regression gate (unchanged):** macOS 78/78, iOS 75 PASS + 3 SKIP, Android 75 PASS + 3 SKIP — already CI-enforced on all three (incl. the self-hosted macOS runner). Plus the new conformance tests.

## Migration order

1. **iOS first** (lower risk — same language, real core). Build `IOSDriver`; collapse `AutoPilotRunner.swift` onto core's `PlanRunner`; rewire the test target; confirm 75+3.
2. **Android second.** Stand up `:agent` (Kotlin `AppDriver` + `AndroidAgent` + `PlanRunner` port + aligned models); pure-UIAutomator; add conformance suite; confirm 75+3.
3. **Cleanup.** Fix the stale `AppDriver.swift` "Appium" comment; update docs to the agent model and the "agent, not runner" naming.

Each step ends green on its platform's existing CI gate; nothing merges broken.

## Open items (adjustable during implementation)

- Exact gesture replacements for the dropped Android `MainActivity` hooks may need timing tuning to keep double-tap/focus/scroll reliable under pure UIAutomator.
- Final package/module names and the precise `run(...)` overload signatures can be refined during planning.
- Field-by-field reconciliation between Kotlin `PlanModel.kt` and core's Codable model is a planning task.

## Out of scope

- Publishing the agents to a registry (Maven / tagged SwiftPM). Source modules in-repo only; published artifacts are a possible follow-up.
- GitHub Releases with downloadable artifacts for iOS/Android (separate gate, needs explicit go).
- New dedicated agent repos. Agents live in their existing platform repos.
