import Foundation

/// The authoring preview shown in the snippet editor: placeholder syntax is
/// annotated as `⟨…⟩` markers rather than filled in.
public enum SnippetPreview {
    static let maxPreviewLength = 500

    /// Empty when `content` has no `{{`; otherwise system placeholders, then
    /// conditional blocks, then value placeholders, capped at 500 UTF-16 units
    /// (without splitting a character).
    public static func build(_ content: String, now: Int64, timeZone: TimeZone = .current) -> String {
        guard content.contains("{{") else { return "" }

        let withSystems = previewSystemPlaceholders(content, now: now, timeZone: timeZone)
        let withConditionals = previewConditionalBlocks(withSystems)
        return capped(previewValuePlaceholders(withConditionals))
    }

    private static func previewSystemPlaceholders(_ content: String, now: Int64, timeZone: TimeZone) -> String {
        let expression = /\{\{\s*(DATETIME|DATE|TIME|TODAY|NOW|YEAR|MONTH|DAY)\s*\}\}/.matchingSemantics(.unicodeScalar)
        return content.replacing(expression) { match in
            let name = String(match.1)
            guard let resolved = SystemPlaceholders.value(for: name, now: now, timeZone: timeZone) else {
                return String(match.0)
            }
            return "⟨\(name) → \(resolved)⟩"
        }
    }

    private static func previewConditionalBlocks(_ content: String) -> String {
        guard content.contains(/\{\{\/if\}\}/.matchingSemantics(.unicodeScalar)) else { return content }
        let expressions = PlaceholderSyntaxParser.scanExpressions(content)
        let opener = /\{\{#if\s+((?:[^}"]|"[^"]*")+)\}\}/.matchingSemantics(.unicodeScalar)
        var stack: [(index: Int, key: String)] = []
        var openers: [Int: String] = [:]
        var closers = Set<Int>()
        for (index, expression) in expressions.enumerated() {
            if let match = expression.raw.wholeMatch(of: opener) {
                stack.append((index, ConditionalBlocks.conditionKey(String(match.1))))
            } else if expression.raw == "{{/if}}", let matched = stack.popLast() {
                openers[matched.index] = matched.key
                closers.insert(index)
            }
        }

        // Annotate matched pairs in one pass. Repeated innermost regex
        // replacements stall the editor on deeply nested, valid templates.
        // Buffer whitespace so each completed body is trimmed without
        // repeatedly copying its already-annotated children.
        var result = ""
        var pendingWhitespace = ""
        var trimLeading = false
        func append(_ text: some StringProtocol) {
            let scalars = String(text).unicodeScalars
            var start = scalars.startIndex
            if trimLeading {
                while start < scalars.endIndex, isWhitespace(scalars[start]) {
                    start = scalars.index(after: start)
                }
            }
            guard start < scalars.endIndex else { return }
            var end = scalars.endIndex
            while end > start, isWhitespace(scalars[scalars.index(before: end)]) {
                end = scalars.index(before: end)
            }
            if start < end {
                result += pendingWhitespace
                result += String(scalars[start..<end])
                pendingWhitespace = ""
                trimLeading = false
            }
            pendingWhitespace += String(scalars[end...])
        }
        func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
            scalar == "\u{FEFF}" || scalar.properties.isWhitespace
        }

        var cursor = content.startIndex
        var depth = 0
        for (index, expression) in expressions.enumerated() {
            append(content[cursor..<expression.indices.lowerBound])
            cursor = expression.indices.upperBound
            if let key = openers[index] {
                append("⟨if \(key): ")
                // The marker's trailing space is part of the annotation.
                result += pendingWhitespace
                pendingWhitespace = ""
                trimLeading = true
                depth += 1
            } else if closers.contains(index) {
                pendingWhitespace = ""
                append("⟩")
                depth -= 1
            } else if depth > 0, expression.raw == "{{#else}}" {
                append(" | else: ")
            } else if depth > 0, expression.raw == "{{/else}}" {
                continue
            } else {
                append(expression.raw)
            }
        }
        append(content[cursor...])
        return result + pendingWhitespace
    }

    private static func previewValuePlaceholders(_ content: String) -> String {
        var result = ""
        var cursor = content.startIndex
        for occurrence in PlaceholderSyntaxParser.parse(content).occurrences {
            result += content[cursor..<occurrence.indices.lowerBound]
            result += previewOccurrence(occurrence)
            cursor = occurrence.indices.upperBound
        }
        return result + content[cursor...]
    }

    private static func previewOccurrence(_ occurrence: ParsedValuePlaceholderOccurrence) -> String {
        let label = displayKey(occurrence)

        if let choices = occurrence.choices {
            let list = choices.map(\.jsonQuoted).joined(separator: ", ")
            let defaultLabel =
                occurrence.hasExplicitDefault ? "; default: \((occurrence.explicitDefault ?? "").jsonQuoted)" : ""
            return "⟨\(label) — choices: \(list)\(defaultLabel)⟩"
        }

        if occurrence.hasExplicitDefault, let explicitDefault = occurrence.explicitDefault, !explicitDefault.isEmpty {
            return "⟨\(label) = \(explicitDefault.jsonQuoted)⟩"
        }
        return "⟨\(label)⟩"
    }

    private static func displayKey(_ occurrence: ParsedValuePlaceholderOccurrence) -> String {
        let prefix = occurrence.prefixWrapper?.trimmed ?? ""
        let suffix = occurrence.suffixWrapper?.trimmed ?? ""
        let main = prefix + occurrence.key
        let wrapped = suffix.isEmpty ? main : "\(main) \(suffix)"
        return occurrence.isSaved ? wrapped : "!\(wrapped)"
    }

    private static func capped(_ text: String) -> String {
        var units = 0
        var end = text.startIndex
        for index in text.indices {
            let width = text[index].utf16.count
            guard units + width <= maxPreviewLength else { break }
            units += width
            end = text.index(after: index)
        }
        return units == text.utf16.count ? text : String(text[..<end])
    }
}
