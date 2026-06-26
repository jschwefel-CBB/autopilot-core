# Platform Agents — Design Spec

**Date:** 2026-06-25 (reconciled 2026-06-26)
**Status:** Approved (brainstorm complete; ready for implementation planning)
**Repos affected:** `autopilot-core` (contract owner), `autopilot-ios`, `autopilot-android`

## Goal

Core speaks ONE abstract command vocabulary; each platform **agent translates** those abstract commands to its own platform-native API. Core says `click(element X)` / `assert(value of Y equals Z)` — platform-blind. The Android agent translates that to UiAutomator; the iOS agent translates the *same* abstract command to XCUITest; macOS to the Accessibility API / CGEvent. Core never knows or cares *how* a platform performs a command — it issues the abstract command and reads back the abstract result.

This puts plan semantics (the execution loop, command dispatch, every assertion operator) in **one** place — core — instead of being re-implemented per platform. The agents are translators, not re-implementations.

**Platforms are co-equal, not ranked.** Each platform has its own capability set. Some abstract commands map to a real platform action; some map to nothing (the platform has no equivalent); some platforms support a command the others cannot. A platform difference is **expected and normal**, never a deficiency. (Example: macOS has a real menu bar and can translate a menu-bar command; iOS/Android have no menu bar, so that command is simply not in their vocabulary — that is correct, not a gap.)

### Capability negotiation — core only ever issues translatable commands

Core must **never** issue a command a platform cannot translate; an "unsupported command" must never reach an agent at runtime. This is guaranteed by up-front capability negotiation:

1. **Each agent advertises its capability set** — the abstract commands it translates — as the single source of truth for its own vocabulary (the agent IS its vocabulary; it cannot drift from what it actually implements). Add `capabilities()` to the `AppDriver` contract.
2. **Core validates the plan against the target platform's advertised capabilities BEFORE the run starts.** A command that platform can't translate is classified at validation time — marked not-applicable (skipped pre-run) per the plan, or surfaced to the author — so by the time core issues commands, every command is guaranteed translatable.
3. A "skip" is therefore a **pre-run not-applicable classification**, NOT a mid-run catch. (Contrast the old per-runner behavior, where a runner received `assertPixel` and hand-coded a skip on the fly. That is removed.)

