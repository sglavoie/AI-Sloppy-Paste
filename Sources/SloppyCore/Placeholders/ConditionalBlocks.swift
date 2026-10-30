import Foundation

/// The branches of one `{{#if key}}…{{/if}}` block, as authored.
public struct ConditionalBlockBody: Sendable, Hashable {
    public var ifBody: String
    public var elseBody: String?

    public init(ifBody: String, elseBody: String? = nil) {
        self.ifBody = ifBody
        self.elseBody = elseBody
    }
}

/// `{{#if key}}…{{#else}}…{{/else}}{{/if}}` blocks. `{{/else}}` is optional,
/// the key may carry a `+` default-on prefix and a trailing `"Label"`.
///
/// All matching uses Unicode-scalar semantics so a combining mark or emoji
/// modifier next to a tag can never hide it, matching the JS UTF-16 regexes.
public enum ConditionalBlocks {
    /// Resolves every block against `values`, innermost first.
    /// A key is truthy when its value is non-blank; guard-only
    /// keys use `"true"` and `""`. One leading and one trailing newline of the
    /// selected body are dropped, so a block on its own lines leaves no blank
    /// line behind. Placeholders inside the chosen body are left for
    /// `PlaceholderRenderer.replacePlaceholders`.
    public static func process(_ text: String, values: [String: String]) -> String {
        resolve(text, values: values).text
    }

    /// Includes condition inputs that contributed to the selected output.
    /// Conditions inside an excluded parent branch do not contribute.
    struct Resolution {
        var text: String
        var conditionKeys: Set<String> = []
    }

