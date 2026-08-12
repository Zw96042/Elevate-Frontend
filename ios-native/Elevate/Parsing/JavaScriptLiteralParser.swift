import Foundation

/// Parses the data-only subset of JavaScript literals used by Skyward grid payloads.
/// It intentionally rejects expressions and functions so remote response text is never executed.
enum JavaScriptLiteralParser {
    private static let maximumScalars = 5_000_000

    static func parse(_ source: String) throws -> Any {
        guard source.unicodeScalars.count <= maximumScalars else {
            throw ParseError.inputTooLarge
        }
        var parser = Parser(source)
        return try parser.parseValue()
    }

    private enum ParseError: LocalizedError {
        case inputTooLarge
        case tooDeep
        case tooManyValues
        case unexpectedEnd
        case unexpectedCharacter
        case invalidEscape
        case invalidNumber

        var errorDescription: String? {
            switch self {
            case .inputTooLarge: return "Skyward data was too large to parse safely"
            case .tooDeep: return "Skyward data was nested too deeply"
            case .tooManyValues: return "Skyward data contained too many values"
            case .unexpectedEnd: return "Skyward data ended unexpectedly"
            case .unexpectedCharacter: return "Skyward data contained an unsupported expression"
            case .invalidEscape: return "Skyward data contained an invalid string escape"
            case .invalidNumber: return "Skyward data contained an invalid number"
            }
        }
    }

    private struct Parser {
        private let scalars: [UnicodeScalar]
        private var index = 0
        private var depth = 0
        private var valueCount = 0

        private static let maximumDepth = 128
        private static let maximumValues = 250_000

        init(_ source: String) {
            scalars = Array(source.unicodeScalars)
        }

        mutating func parseValue() throws -> Any {
            try skipTrivia()
            try recordValue()
            guard let scalar = current else { throw ParseError.unexpectedEnd }
            switch scalar {
            case "{": return try parseObject()
            case "[": return try parseArray()
            case "\"", "'": return try parseString()
            case "-", "+", ".", "0"..."9": return try parseNumber()
            default:
                let identifier = try parseIdentifier()
                switch identifier {
                case "true": return true
                case "false": return false
                case "null", "undefined", "NaN", "Infinity": return NSNull()
                default: return identifier
                }
            }
        }

        private mutating func parseObject() throws -> [String: Any] {
            try enterContainer()
            defer { depth -= 1 }
            advance()
            try skipTrivia()

            var object: [String: Any] = [:]
            if consume("}") { return object }

            while true {
                try skipTrivia()
                guard let scalar = current else { throw ParseError.unexpectedEnd }
                let key: String
                if scalar == "\"" || scalar == "'" {
                    key = try parseString()
                } else if scalar == "+" || scalar == "-" || scalar == "." || isDigit(scalar) {
                    key = String(describing: try parseNumber())
                } else {
                    key = try parseIdentifier()
                }

                try skipTrivia()
                guard consume(":") else { throw ParseError.unexpectedCharacter }
                object[key] = try parseValue()
                try skipTrivia()

                if consume("}") { return object }
                guard consume(",") else { throw ParseError.unexpectedCharacter }
                try skipTrivia()
                if consume("}") { return object }
            }
        }

        private mutating func parseArray() throws -> [Any] {
            try enterContainer()
            defer { depth -= 1 }
            advance()
            try skipTrivia()

            var array: [Any] = []
            if consume("]") { return array }

            while true {
                try skipTrivia()
                if consume(",") {
                    array.append(NSNull())
                    continue
                }
                array.append(try parseValue())
                try skipTrivia()
                if consume("]") { return array }
                guard consume(",") else { throw ParseError.unexpectedCharacter }
                try skipTrivia()
                if consume("]") { return array }
            }
        }

