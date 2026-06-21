import Foundation

/// Pure, platform-agnostic validation of a key-chord string ("cmd+shift+z").
/// Mirrors the token vocabulary ActionEngine.parseChord accepts, but produces
/// no platform types — used by PlanParser to reject bad chords at parse time.
public enum ChordValidator {
    /// Single-character keys ActionEngine maps (ANSI letters, digits, punctuation).
    static let singleCharKeys: Set<Character> = [
        "a","s","d","f","h","g","z","x","c","v","b","q","w","e","r","y","t",
        "o","u","i","p","l","j","k","n","m",
        "1","2","3","4","5","6","7","8","9","0",
        "=","-","]","[","'",";","\\",",","/",".","`"
    ]
    /// Named keys ActionEngine maps.
    static let namedKeys: Set<String> = [
        "return","enter","tab","space","delete","forwarddelete","escape",
        "left","right","down","up","home","end","pageup","pagedown",
        "comma","period","slash","semicolon","quote","leftbracket","rightbracket",
        "backslash","grave","minus","equal",
        "f1","f2","f3","f4","f5","f6","f7","f8","f9","f10","f11","f12"
    ]
    static let modifiers: Set<String> = [
        "cmd","command","shift","opt","option","alt","ctrl","control"
    ]

    public static func validate(_ s: String) throws {
        let parts = s.lowercased().split(separator: "+").map(String.init)
        guard let keyToken = parts.last, !keyToken.isEmpty else {
            throw PlanError.decode("empty key chord")
        }
        for mod in parts.dropLast() {
            guard modifiers.contains(mod) else { throw PlanError.unsupportedKey("modifier '\(mod)'") }
        }
        // `plus` is the literal plus key (Shift+'=' on ANSI); always valid as a key token.
        if keyToken == "plus" { return }
        if namedKeys.contains(keyToken) { return }
        if keyToken.count == 1, let ch = keyToken.first, singleCharKeys.contains(ch) { return }
        throw PlanError.unsupportedKey(keyToken)
    }
}
