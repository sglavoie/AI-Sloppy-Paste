import Foundation

/// The `is:`/`not:` flags a query can test.
public enum BooleanFilter: String, Sendable, Hashable, CaseIterable {
    case favorite
    case bookmarked
    case archived
    case untagged
}

/// A search query split into operators and the remaining fuzzy text.
public struct ParsedQuery: Sendable, Hashable {
    /// Snippet must have all these tags (hierarchical matching).
    public var tags: [String] = []
    /// Snippet must have none of these tags.
    public var notTags: [String] = []
    /// Snippet title must carry all these `Prefix:` contexts.
    public var contexts: [String] = []
    /// Snippet title must carry none of these contexts.
    public var notContexts: [String] = []
    public var isFilters: [BooleanFilter] = []
    public var notFilters: [BooleanFilter] = []
    /// Case-insensitive substrings of the title or content.
    public var exactPhrases: [String] = []
    /// Remaining words; each must appear in the title, content or a tag.
    public var fuzzyText = ""

    public init(
        tags: [String] = [], notTags: [String] = [], contexts: [String] = [], notContexts: [String] = [],
        isFilters: [BooleanFilter] = [], notFilters: [BooleanFilter] = [], exactPhrases: [String] = [],
        fuzzyText: String = ""
    ) {
        self.tags = tags
        self.notTags = notTags
        self.contexts = contexts
        self.notContexts = notContexts
        self.isFilters = isFilters
        self.notFilters = notFilters
        self.exactPhrases = exactPhrases
        self.fuzzyText = fuzzyText
    }

    /// True when anything but plain fuzzy text is present.
    public var hasStructuredOperators: Bool {
        !tags.isEmpty || !notTags.isEmpty || !contexts.isEmpty || !notContexts.isEmpty
            || !isFilters.isEmpty || !notFilters.isEmpty || !exactPhrases.isEmpty
    }

    /// True when the query filters anything; fuzzy text counts.
    public var hasOperators: Bool {
        hasStructuredOperators || !fuzzyText.isEmpty
    }

    public var isEmpty: Bool { !hasOperators }
}

/// Parses the search field syntax:
///
/// - `tag:work` / `not:tag:personal`: has (or lacks) the tag or a child of it
/// - `ctx:asl` / `not:ctx:asl`: the title does (or does not) carry the `asl:` context
/// - tag and context values with spaces can be quoted: `ctx:"dead code"`
/// - `is:favorite` / `not:archived`: favorite, bookmarked, archived or untagged
/// - `"exact phrase"`: case-insensitive substring of the title or content
/// - anything else: fuzzy words
///
/// Malformed operators (`tag:`, `is:invalid`, an unclosed quote) fall back to fuzzy text.
public enum QueryParser {
    public static func parse(_ query: String) -> ParsedQuery {
        var result = ParsedQuery()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return result }

        // Keep a quoted operator value together, and consume whole phrases
        // before looking for operators inside them. Consume an unclosed quote
        // through the end, so its contents cannot become active filters.
        let tokens = /(not:tag:|not:ctx:|tag:|ctx:)"((?:\\[\s\S]|[^"\\])*)"|"((?:\\[\s\S]|[^"\\])+)"|[^\s"]*"(?:\\[\s\S]|[^"\\])*\\?$|\S+/
            .matchingSemantics(.unicodeScalar)
        var fuzzyTokens: [String] = []
        for match in query.matches(of: tokens) {
            if let operation = match.output.1, let quotedValue = match.output.2 {
                let value = unescapeQuoted(quotedValue).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty, consume(Substring(String(operation) + value), into: &result) { continue }
            } else if let quotedPhrase = match.output.3 {
                let phrase = unescapeQuoted(quotedPhrase).trimmingCharacters(in: .whitespacesAndNewlines)
                if !phrase.isEmpty { result.exactPhrases.append(phrase) }
                continue
            } else if !match.output.0.contains("\""), consume(match.output.0, into: &result) {
                continue
            }
            fuzzyTokens.append(String(match.output.0))
        }
        result.fuzzyText = fuzzyTokens.joined(separator: " ")
        return result
    }

    /// Only quotes and backslashes are escaped in query values.
    private static func unescapeQuoted(_ text: Substring) -> String {
        String(text).replacing(/\\(["\\])/.matchingSemantics(.unicodeScalar)) { String($0.output.1) }
    }

    /// Records an operator token and returns whether it was one. `not:tag:` and
    /// `not:ctx:` are checked before the generic `not:`, which would otherwise
    /// reject them as unknown booleans and leave them as fuzzy text.
    private static func consume(_ token: Substring, into result: inout ParsedQuery) -> Bool {
        if let value = value(of: token, after: "not:tag:") {
            result.notTags.append(TagNormalization.normalizeTag(value))
        } else if let value = value(of: token, after: "not:ctx:") {
            result.notContexts.append(TitleContext.normalize(value))
        } else if let value = value(of: token, after: "tag:") {
            result.tags.append(TagNormalization.normalizeTag(value))
        } else if let value = value(of: token, after: "ctx:") {
            result.contexts.append(TitleContext.normalize(value))
        } else if let value = value(of: token, after: "not:"), let filter = BooleanFilter(rawValue: value) {
            result.notFilters.append(filter)
        } else if let value = value(of: token, after: "is:"), let filter = BooleanFilter(rawValue: value) {
            result.isFilters.append(filter)
        } else {
            return false
        }
        return true
    }

    /// The non-empty rest of `token` after `prefix`, or nil.
    private static func value(of token: Substring, after prefix: String) -> String? {
        guard token.hasPrefix(prefix), token.count > prefix.count else { return nil }
        return String(token.dropFirst(prefix.count))
    }
}
