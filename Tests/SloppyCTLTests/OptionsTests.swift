import Testing
import SloppyCore
@testable import sloppyctl

@Suite struct OptionsTests {
    @Test func tagOptionTreatsFormerSentinelAsLiteralTag() throws {
        let options = try Options(["--tag", "__untagged__"][...])
        let snippets = [
            Snippet(id: "tagged", title: "Tagged", content: "Text", tags: ["__untagged__"], createdAt: 0, updatedAt: 0),
            Snippet(id: "empty", title: "Empty", content: "Text", createdAt: 0, updatedAt: 0),
        ]
        #expect(SnippetListPipeline.filter(snippets, query: ParsedQuery(),
            options: options.filterOptions, now: 0).map(\.id) == ["tagged"])
    }

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

    @Test(arguments: [["--merge", "--replace"], ["--replace", "--merge"]])
    func conflictingImportModesFail(flags: [String]) {
        #expect(throws: CommandError.self) { try Options(flags[...]) }
    }

    @Test(arguments: [
        ("stats", ["--replace"]),
        ("import", ["--tag", "work"]),
        ("render", ["--json"]),
        ("search", ["--text", "hello"]),
    ])
    func rejectsFlagsForOtherCommands(command: String, flags: [String]) throws {
        let options = try Options(flags[...])
        #expect(throws: CommandError.self) { try options.validate(for: command) }
    }

    @Test(arguments: [
        ("import", ["--replace", "--json"]),
        ("stats", ["--json"]),
        ("render", ["--text", "hello"]),
        ("search", ["--tag", "work", "--sort", "alphabetical"]),
    ])
    func permitsRelevantCommandFlags(command: String, flags: [String]) throws {
        try Options(flags[...]).validate(for: command)
    }
}
