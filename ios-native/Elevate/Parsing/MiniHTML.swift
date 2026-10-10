import Foundation

/// A small, tolerant HTML parser with just enough CSS-selector support for
/// scraping Skyward's pages. Replaces the `node-html-parser` dependency from
/// the React Native app with pure Swift.
final class HTMLNode {
    let tagName: String           // lowercase; "" for text nodes and the root
    var attributes: [String: String]
    var children: [HTMLNode] = []
    weak var parent: HTMLNode?
    var textContentRaw: String    // only for text nodes

    init(tagName: String, attributes: [String: String] = [:], text: String = "") {
        self.tagName = tagName
        self.attributes = attributes
        self.textContentRaw = text
    }

    var isText: Bool { tagName.isEmpty && parent != nil }

    var id: String { attributes["id"] ?? "" }

    var classList: [String] {
        (attributes["class"] ?? "").split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
    }

    func hasClass(_ name: String) -> Bool { classList.contains(name) }

    func attribute(_ name: String) -> String? { attributes[name] }

    /// Concatenated, entity-decoded text of all descendants.
    var text: String {
        if isText { return HTMLEntities.decode(textContentRaw) }
        var out = ""
        collectText(into: &out)
        return out
    }

    private func collectText(into out: inout String) {
        if isText {
            out += HTMLEntities.decode(textContentRaw)
            return
        }
        for child in children { child.collectText(into: &out) }
    }

    /// Element children only (skips text nodes).
    var elements: [HTMLNode] {
        children.filter { !$0.tagName.isEmpty }
    }

    func descendants() -> [HTMLNode] {
        var result: [HTMLNode] = []
        var stack = elements.reversed().map { $0 }
        while let node = stack.popLast() {
            result.append(node)
            stack.append(contentsOf: node.elements.reversed())
        }
        return result
    }

    func querySelector(_ selector: String) -> HTMLNode? {
        querySelectorAll(selector, first: true).first
    }

    func querySelectorAll(_ selector: String) -> [HTMLNode] {
        querySelectorAll(selector, first: false)
    }

    private func querySelectorAll(_ selector: String, first: Bool) -> [HTMLNode] {
        guard let chain = SelectorChain(selector) else { return [] }
        var matches: [HTMLNode] = []
        for node in descendants() {
            if chain.matches(node) {
                matches.append(node)
                if first { break }
            }
        }
        return matches
    }
}

// MARK: - Selector engine

private struct SimpleSelector {
    var tag: String?
    var idValue: String?
    var classes: [String] = []
    var attrChecks: [(name: String, op: String?, value: String?)] = []  // op: "=", "^=", "*=", nil = presence
    var pseudos: [String] = []      // "last-child", "nth-child(2)"
    var notSelector: String?

    init?(_ raw: String) {
        var s = Substring(raw)
        guard !s.isEmpty else { return nil }

        func readName(_ s: inout Substring) -> String {
            var name = ""
            while let c = s.first, c.isLetter || c.isNumber || c == "-" || c == "_" {
                name.append(c)
                s.removeFirst()
            }
            return name
        }

        if let c = s.first, c.isLetter {
            tag = readName(&s).lowercased()
        } else if s.first == "*" {
            s.removeFirst()
        }

        while let c = s.first {
            switch c {
            case "#":
                s.removeFirst()
                idValue = readName(&s)
            case ".":
                s.removeFirst()
                classes.append(readName(&s))
            case "[":
                s.removeFirst()
                let name = readName(&s)
                var op: String? = nil
                var value: String? = nil
                if s.first == "^" || s.first == "*" {
                    op = String(s.removeFirst()) + "="
                    if s.first == "=" { s.removeFirst() }
                } else if s.first == "=" {
                    op = "="
                    s.removeFirst()
                }
                if op != nil {
                    var quote: Character? = nil
                    if s.first == "'" || s.first == "\"" { quote = s.removeFirst() }
                    var v = ""
                    while let ch = s.first {
                        if let q = quote, ch == q { s.removeFirst(); break }
                        if quote == nil, ch == "]" { break }
                        v.append(ch)
                        s.removeFirst()
                    }
                    value = v
                }
                if s.first == "]" { s.removeFirst() }
                attrChecks.append((name, op, value))
            case ":":
                s.removeFirst()
                var pseudo = readName(&s)
                if s.first == "(" {
                    s.removeFirst()
                    var inner = ""
                    var depth = 1
                    while let ch = s.first {
                        s.removeFirst()
                        if ch == "(" { depth += 1 }
                        if ch == ")" { depth -= 1; if depth == 0 { break } }
                        inner.append(ch)
                    }
                    if pseudo == "not" {
                        notSelector = inner
                        pseudo = ""
                    } else {
                        pseudo += "(\(inner))"
                    }
                }
                if !pseudo.isEmpty { pseudos.append(pseudo) }
            default:
                return nil
            }
        }
    }

