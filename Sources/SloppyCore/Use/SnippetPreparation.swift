import Foundation

/// Final content ready for the clipboard, plus the values to track with the use.
public struct PreparedSnippet: Sendable, Hashable {
    public var content: String
    public var placeholderValues: [PlaceholderValueToRecord]

    public init(content: String, placeholderValues: [PlaceholderValueToRecord] = []) {
        self.content = content
        self.placeholderValues = placeholderValues
    }
}

/// A snippet whose system placeholders are already resolved, and the user
/// placeholders the form must ask for.
public struct PlaceholderFormRequest: Sendable, Hashable {
    public var snippet: Snippet
    public var placeholders: [Placeholder]

    public init(snippet: Snippet, placeholders: [Placeholder]) {
        self.snippet = snippet
        self.placeholders = placeholders
    }
}

public struct MissingPlaceholderHistoryError: Error, Sendable, Hashable, CustomStringConvertible {
    public var placeholderKey: String

    public init(placeholderKey: String) {
        self.placeholderKey = placeholderKey
    }

    public var description: String { "No history for {{\(placeholderKey)}}" }
}

/// Turns a stored snippet into clipboard content: directly, through the
/// placeholder form, or with the last-used values.
public enum SnippetPreparation {
    public enum Plan: Sendable, Hashable {
        /// No user placeholders: the content is final.
        case direct(PreparedSnippet)
        case form(PlaceholderFormRequest)
    }

    public enum LastValuesAvailability: Sendable, Hashable {
        /// The snippet has no required user placeholders, so the action is hidden.
        case notApplicable
        /// Some required key in the selected branches has no history yet.
        case unavailable
        case available
    }

    /// Resolves system placeholders, then either finishes the content or asks for a form.
    public static func plan(for snippet: Snippet, now: Int64, timeZone: TimeZone = .current) -> Plan {
        let processed = SystemPlaceholders.process(snippet.content, now: now, timeZone: timeZone)
        let placeholders = PlaceholderSyntaxParser.extractPlaceholders(processed)
        guard placeholders.isEmpty else {
            var formSnippet = snippet
            formSnippet.content = processed
            return .form(PlaceholderFormRequest(snippet: formSnippet, placeholders: placeholders))
        }
        return .direct(PreparedSnippet(content: ConditionalBlocks.process(processed, values: [:])))
    }

    /// Renders already system-processed content with the form's final values.
    /// Values found only in excluded branches do not count as history uses,
    /// unless they determined a conditional branch that contributed to output.
    public static func submission(
        content: String,
        placeholders: [Placeholder],
        finalValues: [String: String]
    ) -> PreparedSnippet {
        let resolution = ConditionalBlocks.resolve(content, values: finalValues)
        let afterBlocks = resolution.text
        let activeKeys = Set(PlaceholderSyntaxParser.parse(afterBlocks).occurrences.map(\.key))
            .union(resolution.conditionKeys)
        let trackedPlaceholders = placeholders.filter { $0.isGuardOnly || activeKeys.contains($0.key) }
        return PreparedSnippet(
            content: PlaceholderRenderer.replacePlaceholders(afterBlocks, values: finalValues, placeholders: placeholders),
            placeholderValues: trackedValues(trackedPlaceholders, finalValues: finalValues)
        )
    }

    /// Every placeholder with its submitted value and save flag; the repository
    /// applies the no-save and blank exclusions when recording.
    public static func trackedValues(
        _ placeholders: [Placeholder],
        finalValues: [String: String]
    ) -> [PlaceholderValueToRecord] {
        placeholders.map { placeholder in
            PlaceholderValueToRecord(
                key: placeholder.key,
                value: finalValues[placeholder.key] ?? "",
                isSaved: placeholder.isSaved
            )
        }
    }

    /// Required user keys after resolving system placeholders. Modified forms
    /// such as `{{!DATE}}` remain user fields even when their key is a system name.
    public static func requiredUserKeys(in content: String, now: Int64, timeZone: TimeZone = .current) -> [String] {
        let processed = SystemPlaceholders.process(content, now: now, timeZone: timeZone)
        return PlaceholderSyntaxParser.extractPlaceholders(processed)
            .filter(\.isRequired)
            .map(\.key)
    }

    /// Keep canonical requirements, but only for value occurrences in the
    /// selected branches. A declaration in another branch can still own a
    /// visible reference's required/optional status and authored choices.
    static func activeRequiredPlaceholders(
        in content: String, placeholders: [Placeholder], values: [String: String]
    ) -> [Placeholder] {
        let selected = ConditionalBlocks.process(content, values: values)
        let keys = Set(PlaceholderSyntaxParser.parse(selected).occurrences.map(\.key))
        return placeholders.filter { $0.isRequired && keys.contains($0.key) }
    }

    public static func lastValuesAvailability(
        for snippet: Snippet,
        history: PlaceholderHistory,
        now: Int64,
        timeZone: TimeZone = .current
    ) -> LastValuesAvailability {
        let processed = SystemPlaceholders.process(snippet.content, now: now, timeZone: timeZone)
        let placeholders = PlaceholderSyntaxParser.extractPlaceholders(processed)
        guard placeholders.contains(where: \.isRequired) else { return .notApplicable }
        let values = lastValues(placeholders, history: history)
        let required = activeRequiredPlaceholders(in: processed, placeholders: placeholders, values: values)
        return required.allSatisfy { values[$0.key] != nil } ? .available : .unavailable
    }

    /// IDs of snippets whose required keys in the selected branches all have history.
    public static func historyAvailability(
        for snippets: [Snippet],
        history: PlaceholderHistory,
        now: Int64,
        timeZone: TimeZone = .current
    ) -> Set<String> {
        var result = Set<String>()
        for snippet in snippets
        where lastValuesAvailability(for: snippet, history: history, now: now, timeZone: timeZone) == .available {
            result.insert(snippet.id)
        }
        return result
    }

    /// "Paste with Last Values": required keys take their last-used value and
    /// optional keys and guard-only toggles take their authored defaults.
    /// Missing history only blocks fields in the selected conditional branches.
    public static func prepareWithLastValues(
        _ snippet: Snippet,
        history: PlaceholderHistory,
        now: Int64,
        timeZone: TimeZone = .current
    ) throws(MissingPlaceholderHistoryError) -> PreparedSnippet {
        let processed = SystemPlaceholders.process(snippet.content, now: now, timeZone: timeZone)
        let placeholders = PlaceholderSyntaxParser.extractPlaceholders(processed)
        let finalValues = lastValues(placeholders, history: history)
        for placeholder in activeRequiredPlaceholders(in: processed, placeholders: placeholders, values: finalValues)
        where finalValues[placeholder.key] == nil {
            throw MissingPlaceholderHistoryError(placeholderKey: placeholder.key)
        }

        return submission(content: processed, placeholders: placeholders, finalValues: finalValues)
    }

    private static func lastValues(_ placeholders: [Placeholder], history: PlaceholderHistory) -> [String: String] {
        var finalValues: [String: String] = [:]

        for placeholder in placeholders where placeholder.isRequired {
            finalValues[placeholder.key] = PlaceholderHistoryRanking.lastUsedValue(history[placeholder.key] ?? [])
        }
        for placeholder in placeholders where !placeholder.isRequired && finalValues[placeholder.key] == nil {
            if placeholder.isGuardOnly {
                finalValues[placeholder.key] = placeholder.defaultOn ? "true" : ""
            } else if let defaultValue = placeholder.defaultValue {
                finalValues[placeholder.key] = defaultValue
            }
        }

        return finalValues
    }
}
