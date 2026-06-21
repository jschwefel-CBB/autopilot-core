import Testing
@testable import AutopilotCore

@Suite struct ChordValidatorTests {
    @Test func acceptsModifiersAndNamedKey() throws {
        try ChordValidator.validate("cmd+s")
        try ChordValidator.validate("cmd+shift+z")
        try ChordValidator.validate("cmd+plus")
        try ChordValidator.validate("return")
        try ChordValidator.validate("f5")
        try ChordValidator.validate("cmd+comma")
    }
    @Test func rejectsUnknownModifier() {
        #expect(throws: (any Error).self) { try ChordValidator.validate("hyper+s") }
    }
    @Test func rejectsUnknownKey() {
        #expect(throws: (any Error).self) { try ChordValidator.validate("cmd+notakey") }
    }
    @Test func rejectsEmpty() {
        #expect(throws: (any Error).self) { try ChordValidator.validate("") }
    }
}
