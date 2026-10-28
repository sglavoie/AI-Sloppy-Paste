import Foundation
import Testing
@testable import SloppyCore

@Suite struct PlaceholderScannerTests {
    @Test(arguments: [
        ("{{}} {{name}}", ["{{name}}"]),
        ("{{broken} then {{name}}", ["{{name}}"]),
        ("{{unfinished {{name}}", ["{{unfinished {{name}}"]),
        (#"{{#if show "Example }} {{name}}"}}Yes{{/if}}"#,
            [#"{{#if show "Example }} {{name}}"}}"#, "{{/if}}"]),
        (#"{{#if show "unfinished}} {{name}}"#, [#"{{#if show "unfinished}}"#, "{{name}}"]),
        (#"{{value "}} {{other}}"#, [#"{{value "}}"#, "{{other}}"]),
        ("{{#if }} {{#if  }}", ["{{#if }}", "{{#if  }}"]),
    ])
    func preservesExpressionBoundaries(text: String, expected: [String]) {
        #expect(PlaceholderSyntaxParser.scanExpressions(text).map(\.raw) == expected)
    }

    @Test func rangesPreserveUnicodeScalarsAndUTF16Offsets() {
        let text = "👩‍💻 {{\u{301}name}}\u{301} {{other}}"
        let expressions = PlaceholderSyntaxParser.scanExpressions(text)
        #expect(expressions.map(\.raw) == ["{{\u{301}name}}", "{{other}}"])
        #expect(expressions.first?.range == PlaceholderSourceRange(start: 6, end: 15))
        for expression in expressions {
            let range = NSRange(location: expression.range.start,
                length: expression.range.end - expression.range.start)
            #expect((text as NSString).substring(with: range) == expression.raw)
            #expect(String(text[expression.indices]) == expression.raw)
        }
    }

    @Test(arguments: ["{{name ", "{{#if "])
    func longUnfinishedContentStillFindsLaterValidExpressions(opener: String) {
        let unfinished = String(repeating: opener, count: 4_000)
        #expect(PlaceholderSyntaxParser.parse(unfinished).placeholders.isEmpty)
        #expect(PlaceholderRenderer.render(unfinished, values: [:], now: 0) == unfinished)
        #expect(SnippetPreview.build(unfinished, now: 0) == String(unfinished.prefix(500)))
        // A single closing brace invalidates all earlier candidates, while
        // the complete expression after it must still be recognized.
        let content = unfinished + "} Hello {{name}}"
        #expect(PlaceholderSyntaxParser.extractPlaceholders(content).map(\.key) == ["name"])
        #expect(PlaceholderRenderer.render(content, values: ["name": "Ada"], now: 0)
            == unfinished + "} Hello Ada")
    }
}
