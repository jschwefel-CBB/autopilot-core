import Foundation

/// Pure selector matching + description. The AX-tree walk lives in the platform
/// driver (MacOSAXResolver); this half is portable.
public struct AXResolver {
    public init() {}

    /// Pure predicate: does a snapshot node satisfy the selector?
    /// All present predicates are ANDed. An all-nil selector matches nothing.
    public static func matches(node: [String: String], selector: Selector) -> Bool {
        var anyPredicate = false
        func check(_ value: String?, _ key: String) -> Bool {
            guard let value else { return true }
            anyPredicate = true
            return node[key] == value
        }
        let ok = check(selector.role, "role")
            && check(selector.identifier, "identifier")
            && check(selector.title, "title")
            && check(selector.label, "label")
            && check(selector.value, "value")
        return anyPredicate && ok
    }

    /// How many match descriptors to include in an ambiguity error.
    public static let maxReportedMatches = 5

    public static func describe(_ s: Selector) -> String {
        var parts: [String] = []
        if let r = s.role { parts.append("role=\(r)") }
        if let id = s.identifier { parts.append("identifier=\(id)") }
        if let t = s.title { parts.append("title=\(t)") }
        if let l = s.label { parts.append("label=\(l)") }
        if let v = s.value { parts.append("value=\(v)") }
        if let p = s.path { parts.append("path=\(p.joined(separator: "/"))") }
        return "{" + parts.joined(separator: ", ") + "}"
    }
}
