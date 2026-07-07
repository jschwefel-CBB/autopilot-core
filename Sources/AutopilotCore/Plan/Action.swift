import Foundation

/// v1 action vocabulary. Lean by design.
public enum Action: String, Codable, Sendable {
    case launch, terminate
    case click, doubleClick, rightClick
    case press          // AX press action (buttons, menu items) — robust vs coordinate click
    case menu           // walk the menu bar: ["View", "Rainbow Brackets"]
    case type, keyPress, setValue, scroll
    case drag           // drag from a source element/point to a destination
    case assertPixel    // assert a screen pixel's color (visual features AX can't see)
    case assertRegion   // assert the average/dominant color over a rectangle (robust for glyphs)
    case snapshot       // capture a region; write a reference on first run, diff on later runs
    case waitFor, screenshot, assert
    case wait   // explicit, discouraged fixed delay
    case exec   // run a shell command / argv; capture stdout/stderr/exitCode.
                // Bare = setup/teardown (always passes); with an assert on
                // stdout/stderr/exitCode, the assert gates the step.
    // Demo actions (schema 1.2). Present so ONE plan can double as a screencast
    // script. They only render in demo mode (RunOptions.demoMode); in a normal
    // test run they are passing no-ops so the plan stays a clean, fast test.
    // Backends that cannot render an overlay skip highlight/caption
    // (skip-don't-branch), like the visual asserts on mobile.
    case highlight  // draw a glow/ring on the target for holdMs, then clear.
    case caption    // show on-screen narration text (args.text) for holdMs.
    case pace       // set demo cadence (typeMsPerChar / stepDelayMs) for the steps
                    // that follow, until the next pace. Stateful; no-op when not in demo mode.
}

/// Per-action arguments. Only the fields relevant to a given action are used.
public struct ActionArgs: Codable, Equatable, Sendable {
    public var text: String?          // type / setValue
    public var keys: String?          // keyPress, e.g. "cmd+s"
    public var deltaX: Int?           // scroll
    public var deltaY: Int?           // scroll
    public var seconds: Double?       // wait
    public var path: String?          // screenshot output path
    public var present: Bool?         // waitFor: true=appears, false=disappears
    public var menuPath: [String]?    // menu: ["View", "Rainbow Brackets"]
    public var to: Selector?          // drag: destination element
    public var toFiles: [String]?     // drag: file paths to drag onto the target (DnD)
    public var commit: Bool?          // type: press Return after typing to fire end-editing
    public var clear: Bool?           // type: select-all + delete before typing
    public var focus: Bool?           // type: click to focus first (default true); set
                                      // false for fields the app already made first responder
    // assertPixel: sample point is target's center + (offsetX,offsetY), or an
    // absolute (atX,atY) when no target is given. Compares to `color` within `tolerance`.
    public var offsetX: Int?
    public var offsetY: Int?
    public var atX: Int?
    public var atY: Int?
    public var color: String?         // expected "#RRGGBB"
    public var tolerance: Double?     // RGB distance tolerance (default 16)
    public var width: Int?            // assertRegion/snapshot: rectangle size
    public var height: Int?
    public var mode: String?          // assertRegion: "average" (default) or "dominant"
    public var reference: String?     // snapshot: reference PNG path (written on first run)
    public var maxDiff: Double?       // snapshot: max allowed differing-pixel fraction (default 0.02)
    /// screenshot / captureTarget: points of padding added around the element
    /// frame on all sides. Preserves shadow/context that a pixel-tight crop hides.
    public var padding: Double?
    // exec: run EITHER a shell string (`command`, via /bin/sh -c) OR an argv
    // array (`argv`, run directly, no shell). Exactly one is required.
    public var command: String?
    public var argv: [String]?
    // Demo actions (schema 1.2):
    /// highlight / caption: how long (ms) to hold the overlay before clearing.
    /// 0 or nil = a brief default; the runner does not block the plan on it.
    public var holdMs: Int?
    /// caption: where to place the banner — "top" / "bottom" (default) / "center".
    public var position: String?
    /// pace: milliseconds per character for subsequent `type` steps in demo mode.
    public var typeMsPerChar: Int?
    /// pace: milliseconds to pause after each subsequent step in demo mode.
    public var stepDelayMs: Int?
    public init() {}
}
