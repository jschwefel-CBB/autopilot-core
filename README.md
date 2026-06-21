# AutopilotCore

Platform-agnostic core for [AutoPilot](https://github.com/jschwefel-CBB/autopilot-macos).

`AutopilotCore` defines the platform-neutral half of AutoPilot: the plan model
(parser, linter), the report model, the `PlanRunner` orchestration loop, and the
`AppDriver` protocol that platform backends implement. It imports only
`Foundation` — no `AppKit`, `ApplicationServices`, `CoreGraphics`, or
`ScreenCaptureKit` — so it can be shared by macOS, iOS, and future backends.

## What's here

- **Plan model** — `Plan`, `PlanParser`, `PlanLinter`, `Selector`, `Action`, `Assertion`.
- **Runner** — `PlanRunner.run(_:options:)`, `RunOptions`, `SuiteReport`.
- **Driver protocol** — `AppDriver`, `ElementHandle`, `ResolvedElement`, neutral
  `Point`/`Rect`/`RGBColor` geometry, `ChordValidator`.
- **Pure targeting/assertion logic** — `AXResolver.matches`, `SelectorSuggester`,
  `VisionResolver` (NCC template match), `PixelColor` (RGB algebra),
  `AssertionEngine.evaluate`, `Poller`/`Clock`.

## Not useful standalone

This package has no backend — it cannot drive a real app on its own. Pair it with
a platform backend (e.g. [`autopilot-macos`](https://github.com/jschwefel-CBB/autopilot-macos),
which provides `MacOSDriver`) that conforms to `AppDriver`.

## Adding as a dependency

```swift
.package(url: "https://github.com/jschwefel-CBB/autopilot-core", from: "2.0.0")
```

## Building

```bash
swift build
swift test
bash scripts/check-core-purity.sh   # fails if any platform framework leaks in
```
