import Foundation

/// Classification helpers for AX roles, shared by the CLI and MCP dump filters.
public enum AXRoles {
    /// Roles a user can interact with — used by the dump-axtree interactiveOnly filter.
    public static let interactive: Set<String> = [
        "AXButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton",
        "AXPopUpButton", "AXMenuButton", "AXMenuItem", "AXSlider", "AXOutline",
        "AXTable", "AXRow", "AXCell", "AXComboBox", "AXLink", "AXTabGroup",
    ]
    public static func isInteractive(_ role: String?) -> Bool {
        guard let role else { return false }
        return interactive.contains(role)
    }
}
