import Testing
@testable import sloppyctl

@Suite struct RenderValuesTests {
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
