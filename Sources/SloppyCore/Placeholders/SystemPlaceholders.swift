import Foundation

/// ALL-CAPS placeholders that resolve from the clock without user input.
///
/// - `{{DATE}}` → `2024-01-15` (local calendar date, not UTC)
/// - `{{TIME}}` → `14:30`
/// - `{{DATETIME}}` → `2024-01-15 14:30`
/// - `{{TODAY}}` → `Monday, January 15, 2024`
/// - `{{NOW}}` → `2024-01-15T14:30:00.000Z` (UTC)
/// - `{{YEAR}}` → `2024`
/// - `{{MONTH}}` → `January`
/// - `{{DAY}}` → `Monday`
public enum SystemPlaceholders {
    /// The supported names, in the TS declaration order.
    public static let names = ["DATE", "TIME", "DATETIME", "TODAY", "NOW", "YEAR", "MONTH", "DAY"]

    /// The value of the system placeholder `name` at `now`, or nil for an unknown name.
    public static func value(for name: String, now: Int64, timeZone: TimeZone = .current) -> String? {
        let date = Date(epochMilliseconds: now)
        switch name {
        case "DATE": return format(date, "yyyy-MM-dd", timeZone)
        case "TIME": return format(date, "HH:mm", timeZone)
        case "DATETIME": return format(date, "yyyy-MM-dd HH:mm", timeZone)
        case "TODAY": return format(date, "EEEE, MMMM d, yyyy", timeZone)
        case "NOW": return format(date, "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", TimeZone(identifier: "UTC")!)
        case "YEAR": return format(date, "y", timeZone)
        case "MONTH": return format(date, "MMMM", timeZone)
        case "DAY": return format(date, "EEEE", timeZone)
        default: return nil
        }
    }

    /// Replaces every `{{NAME}}` (whitespace allowed around the name, as the
    /// parser trims keys) with its value. Call this before extracting
    /// placeholders so the form never prompts for system values. Lowercase
    /// names are left alone.
    public static func process(_ text: String, now: Int64, timeZone: TimeZone = .current) -> String {
        let regex = /\{\{\s*(DATETIME|DATE|TIME|TODAY|NOW|YEAR|MONTH|DAY)\s*\}\}/.matchingSemantics(.unicodeScalar)
        // Conditional labels can contain literal template examples. The shared
        // scanner consumes the entire opener, including braces inside quotes.
        let conditionalOpeners = PlaceholderSyntaxParser.scanExpressions(text)
            .filter { $0.content.trimmed.contains(/^#if\s/.matchingSemantics(.unicodeScalar)) }
            .map(\.indices)
        var openerIndex = 0
        var result = ""
        var cursor = text.startIndex
        for match in text.matches(of: regex) {
            result += text[cursor..<match.range.lowerBound]
            while openerIndex < conditionalOpeners.count,
                conditionalOpeners[openerIndex].upperBound <= match.range.lowerBound {
                openerIndex += 1
            }
            let insideOpener = openerIndex < conditionalOpeners.count
                && conditionalOpeners[openerIndex].lowerBound <= match.range.lowerBound
                && match.range.upperBound <= conditionalOpeners[openerIndex].upperBound
            result += insideOpener
                ? String(match.output.0)
                : value(for: String(match.output.1), now: now, timeZone: timeZone) ?? String(match.output.0)
            cursor = match.range.upperBound
        }
        return result + text[cursor...]
    }

    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