    static func resolve(_ text: String, values: [String: String]) -> Resolution {
        // An unfinished block cannot render. Avoid repeatedly searching for
        // a closer that is absent while the user is still authoring it.
        guard text.contains(/\{\{\/if\}\}/.matchingSemantics(.unicodeScalar)) else { return Resolution(text: text) }
        let open = /\{\{#if\s+((?:[^}"]|"[^"]*")+)\}\}/.matchingSemantics(.unicodeScalar)
        // Resolve blocks as their closing tags arrive, without rescanning the
        // entire document for every nesting level. The shared scanner also
        // keeps template examples inside quoted labels together.
        var stack = [RenderingBlock(opener: "", key: "")]
        var cursor = text.startIndex
        for expression in PlaceholderSyntaxParser.scanExpressions(text) {
            stack[stack.count - 1].append(text[cursor..<expression.indices.lowerBound])
            cursor = expression.indices.upperBound
            if let match = expression.raw.wholeMatch(of: open) {
                stack.append(RenderingBlock(opener: expression.raw, key: conditionKey(String(match.output.1))))
            } else if expression.raw == "{{#else}}", stack.count > 1, stack.last?.elseBody == nil {
                stack[stack.count - 1].elseBody = Resolution(text: "")
            } else if expression.raw == "{{/else}}", stack.count > 1,
                stack.last?.elseBody != nil, stack.last?.afterElseCloser == nil {
                stack[stack.count - 1].afterElseCloser = Resolution(text: "")
            } else if expression.raw == "{{/if}}", stack.count > 1 {
                let block = stack.removeLast()
                var body: Resolution
                if (values[block.key] ?? "").trimmed.isEmpty {
                    body = block.selectedElseBody
                } else {
                    body = block.ifBody
                }
                body.conditionKeys.insert(block.key)
                stack[stack.count - 1].append(stripOuterNewlines(body.text), conditionKeys: body.conditionKeys)
            } else {
                stack[stack.count - 1].append(expression.raw)
            }
        }
        stack[stack.count - 1].append(text[cursor...])
        // Preserve unfinished outer blocks while retaining any complete
        // nested blocks already resolved, as in the editor's live preview.
        while stack.count > 1 {
            let block = stack.removeLast()
            stack[stack.count - 1].append(block.opener + block.ifBody.text, conditionKeys: block.ifBody.conditionKeys)
            if let elseBody = block.elseBody {
                stack[stack.count - 1].append("{{#else}}" + elseBody.text, conditionKeys: elseBody.conditionKeys)
                if let suffix = block.afterElseCloser {
                    stack[stack.count - 1].append("{{/else}}" + suffix.text, conditionKeys: suffix.conditionKeys)
                }
            }
        }
        return stack[0].ifBody
    }

    private struct RenderingBlock {
        var opener: String
        var key: String
        var ifBody = Resolution(text: "")
        var elseBody: Resolution?
        /// Text after a structural closer, kept for unfinished or malformed blocks.
        var afterElseCloser: Resolution?

        var selectedElseBody: Resolution {
            var body = elseBody ?? Resolution(text: "")
            guard let suffix = afterElseCloser, !suffix.text.trimmed.isEmpty else { return body }
            body.text += "{{/else}}" + suffix.text
            body.conditionKeys.formUnion(suffix.conditionKeys)
            return body
        }

        mutating func append(_ text: some StringProtocol, conditionKeys: Set<String> = []) {
            if afterElseCloser != nil {
                afterElseCloser!.text.append(contentsOf: text)
                afterElseCloser!.conditionKeys.formUnion(conditionKeys)
            } else if elseBody != nil {
                elseBody!.text.append(contentsOf: text)
                elseBody!.conditionKeys.formUnion(conditionKeys)
            } else {
                ifBody.text.append(contentsOf: text)
                ifBody.conditionKeys.formUnion(conditionKeys)
            }
        }
    }

    /// The top-level bodies of every block guarded by `key`, in document
    /// order, for field previews. Nested blocks stay inside their parent body;
    /// unterminated blocks are skipped.
    public static func extractBodies(_ text: String, key: String) -> [ConditionalBlockBody] {
        let open = /\{\{#if\s+\+?([^\s}"]+)(?:\s+"[^"]*")?\s*\}\}/.matchingSemantics(.unicodeScalar)
        let renderingOpen = /\{\{#if\s+((?:[^}"]|"[^"]*")+)\}\}/.matchingSemantics(.unicodeScalar)
        let expressions = PlaceholderSyntaxParser.scanExpressions(text)
        var stack: [ExtractionBlock] = []
        var completed: [Int: (block: ExtractionBlock, close: Int)] = [:]
        // Match structural tokens once. Raw regex searches can see examples
        // inside value defaults as controls, and repeatedly rescan unfinished blocks.
        for (index, expression) in expressions.enumerated() {
            if expression.raw.wholeMatch(of: renderingOpen) != nil {
                stack.append(ExtractionBlock(opener: index))
            } else if expression.raw == "{{#else}}", let last = stack.indices.last,
                stack[last].elseStart == nil {
                stack[last].elseStart = index
            } else if expression.raw == "{{/else}}", let last = stack.indices.last,
                stack[last].elseStart != nil, stack[last].elseEnd == nil {
                stack[last].elseEnd = index
            } else if expression.raw == "{{/if}}", let block = stack.popLast() {
                completed[block.opener] = (block, index)
            }
        }

        var results: [ConditionalBlockBody] = []
        var index = 0
        while index < expressions.count {
            let expression = expressions[index]
            guard let match = expression.raw.wholeMatch(of: open), String(match.output.1).trimmed == key,
                let (block, close) = completed[index] else {
                index += 1
                continue
            }
            let start = expression.indices.upperBound
            let end = expressions[close].indices.lowerBound
            if let elseStart = block.elseStart {
                var elseEnd = end
                if let closer = block.elseEnd,
                    String(text[expressions[closer].indices.upperBound..<end]).trimmed.isEmpty {
                    elseEnd = expressions[closer].indices.lowerBound
                }
                results.append(ConditionalBlockBody(
                    ifBody: String(text[start..<expressions[elseStart].indices.lowerBound]),
                    elseBody: String(text[expressions[elseStart].indices.upperBound..<elseEnd])))
            } else {
                results.append(ConditionalBlockBody(ifBody: String(text[start..<end])))
            }
            index = close + 1
        }
        return results
    }

    private struct ExtractionBlock {
        var opener: Int
        var elseStart: Int?
        var elseEnd: Int?
    }

    /// `rawKey.trim()` minus a trailing `"Label"` and a leading `+`.
    static func conditionKey(_ rawKey: String) -> String {
        var key = rawKey.trimmed.replacing(/\s+"[^"]*"$/.matchingSemantics(.unicodeScalar), with: "")
        if key.unicodeScalars.first == "+" { key.unicodeScalars.removeFirst() }
        return key
    }

    /// Remove one complete line ending at each edge, preserving interior
    /// line endings and adjacent combining marks. CRLF is one line ending.
    private static func stripOuterNewlines(_ body: String) -> String {
        var scalars = body.unicodeScalars
        if scalars.first == "\r" {
            scalars.removeFirst()
            if scalars.first == "\n" { scalars.removeFirst() }
        } else if scalars.first == "\n" {
            scalars.removeFirst()
        }
        if scalars.last == "\n" {
            scalars.removeLast()
            if scalars.last == "\r" { scalars.removeLast() }
        } else if scalars.last == "\r" {
            scalars.removeLast()
        }
        return String(scalars)
    }
}
