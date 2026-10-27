import Testing
@testable import sloppyctl

@Suite struct OptionsTests {
    @Test func terminatorPreservesLiteralArguments() throws {
        let options = try Options(["--json", "--", "--favorites", "--", "name=--data"][...])
        #expect(options.json)
        #expect(!options.filterOptions.showOnlyFavorites)
        #expect(options.positional == ["--favorites", "--", "name=--data"])
    }

    @Test func terminatorCanBeAnOptionValue() throws {
        let options = try Options(["--text", "--", "name=Ada"][...])
        #expect(options.text == "--")
        #expect(options.positional == ["name=Ada"])
    }

    @Test func unknownOptionsStillFailBeforeTerminator() {
        #expect(throws: CommandError.self) { try Options(["--unknown"][...]) }
    }
}