    func matches(_ node: HTMLNode) -> Bool {
        if let tag, node.tagName != tag { return false }
        if let idValue, node.id != idValue { return false }
        for cls in classes where !node.hasClass(cls) { return false }
        for (name, op, value) in attrChecks {
            guard let actual = node.attributes[name] else { return false }
            switch op {
            case nil: break
            case "=": if actual != value { return false }
            case "^=": if !actual.hasPrefix(value ?? "") { return false }
            case "*=": if !actual.contains(value ?? "") { return false }
            default: return false
            }
        }
        if let notSelector, let inner = SimpleSelector(notSelector), inner.matches(node) {
            return false
        }
        for pseudo in pseudos {
            guard let parent = node.parent else { return false }
            let siblings = parent.elements
            if pseudo == "last-child" {
                if siblings.last !== node { return false }
            } else if pseudo.hasPrefix("nth-child(") {
                let numStr = pseudo.dropFirst("nth-child(".count).dropLast()
                guard let n = Int(numStr), siblings.indices.contains(n - 1), siblings[n - 1] === node else { return false }
            } else {
                return false
            }
        }
        return true
    }
}

private struct SelectorChain {
    // Parts from rightmost to leftmost, each with the combinator that connects
    // it to the part on its left (" " descendant or ">" child).
    var parts: [(selector: SimpleSelector, combinatorToLeft: Character?)]

