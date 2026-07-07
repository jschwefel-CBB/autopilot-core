# AutoPilot → Demo Driver + Visual Builder + Web Test Platform

> **Implementation plan.** Cross-repo initiative rooted in `autopilot-core` (the schema
> source of truth). Phase 1 lands here; Phases 2–4 land in `autopilot-macos`,
> `autopilot-web` (new), and `autopilot-android`/`autopilot-ios`.
>
> **Status:** Phase 1 (core schema v1.2) — IN PROGRESS on branch `feature/demo-steps`.
> Phases 2–4 pending.

## Context

**Why:** AutoPilot today is a deterministic GUI-test driver — a JSON "plan" (no LLM at
runtime) drives apps via accessibility APIs on macOS/iOS/Android. The unified 78-step
plan runs 75 PASS + 3 SKIP on all three. This extends it in three directions at once,
unified by AutoPilot's north star: **automate GUI interaction by any means possible.**

1. **Demo driver** — reuse the deterministic runner to drive an app on-screen for a
   live demo or recorded screencast: human-visible pacing (pause / wait-for-X /
   keystroke speed), element highlighting, on-screen captions, frame capture. The plan
   becomes a *demo script* as easily as a test script.
2. **Visual builder** — the macOS Cockpit's **Author** tab is today a JSON-backed step
   *list* (add/reorder/delete + apply-selector). Its own source flags the gap:
   *"Full per-action visual editing is a later phase."* Finish it into a real
   click-to-build builder with per-action arg/assert forms — and make demo steps
   authorable in the same flow.
3. **Web as a 4th platform — a first-class TEST backend, plus demo mode** — greenfield
   (verified: no repo, no branch, no stash, no stray checkout anywhere; docs currently
   say "not a web testing tool" — **that stated boundary is reversed**: AutoPilot *is* a
   web testing tool). A new **`autopilot-web`** runner (TypeScript + Playwright) that
   reimplements the plan loop over the browser, exactly as Android reimplemented it in
   Kotlin/UiAutomator and iOS in Swift/XCUITest. It runs the same test plans headless in
   CI as a real parity gate (like the other three platforms), *and* supports the same
   demo/screencast mode. The single shared contract is the JSON plan schema.

**Coverage north star — "test all that is testable":** every action/assert that has a
web (or platform) equivalent gets exercised and asserted; only genuinely-impossible
steps skip (native menubar `menu`, native pixel capture `assertPixel`/`assertRegion`/
`snapshot`, host `exec`). Skip is the narrow exception, not a convenience.

**Decisions locked:**
- Web backend = **Playwright** (TS). Headless for CI, **headed** for live demos.
- Demo-pacing lives as **first-class core step types** (schema **v1.2**): new actions
  `highlight`, `caption`, `pace`; reuse existing `wait` / `waitFor` / `screenshot` /
  `captureTarget`. "One plan, all platforms; runners translate; skip-don't-branch."
- **All four platforms** (macOS / iOS / Android / new Web). macOS is the reference
  implementation; mobile + web implement or skip.

## Global Constraints

- **`autopilot-core` is the schema source of truth.** New actions/args land in Swift
  first (`Action.swift`, `ActionArgs`, `PlanParser`), then the JSON schema, then each
  runner mirrors them. Bump `schemaVersion` **1.1 → 1.2**; keep parsing 1.1.
- **Skip-don't-branch.** Demo/visual steps a backend can't do are **skipped**, never a
  hard failure. Test plans stay green everywhere.
- **Backward compatible.** A v1.1 plan must still parse and run. Demo actions are
  additive; `pace`/`highlight`/`caption` are no-ops in a normal (non-demo) test run.
- Fix the **existing schema/code drift** while here: `plan.schema.json` was missing
  `exec` (action) and `clipboard`/`stdout`/`stderr`/`exitCode` (assert props).
- Git author `jschwefel@coldboreballisticsllc.com` (never `-c`).
- **NEVER touch medit.** Never commit Apple team id `P46UWRKPX9`.
- **HARD release gate:** no tag / GitHub release / Homebrew-tap / npm publish without an
  explicit "go." Feature branches + PRs only until then.
- **Unified versioning at release.** ALL repos bump to ONE common version in the same
  release (`core`, `-macos`, `-ios`, `-android`, `-web` move together). Mobile jumps
  from `v2.0.0` to core's line. Web joins the same version train.
- Android runs export
  `ORG_GRADLE_JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`.

---

## Phase 1 — Core: schema v1.2 demo step types  ✅ (this branch)

**Repo:** `autopilot-core`. Branch: `feature/demo-steps`.

- **New actions** (`Sources/AutopilotCore/Plan/Action.swift`): `highlight` (glow a
  target for `holdMs`), `caption` (on-screen text), `pace` (set typing/step cadence).
- **New `ActionArgs`**: `holdMs`, `position`, `typeMsPerChar`, `stepDelayMs`.
- **Parser** (`Plan/PlanParser.swift`): `acceptedSchemaVersions = {1.1, 1.2}`;
  `highlight` joins `targetRequiringActions`; `caption` requires `args.text`; `pace`
  requires `typeMsPerChar` or `stepDelayMs`.
- **Runner** (`Runner/PlanRunner.swift`): `RunOptions.demoMode` (default false). Demo
  OFF ⇒ `highlight`/`caption` are passing no-ops, `pace` records cadence but nothing
  sleeps (tests stay fast/deterministic). Demo ON ⇒ `pace` sets a `DemoCadence`; `type`
  honors `typeMsPerChar`; each step honors `stepDelayMs`; `highlight`/`caption` call the
  driver hooks.
