import Foundation

/// A source range in UTF-16 offsets (`start` inclusive, `end` exclusive), the
/// same units as the TS offsets and `NSRange`.
public struct PlaceholderSourceRange: Sendable, Hashable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

public struct ParsedValuePlaceholderOccurrence: Sendable, Hashable {
    /// The complete authored expression, including braces.
    public var raw: String
    public var range: PlaceholderSourceRange
    /// The same range as `String.Index` bounds into the parsed text.
    public var indices: Range<String.Index>
    public var key: String
    public var prefixWrapper: String?
    public var suffixWrapper: String?
    /// Present when the expression has a trailing `|default`, including an empty default.
    public var explicitDefault: String?
    public var hasExplicitDefault: Bool
    public var isSaved: Bool
    public var isRequired: Bool
    public var choices: [String]?
    public var isChoiceDeclaration: Bool
}

public struct PlaceholderSyntaxDiagnostic: Sendable, Hashable {
    public var range: PlaceholderSourceRange
    /// The complete offending expression, including braces.
    public var expression: String
    public var message: String
}

public struct PlaceholderSyntaxResult: Sendable, Hashable {
    public var occurrences: [ParsedValuePlaceholderOccurrence]
    public var placeholders: [Placeholder]
    public var diagnostics: [PlaceholderSyntaxDiagnostic]
}

public enum PlaceholderSyntaxParser {
    private static let controlExpressions: Set<String> = ["#else", "/else", "/if"]