    init?(_ raw: String) {
        var tokens: [String] = []
        var current = ""
        for ch in raw {
            if ch == " " || ch == ">" {
                if !current.isEmpty { tokens.append(current); current = "" }
                if ch == ">" { tokens.append(">") }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        guard !tokens.isEmpty else { return nil }

        var built: [(SimpleSelector, Character?)] = []
        var pendingCombinator: Character? = nil
        for token in tokens {
            if token == ">" {
                pendingCombinator = ">"
                continue
            }
            guard let sel = SimpleSelector(token) else { return nil }
            built.append((sel, pendingCombinator ?? " "))
            pendingCombinator = nil
        }
        // The first part has no combinator to its left.
        if !built.isEmpty { built[0].1 = nil }
        parts = built.reversed().map { (selector: $0.0, combinatorToLeft: $0.1) }
    }

    func matches(_ node: HTMLNode) -> Bool {
        guard let rightmost = parts.first else { return false }
        guard rightmost.selector.matches(node) else { return false }
        return matchesAncestors(node: node, partIndex: 1, combinator: rightmost.combinatorToLeft)
    }

    private func matchesAncestors(node: HTMLNode, partIndex: Int, combinator: Character?) -> Bool {
        guard partIndex < parts.count else { return true }
        let part = parts[partIndex]
        if combinator == ">" {
            guard let parent = node.parent, part.selector.matches(parent) else { return false }
            return matchesAncestors(node: parent, partIndex: partIndex + 1, combinator: part.combinatorToLeft)
        }
        var ancestor = node.parent
        while let candidate = ancestor {
            if part.selector.matches(candidate),
               matchesAncestors(node: candidate, partIndex: partIndex + 1, combinator: part.combinatorToLeft) {
                return true
            }
            ancestor = candidate.parent
        }
        return false
    }
}

// MARK: - Parser

enum MiniHTML {
    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
    ]

    static func parse(_ html: String) -> HTMLNode {
        let root = HTMLNode(tagName: "")
        var stack: [HTMLNode] = [root]
        let scalars = Array(html)
        var i = 0
        let n = scalars.count

        func appendText(_ text: String) {
            guard !text.isEmpty else { return }
            let node = HTMLNode(tagName: "", text: text)
            node.parent = stack.last
            stack.last?.children.append(node)
        }

        while i < n {
            if scalars[i] == "<" {
                // Comment
                if i + 3 < n, scalars[i+1] == "!", scalars[i+2] == "-", scalars[i+3] == "-" {
                    var j = i + 4
                    while j + 2 < n, !(scalars[j] == "-" && scalars[j+1] == "-" && scalars[j+2] == ">") { j += 1 }
                    i = min(j + 3, n)
                    continue
                }
                // Doctype / CDATA / processing instructions: skip to ">"
                if i + 1 < n, scalars[i+1] == "!" || scalars[i+1] == "?" {
                    var j = i + 1
                    while j < n, scalars[j] != ">" { j += 1 }
                    i = min(j + 1, n)
                    continue
                }
                // Closing tag
                if i + 1 < n, scalars[i+1] == "/" {
                    var j = i + 2
                    var name = ""
                    while j < n, scalars[j] != ">" {
                        if scalars[j].isLetter || scalars[j].isNumber { name.append(scalars[j]) }
                        j += 1
                    }
                    name = name.lowercased()
                    if let idx = stack.lastIndex(where: { $0.tagName == name }), idx > 0 {
                        stack.removeSubrange(idx...)
                    }
                    i = min(j + 1, n)
                    continue
                }
                // Opening tag
                if i + 1 < n, scalars[i+1].isLetter {
                    var j = i + 1
                    var name = ""
                    while j < n, scalars[j].isLetter || scalars[j].isNumber || scalars[j] == "-" {
                        name.append(scalars[j])
                        j += 1
                    }
                    name = name.lowercased()
                    var attrs: [String: String] = [:]
                    var selfClosing = false
                    // Parse attributes
                    while j < n, scalars[j] != ">" {
                        if scalars[j] == "/" && j + 1 < n && scalars[j+1] == ">" {
                            selfClosing = true
                            j += 1
                            break
                        }
                        if scalars[j].isWhitespace { j += 1; continue }
                        var attrName = ""
                        while j < n, !scalars[j].isWhitespace, scalars[j] != "=", scalars[j] != ">", scalars[j] != "/" {
                            attrName.append(scalars[j])
                            j += 1
                        }
                        while j < n, scalars[j].isWhitespace { j += 1 }
                        var attrValue = ""
                        if j < n, scalars[j] == "=" {
                            j += 1
                            while j < n, scalars[j].isWhitespace { j += 1 }
                            if j < n, scalars[j] == "\"" || scalars[j] == "'" {
                                let quote = scalars[j]
                                j += 1
                                while j < n, scalars[j] != quote {
                                    attrValue.append(scalars[j])
                                    j += 1
                                }
                                j += 1
                            } else {
                                while j < n, !scalars[j].isWhitespace, scalars[j] != ">" {
                                    attrValue.append(scalars[j])
                                    j += 1
                                }
                            }
                        }
                        if !attrName.isEmpty {
                            attrs[attrName.lowercased()] = HTMLEntities.decode(attrValue)
                        }
                    }
                    i = j < n ? j + 1 : n

                    let node = HTMLNode(tagName: name, attributes: attrs)
                    node.parent = stack.last
                    stack.last?.children.append(node)

                    if name == "script" || name == "style" {
                        // Raw text until matching close tag
                        let closeTag = "</\(name)"
                        var k = i
                        var raw = ""
                        while k < n {
                            if scalars[k] == "<" {
                                let remaining = n - k
                                if remaining >= closeTag.count {
                                    let candidate = String(scalars[k..<(k + closeTag.count)]).lowercased()
                                    if candidate == closeTag { break }
                                }
                            }
                            raw.append(scalars[k])
                            k += 1
                        }
                        let textNode = HTMLNode(tagName: "", text: raw)
                        textNode.parent = node
                        node.children.append(textNode)
                        // Skip past "</script ... >"
                        while k < n, scalars[k] != ">" { k += 1 }
                        i = min(k + 1, n)
                        continue
                    }

                    if !selfClosing && !voidElements.contains(name) {
                        stack.append(node)
                    }
                    continue
                }
                // Stray "<": treat as text
                appendText("<")
                i += 1
                continue
            }
            // Text run
            var j = i
            var text = ""
            while j < n, scalars[j] != "<" {
                text.append(scalars[j])
                j += 1
            }
            appendText(text)
            i = j
        }
        return root
    }
}

// MARK: - Entities

enum HTMLEntities {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00a0}", "ndash": "\u{2013}", "mdash": "\u{2014}",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201c}", "rdquo": "\u{201d}",
        "hellip": "\u{2026}", "bull": "\u{2022}", "copy": "\u{00a9}", "reg": "\u{00ae}",
    ]

    static func decode(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var result = ""
        result.reserveCapacity(input.count)
        var chars = Substring(input)
        while let ampIndex = chars.firstIndex(of: "&") {
            result += chars[..<ampIndex]
            chars = chars[ampIndex...].dropFirst()
            guard let semi = chars.prefix(10).firstIndex(of: ";") else {
                result += "&"
                continue
            }
            let entity = String(chars[..<semi])
            var decoded: String? = nil
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                if let code = UInt32(entity.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
                    decoded = String(Character(scalar))
                }
            } else if entity.hasPrefix("#") {
                if let code = UInt32(entity.dropFirst()), let scalar = Unicode.Scalar(code) {
                    decoded = String(Character(scalar))
                }
            } else {
                decoded = named[entity]
            }
            if let decoded {
                result += decoded
                chars = chars[semi...].dropFirst()
            } else {
                result += "&"
            }
        }
        result += chars
        return result
    }
}