- **Driver** (`Driver/AppDriver.swift`): `showHighlight(_ element:holdMs:)` +
  `showCaption(_:position:holdMs:)` with empty default impls (the driver owns element
  geometry, so `highlight` passes the resolved element, not a pre-computed rect).
- **Schema** (`schema/plan.schema.json`): allow `1.2`; add the 3 actions + 4 args; fix
  drift (`exec` + `command`/`argv` args; `clipboard`/`stdout`/`stderr`/`exitCode` assert
  props; target-less clipboard assert exemption).
- **TDD:** `Tests/AutopilotCoreTests/DemoStepsTests.swift` — decode v1.2, back-compat
  v1.1, validation negatives, demo-off no-ops, demo-on hooks fire.

**Exit:** v1.2 plans parse + validate; v1.1 unaffected; core tests green; demo-off run
treats demo steps as passing no-ops. Schema validated against demo/legacy/negative plans.

---

## Phase 2 — macOS: demo rendering + finish the visual builder

**Repo:** `autopilot-macos`. Branch: `feature/demo-and-builder`.

- **2a. MacOSDriver:** implement `showHighlight`/`showCaption` via a borderless,
  click-through overlay `NSWindow`; the driver looks up the element's real frame. Reuse
  `Runtime/Screenshot.swift` (`captureElement`) + `ScreenCapture` (ScreenCaptureKit).
- **2b. Cockpit Demo:** add a **Demo-mode** toggle (sets `RunOptions.demoMode`) and an
  optional **Record-screencast** toggle in `Run/RunView.swift` + `RunController.swift`
  (frames via the existing `RunObserver.stepDidFinish`).
- **2c. Builder:** extend `Author/AuthorView.swift` `authorableActions` with
  `highlight`/`caption`/`pace`; add a **per-step args/assert/level form** in
  `Author/PlanEditor.swift` (add `setArgs`/`setAssert`); bump `emptyPlan()` to `1.2`.
- **Also:** sync the schema mirror `autopilot-macos/schema/plan.schema.json` to core's.

**Exit:** Cockpit visually authors a demo plan (incl. args/asserts) and runs it with
on-screen highlight/caption/pacing; test-mode runs unchanged.

---

## Phase 3 — Web runner (new repo, Playwright/TS)

**New repo:** `autopilot-web` (confirm path/structure before creating). TS + Playwright.

- `testhost/index.html` — **web TestHostApp (build FIRST, gates the parity gate).**
  Mirrors the native surface (`nameField`, `statusLabel`, buttons, scroll list, a
  status-updating form) with stable `id`s / ARIA roles. Pair with
  `test-web-capabilities.json` (the shared 78-step plan targets the NATIVE app).
- `src/planModel.ts` — mirror the core schema (like Android/iOS).
- `src/runner.ts` — reimplement the loop over Playwright `Page`. **Selector mapping
  verified empirically** (AX↔ARIA not 1:1): `identifier → [id]`, `role+title →
  getByRole`, `index → .nth()`, `within → chained`. Skip `menu`/visual-asserts/`exec`.
  Demo steps inject overlay/caption via `page.evaluate`; headed + `recordVideo`.
- `src/index.ts` — CLI `autopilot-web run <plan> --url <target> [--headed] [--demo] [--record <dir>]`.
- `README.md` (per-OS setup), CI parity gate, **reverse the "not a web testing tool"
  disclaimer** across the doc set + add web to platform tables.

**Exit:** real test backend — headless CI parity gate green + headed/demo live; docs no
longer disclaim web testing.

---

## Phase 4 — Mobile parity (implement-or-skip)

**Repos:** `autopilot-android`, `autopilot-ios`. Branches: `feature/demo-steps`.

Bump each hand-mirrored `PlanModel` to accept 1.2 + new actions/args. Android:
`highlight`/`caption` via overlay if feasible, else skip; `pace` → per-char delay. iOS:
skip `highlight`/`caption` (XCUITest can't draw on the app under test), honor `pace`
where possible. Verify the 78-step plan still hits 75 PASS + 3 SKIP on the real S24 +
iPhone 17 (verify device connected first).

---

## Verification (end-to-end)

- **Core:** `swift test` — demo-step tests pass; v1.1 fixture parses; demo-off = passing
  no-ops. Schema validated against demo/legacy/negative plans.
- **macOS:** author a `caption`/`highlight`/`pace`+`type` plan; Run with Demo ON → glow
  ring, caption, paced typing; Demo OFF → fast, demo steps pass silently.
- **Web:** `npx playwright install` then `autopilot-web run test-web-capabilities.json
  --url testhost/index.html --headed --demo` → drives the web TestHostApp, overlays
  inject; headless CI asserts the parity count.
- **Mobile:** 78-step plan on real S24 + iPhone 17 → 75 PASS + 3 SKIP unchanged; a
  demo-step plan parses and renders-or-skips.

## Risks / open items

1. **Web disclaimer reversal (deliberate)** — remove/reverse "not a web testing tool"
   everywhere (`autopilot-macos/docs/MANUAL.md`, distribution-plan doc) and add web to
   the supported-platform tables. Leaving the old line is the defect.
2. **iOS overlay limitation** — XCUITest can't draw on the app under test; demo overlays
   skip on iOS (pacing-only).
3. **New repo gate** — `autopilot-web` confirmed (path + structure) before creation.
4. **v1.2 back-compat** — keep parsing v1.1 plans; tested.
5. **Web TestHostApp + selector fidelity** — build the web TestHostApp FIRST; prove the
   `role+title → getByRole` mapping against the real page (AX↔ARIA not 1:1).
6. **Unified release train** — all five repos bump to one common version at the same
   "go"; coordinated tag/release/npm/tap.
7. **Scope** — 4 branches across 3 existing repos + 1 new repo; each phase an
   independent, shippable PR. No publish without an explicit "go."
