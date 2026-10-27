import Testing
import SloppyCore
@testable import sloppyctl

@Suite struct RenderValuesTests {
    @Test(arguments: [
        "{{tone[Formal|Casual]}}", "{{tone[Formal|Casual]|Casual}}", "{{tone[Formal|Casual]|}}",
        "{{(:tone[Formal|Casual]:)}}", "{{(:tone[Formal|Casual]:)|Casual}}",
    ])
    func authoredChoicesUseTheSameInitialValueAsTheForm(content: String) throws {
        let placeholders = PlaceholderSyntaxParser.extractPlaceholders(content)
        let form = PlaceholderFormModel(snippetContent: content, placeholders: placeholders, history: [:], now: 0)
        let values = try renderValues([], placeholders: placeholders)
        #expect(PlaceholderRenderer.render(content, values: values, now: 0) == form.previewContent)
        #expect(try renderValues(["tone=Custom"], placeholders: placeholders)["tone"] == "Custom")
        #expect(try renderValues(["tone="], placeholders: placeholders)["tone"] == "")
    }

    @Test(arguments: ["\u{0301}Ada", "\u{FE0F}value", "\u{200D}value", "Ada=Bob", "", "  Ada  "])
    func preservesAssignmentValue(value: String) throws {
        #expect(try renderValues(["name=" + value], placeholders: []) == ["name": value])
    }

    @Test func preservesUnicodeKey() throws {
        #expect(try renderValues(["名前=太郎"], placeholders: []) == ["名前": "太郎"])
    }

    @Test func rejectsAssignmentWithoutEquals() {
        #expect(throws: CommandError.self) {
            try renderValues(["name"], placeholders: [])
        }
    }
}
