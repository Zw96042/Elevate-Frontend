import Testing
@testable import ElevateCore

@Suite("Data-only JavaScript parser")
struct JavaScriptLiteralParserTests {
    @Test("Parses Skyward-style object literals without evaluation")
    func parsesLiteral() throws {
        let value = try JavaScriptLiteralParser.parse(
            #"{grid:{tb:{r:[{c:[{h:'<b>Algebra</b>'}],},],},}, enabled:true}"#
        )
        let root = try #require(value as? [String: Any])
        let grid = try #require(root["grid"] as? [String: Any])
        let table = try #require(grid["tb"] as? [String: Any])
        let rows = try #require(table["r"] as? [[String: Any]])

        #expect(rows.count == 1)
        #expect(root["enabled"] as? Bool == true)
    }

    @Test("Rejects executable expressions")
    func rejectsCode() {
        #expect(throws: (any Error).self) {
            _ = try JavaScriptLiteralParser.parse("{value:(function(){return 1})()}")
        }
    }

    @Test("Rejects executable text after a valid literal")
    func rejectsTrailingCode() {
        #expect(throws: (any Error).self) {
            _ = try JavaScriptLiteralParser.parse("{grid:{}}; globalThis.pwn()")
        }
    }

    @Test("Array holes count toward the value limit")
    func boundsSparseArrays() {
        let source = "[" + String(repeating: ",", count: 250_001) + "]"
        #expect(throws: (any Error).self) {
            _ = try JavaScriptLiteralParser.parse(source)
        }
    }
}
