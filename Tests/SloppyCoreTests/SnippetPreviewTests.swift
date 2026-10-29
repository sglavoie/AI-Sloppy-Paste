import Foundation
import Testing
@testable import SloppyCore

@Suite struct SnippetPreviewTests {
    /// 2024-03-15T14:30:45.000Z, a Friday.
    static let now: Int64 = 1_710_513_045_000
    static let utc = TimeZone(identifier: "UTC")!

    private func preview(_ content: String) -> String {
        SnippetPreview.build(content, now: Self.now, timeZone: Self.utc)
    }

    @Test func emptyWithoutPlaceholderSyntax() {
        #expect(preview("Plain content") == "")
    }

    @Test(arguments: ["\u{301}", "\u{FE0F}"])
    func leadingCombiningScalarsDoNotHidePlaceholders(mark: String) {
        let key = mark + "name"
        let content = "Hello {{" + key + "}}"
        #expect(PlaceholderSyntaxParser.extractPlaceholders(content).map(\.key) == [key])
        #expect(preview(content) == "Hello ⟨" + key + "⟩")
        #expect(PlaceholderRenderer.render(content, values: [key: "Ada"], now: Self.now) == "Hello Ada")
    }

    @Test func defaultsNoSaveLabelsAndWrappers() {
        #expect(preview("{{name}} {{role|Editor}} {{!$:amount: USD|10}}")
            == "⟨name⟩ ⟨role = \"Editor\"⟩ ⟨!$amount USD = \"10\"⟩")
    }

    @Test func decodedAuthoredChoicesWithExplicitDefault() {
        #expect(preview(#"{{tone[Formal|A\|B|\[Custom\]|Path\\Name]|Formal}} then {{tone}}"#)
            == #"⟨tone — choices: "Formal", "A|B", "[Custom]", "Path\\Name"; default: "Formal"⟩ then ⟨tone⟩"#)
    }

    @Test func choiceWithoutDefaultVersusExplicitEmptyDefault() {
        #expect(preview("{{tone[Formal|Casual]}} / {{detail[Short|Long]|}}")
            == #"⟨tone — choices: "Formal", "Casual"⟩ / ⟨detail — choices: "Short", "Long"; default: ""⟩"#)
    }

    @Test func conditionalBlocksBeforeInnerPlaceholders() {
        #expect(preview("{{#if name}}Hi {{name}}{{#else}}Hello{{/if}}") == "⟨if name: Hi ⟨name⟩ | else: Hello⟩")
    }

    @Test func nestedConditionalsKeepTheirOwnElseBranches() {
        let content = "{{#if outer}}A {{#if inner}}Hi {{name}}{{#else}}B{{/else}}{{/if}}{{#else}}C{{/if}}"
        #expect(preview(content) == "⟨if outer: A ⟨if inner: Hi ⟨name⟩ | else: B⟩ | else: C⟩")
    }

    @Test func largeNestedTemplateCanBePreviewedWhileEditing() {
        let depth = 4_000
        let content = String(repeating: "{{#if +a}}", count: depth)
            + "{{name}}" + String(repeating: "{{/if}}", count: depth)
        #expect(content.count < ValidationLimits.contentMaxLength)
        #expect(preview(content) == String(String(repeating: "⟨if a: ", count: depth).prefix(500)))
    }

    @Test(arguments: [
        ("  {{#if k}}\n \n{{/if}}  ", "  ⟨if k: ⟩  "),
        ("{{#if k}} \u{FEFF} hi \u{FEFF} {{/if}}", "⟨if k: hi⟩"),
        ("{{#if k}}\n{{#else}}\nno\n{{/else}}\n{{/if}}", "⟨if k: | else: \nno⟩"),
        ("Before {{#if outer}}\n{{#if inner}}B{{/if}} ", "Before {{#if outer}}\n⟨if inner: B⟩ "),
        (#"{{#if k "Include {{#if fake}}?"}}Hello{{/if}}"#, "⟨if k: Hello⟩"),
        ("{{#else}} {{#if k}}yes{{/if}} {{/else}}", "{{#else}} ⟨if k: yes⟩ {{/else}}"),
    ])
    func conditionalPreviewPreservesSurroundingText(content: String, expected: String) {
        #expect(preview(content) == expected)
    }

    @Test(arguments: [" ", "\t", "\n", "\r\n"])
    func previewAcceptsRenderingWhitespace(separator: String) {
        let content = "{{#if\(separator)+show \"Show date\"}}{{\(separator)DATE\(separator)}}{{/if}}"
        #expect(preview(content) == "⟨if show: ⟨DATE → 2024-03-15⟩⟩")
    }

    @Test func conditionalLabelsAndPlusPrefixAreHidden() {
        #expect(preview(#"{{#if +k "Add a note"}}Note{{/if}}"#) == "⟨if k: Note⟩")
    }

    @Test(arguments: ["Include {name}?", "Include }?", "Include {{name}}?"])
    func bracesInConditionalLabelsAreHidden(label: String) {
        let content = "{{#if +show \"\(label)\"}}Hello{{#else}}Hidden{{/if}}"
        #expect(preview(content) == "⟨if show: Hello | else: Hidden⟩")
    }

    @Test func systemPlaceholdersBeforeUserPlaceholders() {
        let result = preview("On {{DATE}}, greet {{name}}")
        #expect(result == "On ⟨DATE → 2024-03-15⟩, greet ⟨name⟩")
        #expect(!result.contains("{{DATE}}"))
    }

    @Test func capsAt500() {
        let result = preview("{{name}}" + String(repeating: "x", count: 600))
        #expect(result.utf16.count == 500)
        #expect(result.hasPrefix("⟨name⟩"))
    }

    @Test func capNeverSplitsAnEmoji() {
        let result = preview("{{a}}" + String(repeating: "x", count: 496) + "👍🏽tail")
        // "⟨a⟩" is 3 units, 496 x's reach 499, and the 4-unit emoji no longer fits.
        #expect(result.utf16.count == 499)
        #expect(result.hasSuffix("x"))
    }
}