    /// Parses all user-value placeholder syntax in one pass.
    ///
    /// Invalid authored-choice expressions receive diagnostics but deliberately
    /// use the legacy parser for their runtime occurrence. This keeps imported or
    /// clipboard-saved malformed snippets safe to run while editor validation can
    /// reject the same content.
    public static func parse(_ text: String) -> PlaceholderSyntaxResult {
        var occurrences: [ParsedValuePlaceholderOccurrence] = []
        var diagnostics: [PlaceholderSyntaxDiagnostic] = []

        for expression in scanExpressions(text) {
            let trimmed = expression.content.trimmed
            if trimmed.contains(/^#if\s/.matchingSemantics(.unicodeScalar)) || controlExpressions.contains(trimmed) { continue }

            let occurrence: ParsedValuePlaceholderOccurrence
            switch ChoiceExpressionParser.parse(trimmed) {
            case .choice(let choice):
                occurrence = ParsedValuePlaceholderOccurrence(
                    raw: expression.raw,
                    range: expression.range,
                    indices: expression.indices,
                    key: choice.key,
                    prefixWrapper: choice.prefixWrapper,
                    suffixWrapper: choice.suffixWrapper,
                    explicitDefault: choice.explicitDefault,
                    hasExplicitDefault: choice.hasExplicitDefault,
                    isSaved: choice.isSaved,
                    isRequired: choice.isRequired,
                    choices: choice.choices,
                    isChoiceDeclaration: true
                )
            case .invalidChoice(let reason):
                diagnostics.append(
                    PlaceholderSyntaxDiagnostic(
                        range: expression.range,
                        expression: expression.raw,
                        message: "Invalid authored choices in \(expression.raw): \(reason)"
                    ))
                occurrence = parseLegacyOccurrence(expression)
            case .legacy:
                occurrence = parseLegacyOccurrence(expression)
            }

            if !occurrence.key.isEmpty { occurrences.append(occurrence) }
        }

        diagnostics += PlaceholderAggregator.findChoiceConflicts(occurrences)
        diagnostics = diagnostics.stableSorted {
            ($0.range.start, $0.range.end) < ($1.range.start, $1.range.end)
        }

        return PlaceholderSyntaxResult(
            occurrences: occurrences,
            placeholders: PlaceholderAggregator.aggregate(text, occurrences: occurrences),
            diagnostics: diagnostics
        )
    }

    /// Unique placeholders in form order (`extractPlaceholders` in TS).
    public static func extractPlaceholders(_ text: String) -> [Placeholder] {
        parse(text).placeholders
    }

    struct ScannedExpression {
        var raw: String
        var range: PlaceholderSourceRange
        var indices: Range<String.Index>
        var content: String
    }

    /// Finds `{{…}}` expressions, consuming quoted conditional labels as a
    /// unit so braces and template examples in a label never become fields.
    static func scanExpressions(_ text: String) -> [ScannedExpression] {
        guard text.contains(/\{\{/.matchingSemantics(.unicodeScalar)) else { return [] }
        let scalars = Array(text.unicodeScalars)
        let count = scalars.count
        guard count >= 5 else { return [] }
        let indices = Array(text.unicodeScalars.indices) + [text.endIndex]
        var offsets = [Int](repeating: 0, count: count + 1)
        for index in scalars.indices {
            offsets[index + 1] = offsets[index] + (scalars[index].value > 0xFFFF ? 2 : 1)
        }

        // Cache where each candidate must end. Retrying a greedy regex at
        // every unfinished opener rescans the same suffix quadratically,
        // freezing live validation even for moderately sized pasted text.
        var nextBrace = [Int](repeating: count, count: count + 1)
        var conditionalEnd = nextBrace
        var nextQuote: Int?
        for index in scalars.indices.reversed() {
            nextBrace[index] = scalars[index] == "}" ? index : nextBrace[index + 1]
            switch scalars[index] {
            case "}": conditionalEnd[index] = index
            case "\"":
                conditionalEnd[index] = nextQuote.map { conditionalEnd[$0 + 1] } ?? count
                nextQuote = index
            default: conditionalEnd[index] = conditionalEnd[index + 1]
            }
        }

        func isClose(_ index: Int, after start: Int) -> Bool {
            index > start && index + 1 < count && scalars[index + 1] == "}"
        }

        var result: [ScannedExpression] = []
        var cursor = 0
        while cursor + 1 < count {
            guard scalars[cursor] == "{", scalars[cursor + 1] == "{" else {
                cursor += 1
                continue
            }
            let start = cursor + 2
            var end = nextBrace[start]
            if start + 3 < count,
                scalars[start] == "#", scalars[start + 1] == "i", scalars[start + 2] == "f",
                scalars[start + 3].properties.isWhitespace,
                isClose(conditionalEnd[start], after: start + 4)
            {
                end = conditionalEnd[start]
            }
            guard isClose(end, after: start) else {
                cursor += 1
                continue
            }
            let range = indices[cursor]..<indices[end + 2]
            result.append(ScannedExpression(
                raw: String(text[range]),
                range: PlaceholderSourceRange(start: offsets[cursor], end: offsets[end + 2]),
                indices: range,
                content: String(text[indices[start]..<indices[end]])
            ))
            cursor = end + 2
        }
        return result
    }

    private static func parseLegacyOccurrence(_ expression: ScannedExpression) -> ParsedValuePlaceholderOccurrence {
        var content = expression.content.trimmed
        let isSaved = content.unicodeScalars.first != "!"
        if !isSaved { content = String(content.unicodeScalars.dropFirst()).trimmed }

        // Delimiters are scalars, even when a following combining mark makes
        // them part of the same extended grapheme cluster.
        let scalars = content.unicodeScalars
        let pipeIndex = scalars.lastIndex(of: "|")
        let hasExplicitDefault = pipeIndex != nil
        let explicitDefault = pipeIndex.map { String(scalars[scalars.index(after: $0)...]).trimmed }
        let coreContent = pipeIndex.map { String(scalars[..<$0]).trimmed } ?? content
        let parts = coreContent.unicodeScalars.split(separator: ":", omittingEmptySubsequences: false).map(String.init)

        let key: String
        var prefixWrapper: String?
        var suffixWrapper: String?

        if parts.count == 1 {
            key = parts[0].trimmed
        } else if parts.count == 3 {
            prefixWrapper = parts[0].nilIfEmpty
            key = parts[1].trimmed
            suffixWrapper = parts[2].nilIfEmpty
        } else {
            key = coreContent
        }

        let hasNonEmptyWrappers = prefixWrapper != nil || suffixWrapper != nil
        return ParsedValuePlaceholderOccurrence(
            raw: expression.raw,
            range: expression.range,
            indices: expression.indices,
            key: key,
            prefixWrapper: prefixWrapper,
            suffixWrapper: suffixWrapper,
            explicitDefault: explicitDefault,
            hasExplicitDefault: hasExplicitDefault,
            isSaved: isSaved,
            isRequired: !hasExplicitDefault && !hasNonEmptyWrappers,
            isChoiceDeclaration: false
        )
    }
}
