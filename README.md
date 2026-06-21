# AutopilotCore

Platform-agnostic core for AutoPilot — the shared Swift package required by all platform backends.

`AutopilotCore` defines the platform-neutral half of AutoPilot: the plan model
(parser, linter), the report model, the `PlanRunner` orchestration loop, and the
`AppDriver` protocol that platform backends implement. It imports only
`Foundation` — no `AppKit`, `ApplicationServices`, `CoreGraphics`, or
`ScreenCaptureKit` — so it can be shared by macOS, iOS, tvOS, and future backends.

## What's here

- **Plan model** — `Plan`, `PlanParser`, `PlanLinter`, `Selector`, `Action`, `Assertion`.
- **Runner** — `PlanRunner.run(_:options:)`, `RunOptions`, `SuiteReport`.
- **Driver protocol** — `AppDriver`, `ElementHandle`, `ResolvedElement`, neutral
  `Point`/`Rect`/`RGBColor` geometry, `ChordValidator`.
- **Pure targeting/assertion logic** — `AXResolver.matches`, `SelectorSuggester`,
  `VisionResolver` (NCC template match), `PixelColor` (RGB algebra),
  `AssertionEngine.evaluate`, `Poller`/`Clock`.

## Platform backends

This package has no backend — it cannot drive a real app on its own. Pair it with
a platform backend that conforms to `AppDriver`:

| Repo | Platform | Backend |
|---|---|---|
| [`autopilot-macos`](https://github.com/jschwefel-CBB/autopilot-macos) | macOS | `MacOSDriver` (Accessibility API) |
| [`autopilot-ios`](https://github.com/jschwefel-CBB/autopilot-ios) | iOS | XCUITest runner |
| [`autopilot-android`](https://github.com/jschwefel-CBB/autopilot-android) | Android | UiAutomator2 runner |

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

## Requirements

- Swift 6 toolchain (Xcode 16+)
- macOS 14+ or iOS 16+

## License

MIT