        private mutating func parseString() throws -> String {
            guard let quote = current, quote == "\"" || quote == "'" else {
                throw ParseError.unexpectedCharacter
            }
            advance()
            var result = String.UnicodeScalarView()

            while let scalar = current {
                advance()
                if scalar == quote { return String(result) }
                guard scalar == "\\" else {
                    result.append(scalar)
                    continue
                }

                guard let escaped = current else { throw ParseError.unexpectedEnd }
                advance()
                switch escaped {
                case "\"", "'", "\\", "/": result.append(escaped)
                case "b": result.append("\u{0008}")
                case "f": result.append("\u{000C}")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "v": result.append("\u{000B}")
                case "\n": break
                case "\r":
                    if current == "\n" { advance() }
                case "x": result.append(try parseEscapedScalar(digits: 2))
                case "u": result.append(try parseEscapedScalar(digits: 4))
                default: result.append(escaped)
                }
            }
            throw ParseError.unexpectedEnd
        }

        private mutating func parseEscapedScalar(digits: Int) throws -> UnicodeScalar {
            var value: UInt32 = 0
            for _ in 0..<digits {
                guard let scalar = current, let digit = hexadecimalValue(scalar) else {
                    throw ParseError.invalidEscape
                }
                value = value * 16 + digit
                advance()
            }
            guard let scalar = UnicodeScalar(value) else { throw ParseError.invalidEscape }
            return scalar
        }

        private mutating func parseNumber() throws -> Any {
            let start = index
            if current == "+" || current == "-" { advance() }
            while let scalar = current, isDigit(scalar) { advance() }
            if current == "." {
                advance()
                while let scalar = current, isDigit(scalar) { advance() }
            }
            if current == "e" || current == "E" {
                advance()
                if current == "+" || current == "-" { advance() }
                let exponentStart = index
                while let scalar = current, isDigit(scalar) { advance() }
                guard exponentStart != index else { throw ParseError.invalidNumber }
            }

            let text = String(String.UnicodeScalarView(scalars[start..<index]))
            guard let value = Double(text), value.isFinite else { throw ParseError.invalidNumber }
            if value == value.rounded(), value >= Double(Int.min), value <= Double(Int.max) {
                return Int(value)
            }
            return value
        }

        private mutating func parseIdentifier() throws -> String {
            guard let scalar = current, isIdentifierStart(scalar) else {
                throw ParseError.unexpectedCharacter
            }
            let start = index
            advance()
            while let scalar = current, isIdentifierContinuation(scalar) { advance() }
            return String(String.UnicodeScalarView(scalars[start..<index]))
        }

        private mutating func skipTrivia() throws {
            while true {
                while let scalar = current, CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    advance()
                }
                guard current == "/", peek() == "/" || peek() == "*" else { return }
                let isLineComment = peek() == "/"
                advance()
                advance()
                if isLineComment {
                    while let scalar = current, scalar != "\n", scalar != "\r" { advance() }
                } else {
                    while current != nil, !(current == "*" && peek() == "/") { advance() }
                    guard current != nil else { throw ParseError.unexpectedEnd }
                    advance()
                    advance()
                }
            }
        }

        private mutating func enterContainer() throws {
            depth += 1
            guard depth <= Self.maximumDepth else { throw ParseError.tooDeep }
        }

        private mutating func recordValue() throws {
            valueCount += 1
            guard valueCount <= Self.maximumValues else { throw ParseError.tooManyValues }
        }

        private var current: UnicodeScalar? {
            scalars.indices.contains(index) ? scalars[index] : nil
        }

        private func peek() -> UnicodeScalar? {
            scalars.indices.contains(index + 1) ? scalars[index + 1] : nil
        }

        private mutating func advance() {
            index += 1
        }

        private mutating func consume(_ expected: UnicodeScalar) -> Bool {
            guard current == expected else { return false }
            advance()
            return true
        }

        private func isDigit(_ scalar: UnicodeScalar) -> Bool {
            scalar.value >= 48 && scalar.value <= 57
        }

        private func hexadecimalValue(_ scalar: UnicodeScalar) -> UInt32? {
            switch scalar.value {
            case 48...57: return scalar.value - 48
            case 65...70: return scalar.value - 55
            case 97...102: return scalar.value - 87
            default: return nil
            }
        }

        private func isIdentifierStart(_ scalar: UnicodeScalar) -> Bool {
            scalar == "_" || scalar == "$" || CharacterSet.letters.contains(scalar)
        }

        private func isIdentifierContinuation(_ scalar: UnicodeScalar) -> Bool {
            isIdentifierStart(scalar) || isDigit(scalar)
        }
    }
}
