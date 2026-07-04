import Foundation

/// An 8-bit RGB color sampled from the screen. Neutral replacement for the
/// macOS-only PixelColor.RGB at the driver boundary.
public struct RGBColor: Equatable, Sendable {
    public var r: Int
    public var g: Int
    public var b: Int
    public init(r: Int, g: Int, b: Int) { self.r = r; self.g = g; self.b = b }
}

/// The result of running an `exec` step's command. Neutral (no platform types)
/// so the runner can evaluate stdout/stderr/exitCode asserts without importing
/// Foundation.Process.
public struct ProcessResult: Sendable, Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int
    public init(stdout: String, stderr: String, exitCode: Int) {
        self.stdout = stdout; self.stderr = stderr; self.exitCode = exitCode
    }
}

/// A launched/attached app, identified by pid + display name. Neutral
/// replacement for the macOS-only LaunchedApp at the driver boundary.
public struct LaunchedHandle: Sendable {
    public let pid: Int32
    public let appName: String
    public init(pid: Int32, appName: String) { self.pid = pid; self.appName = appName }
}

/// A flattened element-tree snapshot: each node is a [attribute: value] dict,
/// `truncated` true if the walk hit its node cap before finishing.
public struct TreeSnapshot: Sendable {
    public let nodes: [[String: String]]
    public let truncated: Bool
    public init(nodes: [[String: String]], truncated: Bool) {
        self.nodes = nodes; self.truncated = truncated
    }
}

/// One item in a menu, as reported by `AppDriver.listMenu`. Neutral (no platform
/// types) so authoring/discovery can inspect menu contents — INCLUDING disabled
/// items, which `selectPath` cannot invoke but an author still needs to see.
public struct MenuItemInfo: Sendable, Equatable {
    public let title: String
    /// Whether the item is enabled at menu-open time. A disabled item (e.g. a
    /// command that needs a specific first-responder state) is listed but cannot
    /// be invoked via the `menu` action.
    public let enabled: Bool
    /// Whether the item opens a submenu.
    public let hasSubmenu: Bool
    /// The AXMenuItemMarkChar (e.g. "✓") if the item is checked/marked, else nil —
    /// so a toggle's state is observable from the discovery path.
    public let markChar: String?
    public init(title: String, enabled: Bool, hasSubmenu: Bool, markChar: String?) {
        self.title = title; self.enabled = enabled
        self.hasSubmenu = hasSubmenu; self.markChar = markChar
    }
}

/// Everything PlanRunner needs from a platform. A backend (macOS AX, iOS
/// XCUITest, Android via Appium) implements this; core orchestration depends
/// only on this protocol and never on any platform API.
public protocol AppDriver {
    // Lifecycle
    func launch(_ target: TargetApp) throws -> LaunchedHandle
    func attach(_ target: TargetApp) throws -> LaunchedHandle
    func attach(pid: Int32) throws -> LaunchedHandle
    func terminate(_ app: LaunchedHandle)
    func activate(_ app: LaunchedHandle, timeoutMs: Int, intervalMs: Int) -> Bool

    // Permissions
    func hasAccessibility() -> Bool
    func hasScreenRecording() -> Bool
    func accessibilityInstructions() -> String
    func screenRecordingInstructions() -> String

    // Resolution
    func resolve(_ selector: Selector, app: LaunchedHandle,
                 timeoutMs: Int, intervalMs: Int, baseDir: URL?) throws -> ResolvedElement
    func waitForPresence(_ selector: Selector, present: Bool, app: LaunchedHandle,
                         timeoutMs: Int, intervalMs: Int) -> Bool
    func matchCount(_ selector: Selector, app: LaunchedHandle) -> Int
    func findAll(_ selector: Selector, app: LaunchedHandle) -> [String]

    // Actions
    func perform(action: Action, args: ActionArgs?, on element: ResolvedElement?) throws
    func point(for element: ResolvedElement) -> Point?
    /// Drag from one screen point to another (file-less; coordinate drag only).
    /// The runner resolves both endpoints to points, then calls this.
    func performDrag(from: Point, to: Point) throws
    /// Perform a REAL cross-process file drop: drag `files` onto screen `point`.
    /// The runner resolves the drop target to a point, then calls this. Platform
    /// backends that cannot originate a drag session should throw. Currently only
    /// the macOS backend implements it (iOS mirrors the schema; Android is Kotlin).
    func performFileDrag(files: [String], to: Point) throws
    /// Select a menu-bar path (e.g. ["File", "Save As…"]) on the app.
    func selectMenuPath(_ path: [String], app: LaunchedHandle) throws

    // Property read (assertions)
    func readProperty(_ property: AssertProperty, of element: any ElementHandle) -> String?

    // Visual capture
    func captureElementScreenshot(_ element: any ElementHandle, to path: String,
                                  padding: Int, metadata: [String: String]) -> String?
    func captureMainDisplay(to path: String, metadata: [String: String]) -> Bool
    func captureRegion(_ rect: Rect, to path: String, metadata: [String: String]) -> Bool
    func samplePixel(at point: Point) -> RGBColor?
    func sampleRegion(_ rect: Rect) -> [RGBColor]
    /// Load a PNG into a flat row-major pixel array (for snapshot diffing).
    func loadPNG(_ path: String) -> [RGBColor]?

    // Inspection
    func dumpTree(app: LaunchedHandle) -> TreeSnapshot
    func suggestSelectors(app: LaunchedHandle) -> [SelectorSuggester.Suggestion]
    /// List the items of the menu reached by `path` (e.g. ["View"] for the View
    /// menu, or ["Edit","Text"] for a submenu) — INCLUDING disabled items, so an
    /// author can discover what a menu contains and which items are currently
    /// invokable. Throws if the path doesn't resolve.
    func listMenu(path: [String], app: LaunchedHandle) throws -> [MenuItemInfo]

    // Clipboard
    /// The system pasteboard's current text (nil if empty / non-text). Backs the
    /// `clipboard` assert property so a plan can verify copy/paste side effects.
    func readClipboard() -> String?

    // Process execution (the `exec` step)
    /// Run a command — EITHER `command` (shell string via /bin/sh -c) OR `argv`
    /// (program + args, no shell) — and capture stdout/stderr/exitCode. Bounded by
    /// `timeoutMs`: on expiry the process (group) is killed and this throws.
    /// `workingDir` is the plan file's base directory (nil → inherit). Backends
    /// that cannot run subprocesses throw via the default implementation.
    func runProcess(command: String?, argv: [String]?, timeoutMs: Int,
                    workingDir: String?) throws -> ProcessResult
}

// Default implementations so a backend that predates these primitives (or a test
// double) still conforms. A backend that supports the feature overrides them.
public extension AppDriver {
    func listMenu(path: [String], app: LaunchedHandle) throws -> [MenuItemInfo] { [] }
    func readClipboard() -> String? { nil }
    func runProcess(command: String?, argv: [String]?, timeoutMs: Int,
                    workingDir: String?) throws -> ProcessResult {
        throw PlanError.decode("exec is not supported on this platform")
    }
}