Because the whole family is built together, no capability discrepancy is *expected*. Core cross-checking the agent's advertised set against the contract's known command set is therefore a **development-time correctness assertion** — a cheap guard that turns a wiring mistake (a mistyped/forgotten capability) into an immediate, located build/conformance error instead of a confusing runtime failure. Capability names are a **typed, shared constant** (a Swift enum on the contract side, mirrored exactly by the Android Kotlin enum), so a mismatch fails at compile / conformance-test time, not via runtime string comparison.

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
- `AppDriver` — Kotlin interface mirroring the Swift protocol's ~25 methods (same names, same semantics) **plus `capabilities()`** returning the agent's translatable command set.
- `AndroidAgent` — implements it with **pure UIAutomator**. Drops the three calls into the sample app's `MainActivity` (`simulateDoubleTap`, `requestFocusOnField`, `scrollInnerScrollViewToEnd`); those become gesture-based and may need timing tuning. The sample app keeps its `MainActivity` helpers for its own purposes; the agent does not depend on them.
- `PlanRunner` — Kotlin port of core's loop: same dispatch, same operators, same capability negotiation.
- `Capability` — a Kotlin enum mirroring core's Swift `Capability` enum **exactly** (the shared, typed vocabulary). The conformance suite asserts the two enums match.
- `Plan` / `Step` / `Selector` / `Assertion` / `Report` — Kotlin data classes aligned field-for-field with core's Codable types (existing `PlanModel.kt`, reconciled).
- **External-app driving** (already prototyped, see "Already built" below): the agent can launch and drive **any installed app** named by `plan.target.bundleId`, not just the bundled sample — load an external plan from a device path, resolve+launch the target package, scope all queries to it. This is what makes the agent usable against real apps (e.g. ScopeDOPE).

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
- **Regression gate (unchanged):** macOS 78/78, iOS 75 PASS + 3 SKIP, Android 75 PASS + 3 SKIP — already CI-enforced on all three (incl. the self-hosted macOS runner). Plus the new conformance tests. Note: the iOS/Android "3 SKIP" are now **pre-run not-applicable classifications** (the visual-capture commands are not in those platforms' advertised capability sets), produced uniformly by core's validation — not three separate hand-coded skip-lists.

## Documentation (kept true at every step)

User-facing docs (READMEs, `autopilot-macos/docs/AUTHORING.md`, `docs/MANUAL.md`) today describe the old per-platform "runner" model; none mention the agent architecture. They are updated **per platform, as each migration step lands** — never up front — so a doc never describes code that does not yet exist (the same "mark target vs shipped" discipline the v2 doc audit enforced). The **design spec is the implementing agent's source of truth**, not the old user docs.

Note: not every "runner" mention is wrong. Core's orchestrator is and stays `PlanRunner`; those references are correct. Only the per-platform-backend sense of "runner" becomes "agent." Each step's doc edit must distinguish the two (inventory which mentions are `PlanRunner` vs platform-backend before editing).

## Already built (Android external-app driving — 2026-06-26)

Ahead of the full agent refactor, the Android agent gained **external-app driving** on branch `feat/external-app-driving` (autopilot-android, commit `a8e53c8`): `AutoPilotRunner(planPath, targetPackageOverride)` loads an external plan from a device path, resolves the target package (`override > plan.target.bundleId > instrumentation target`), launches it via its launcher intent, and scopes all queries to it; fixture-only setup is gated to the bundled host app; a `launch` action and an `ExternalPlanTest` (`am instrument -e plan <path> [-e target <pkg>]`) entry were added. Compiles + assembles green (build with Android Studio's JDK 21, not the system JDK 26). On-device verification pending (needs an emulator/device with the target app installed). This is the capability that makes the agent usable against real apps; the full refactor below subsumes it into the agent model.

## Build order — co-equal platforms, no ranking

iOS and Android are **equal partners**; neither is "first" or "lower priority." Each translates the abstract command set to its own platform and has capabilities the other lacks — that divergence is the point of the architecture, not a gap to be sequenced around. Build them in parallel (or in whatever order is convenient); the contract, capability vocabulary, and conformance suite keep them honest against core and each other.

Each platform's definition of done: agent built; advertises its `capabilities()`; core's pre-run validation passes for the unified plan on that platform; that platform's CI gate green (macOS 78, iOS/Android 75+3); that platform's user-facing docs flipped to the agent model.

Cross-cutting work (do once, shared by both):
- Define the typed `Capability` enum on the core contract; add `capabilities()` to `AppDriver`; add core's pre-run plan-vs-capability validation.
- The Android Kotlin mirror (`AppDriver` interface + `Capability` enum + `PlanRunner` port + aligned models) and the conformance suite (golden reports + operator truth-table + enum-parity assertion).
- **Cleanup:** fix the stale `AppDriver.swift` "Appium" comment; sweep core/macOS user-facing docs (README, AUTHORING, MANUAL) for the cross-platform agent model and the "agent, not runner" naming (preserving correct `PlanRunner` references).

Nothing merges broken: each platform ends green on its existing CI gate.

## Open items (adjustable during implementation)

- Exact gesture replacements for the dropped Android `MainActivity` hooks may need timing tuning to keep double-tap/focus/scroll reliable under pure UIAutomator.
- Final package/module names and the precise `run(...)` overload signatures can be refined during planning.
- Field-by-field reconciliation between Kotlin `PlanModel.kt` and core's Codable model is a planning task.

## Out of scope

- Publishing the agents to a registry (Maven / tagged SwiftPM). Source modules in-repo only; published artifacts are a possible follow-up.
- GitHub Releases with downloadable artifacts for iOS/Android (separate gate, needs explicit go).
- New dedicated agent repos. Agents live in their existing platform repos.
