import Foundation
import Testing
@testable import SloppyCore

@Suite struct SnippetPreparationTests {
    /// 2024-03-15T14:30:45.000Z.
    static let now: Int64 = 1_710_513_045_000
    static let utc = TimeZone(identifier: "UTC")!

    private func snippet(_ content: String, id: String = "s1") -> Snippet {
        Snippet(id: id, title: "T", content: content, createdAt: 0, updatedAt: 0)
    }

    private func history(_ pairs: [String: String]) -> PlaceholderHistory {
        pairs.mapValues { [PlaceholderHistoryValue(value: $0, useCount: 1, lastUsed: 5, createdAt: 1)] }
    }

    @Test func directPlanResolvesSystemPlaceholdersAndConditionals() {
        let plan = SnippetPreparation.plan(for: snippet("On {{DATE}}\n"), now: Self.now,
            timeZone: Self.utc)
        #expect(plan == .direct(PreparedSnippet(content: "On 2024-03-15\n")))
    }

    @Test func formPlanCarriesProcessedContentAndUserPlaceholders() {
        let plan = SnippetPreparation.plan(for: snippet("{{YEAR}} {{name}}"), now: Self.now, timeZone: Self.utc)
        guard case .form(let request) = plan else {
            Issue.record("expected a form plan")
            return
        }
        #expect(request.snippet.content == "2024 {{name}}")
        #expect(request.snippet.id == "s1")
        #expect(request.placeholders.map(\.key) == ["name"])
    }

    @Test func lastValuesAvailability() {
        let s = snippet("{{a}} {{b}} {{opt|x}} {{DATE}}")
        #expect(SnippetPreparation.lastValuesAvailability(for: snippet("no {{opt|x}}"), history: [:], now: Self.now)
            == .notApplicable)
        #expect(SnippetPreparation.lastValuesAvailability(for: s, history: history(["a": "1"]), now: Self.now)
            == .unavailable)
        #expect(SnippetPreparation.lastValuesAvailability(for: s, history: history(["a": "1", "b": "2"]),
            now: Self.now) == .available)
    }

    @Test func historyAvailabilityListsSnippetsWithAllRequiredHistory() {
        let snippets = [
            snippet("{{a}}", id: "has"),
            snippet("{{a}} {{b}}", id: "missing"),
            snippet("plain", id: "plain"),
            snippet("{{opt|x}}", id: "optional-only"),
        ]
        #expect(SnippetPreparation.historyAvailability(for: snippets, history: history(["a": "1"]), now: Self.now)
            == ["has"])
    }

    @Test(arguments: SystemPlaceholders.names)
    func modifiedSystemNamesRemainUserFieldsForLastValues(key: String) throws {
        let s = snippet("{{DATE}} {{!\(key)}} {{name}}")
        let values = history([key: "custom", "name": "Ada"])
        #expect(SnippetPreparation.requiredUserKeys(in: s.content, now: Self.now) == [key, "name"])
        #expect(SnippetPreparation.lastValuesAvailability(for: s, history: history(["name": "Ada"]),
            now: Self.now) == .unavailable)
        #expect(throws: MissingPlaceholderHistoryError(placeholderKey: key)) {
            try SnippetPreparation.prepareWithLastValues(s, history: history(["name": "Ada"]), now: Self.now)
        }
        let prepared = try SnippetPreparation.prepareWithLastValues(s, history: values,
            now: Self.now, timeZone: Self.utc)
        #expect(prepared.content == "2024-03-15 custom Ada")
        guard case .form(let request) = SnippetPreparation.plan(for: s, now: Self.now, timeZone: Self.utc) else {
            Issue.record("Expected a form for user placeholders")
            return
        }
        var form = PlaceholderFormModel(snippetContent: request.snippet.content,
            placeholders: request.placeholders, history: values, now: Self.now)
        #expect(prepared == form.prepareSubmission())
    }

    @Test func lastValuesTracksOptionalUserFieldsNamedLikeSystemPlaceholders() throws {
        let prepared = try SnippetPreparation.prepareWithLastValues(
            snippet("{{name}} {{DATE|later}}"), history: history(["name": "Ada"]), now: Self.now)
        #expect(prepared.content == "Ada later")
        #expect(prepared.placeholderValues == [.init(key: "name", value: "Ada"), .init(key: "DATE", value: "later")])
    }

    @Test func prepareWithLastValuesFillsRequiredAndDefaults() throws {
        let values: PlaceholderHistory = ["name": [
            PlaceholderHistoryValue(value: "Old", useCount: 9, lastUsed: 1, createdAt: 1),
            PlaceholderHistoryValue(value: "Ada", useCount: 1, lastUsed: 9, createdAt: 1),
        ]]
        let prepared = try SnippetPreparation.prepareWithLastValues(
            snippet("{{DATE}} {{name}}{{(:role:)|dev}}{{#if name}}!{{/if}}{{opt|}}"),
            history: values, now: Self.now, timeZone: Self.utc)
        #expect(prepared.content == "2024-03-15 Ada(dev)!")
        #expect(prepared.placeholderValues == [
            .init(key: "name", value: "Ada"), .init(key: "role", value: "dev"), .init(key: "opt", value: ""),
        ])
    }

    @Test func prepareWithLastValuesThrowsForMissingHistory() {
        #expect(throws: MissingPlaceholderHistoryError(placeholderKey: "b")) {
            try SnippetPreparation.prepareWithLastValues(snippet("{{a}} {{b}}"), history: history(["a": "1"]),
                now: Self.now)
        }
        #expect(MissingPlaceholderHistoryError(placeholderKey: "b").description == "No history for {{b}}")
    }

    @Test(arguments: ["", " \t\n", "\u{FEFF}", " \u{FEFF}\n"])
    func blankHistoryCannotSatisfyRequiredFields(blank: String) {
        let s = snippet("Hello {{name}}")
        let values = history(["name": blank])
        #expect(SnippetPreparation.lastValuesAvailability(for: s, history: values, now: Self.now) == .unavailable)
        #expect(throws: MissingPlaceholderHistoryError(placeholderKey: "name")) {
            try SnippetPreparation.prepareWithLastValues(s, history: values, now: Self.now)
        }
    }

    @Test(arguments: [
        "{{token}} {{!token}}",
        "{{!token}} {{token}}",
        "{{!token}} {{token[one|two]}}",
        "{{token[one|two]}} {{!token}}",
        "{{token}} {{!token[one|two]}}",
        "{{!token[one|two]}} {{token}}",
    ])
    func repeatedNoSavePlaceholderNeverEntersHistory(content: String) throws {
        let s = snippet(content)
        let placeholders = PlaceholderSyntaxParser.extractPlaceholders(content)
        var form = PlaceholderFormModel(snippetContent: content, placeholders: placeholders,
            history: [:], now: Self.now)
        form.setCustomValue("token", "secret")
        let submission = form.prepareSubmission()
        let prepared = try #require(submission)
        #expect(prepared.content == "secret secret")
        #expect(prepared.placeholderValues == [.init(key: "token", value: "secret", isSaved: false)])

        var repository = SnippetRepository(data: StorageData(snippets: [s]))
        try repository.recordUse(id: s.id, placeholderValues: prepared.placeholderValues, now: Self.now)
        #expect(repository.data.placeholderHistory.isEmpty)
        #expect(repository.snippets.first?.useCount == 1)
    }

    @Test func lastValuesSkipsBlankImportedHistoryWithoutTrimmingValidText() throws {
        let s = snippet("Hello {{name}}")
        let values: PlaceholderHistory = ["name": [
            .init(value: " Ada ", useCount: 1, lastUsed: 1, createdAt: 1),
            .init(value: " \u{FEFF}\n", useCount: 1, lastUsed: 2, createdAt: 2),
        ]]
        #expect(SnippetPreparation.lastValuesAvailability(for: s, history: values, now: Self.now) == .available)
        let prepared = try SnippetPreparation.prepareWithLastValues(s, history: values, now: Self.now)
        #expect(prepared.content == "Hello  Ada ")
        var form = PlaceholderFormModel(snippetContent: s.content,
            placeholders: PlaceholderSyntaxParser.extractPlaceholders(s.content), history: values, now: Self.now)
        #expect(form.prepareSubmission() == prepared)
    }

    @Test func lastValuesHonorsGuardDefaultsLikeTheForm() throws {
        let content = #"{{name}}{{#if +signature "Signature"}} — Thanks{{/if}}{{#if extra}} Extra{{#else}}!{{/if}}"#
        let values = history(["name": "Ada", "signature": "", "extra": "previous value"])
        var form = PlaceholderFormModel(snippetContent: content,
            placeholders: PlaceholderSyntaxParser.extractPlaceholders(content), history: values, now: Self.now)
        let prepared = try SnippetPreparation.prepareWithLastValues(
            snippet(content), history: values, now: Self.now)
        #expect(prepared.content == "Ada — Thanks!")
        #expect(prepared == form.prepareSubmission())
    }

    @Test func lastValuesDoesNotRequireHistoryForInactiveBranches() throws {
        let s = snippet("Hi {{name}}{{#if signature}} — {{signatureText}}{{/if}}")
        let values = history(["name": "Ada"])
        #expect(SnippetPreparation.lastValuesAvailability(for: s, history: values, now: Self.now) == .available)
        let prepared = try SnippetPreparation.prepareWithLastValues(s, history: values, now: Self.now)
        #expect(prepared.content == "Hi Ada")
    }

    @Test(arguments: [false, true])
    func unusedBranchValuesDoNotChangeHistory(useLastValues: Bool) throws {
        let s = snippet("{{#if formal}}Dear {{name}}{{#else}}Hi {{nickname}}{{/if}}")
        let saved = history(["name": "Ada", "nickname": "A"])
        var form = PlaceholderFormModel(snippetContent: s.content,
            placeholders: PlaceholderSyntaxParser.extractPlaceholders(s.content), history: saved, now: Self.now)
        // A value typed in a branch that is subsequently excluded must not be saved either.
        form.setCustomValue("name", "Unused edit")
        let prepared: PreparedSnippet
        if useLastValues {
            prepared = try SnippetPreparation.prepareWithLastValues(s, history: saved, now: Self.now)
        } else {
            let submission = form.prepareSubmission()
            prepared = try #require(submission)
        }
        #expect(prepared.content == "Hi A")
        var repository = SnippetRepository(data: StorageData(snippets: [s], placeholderHistory: saved))
        try repository.recordUse(id: s.id, placeholderValues: prepared.placeholderValues, now: Self.now)
        #expect(repository.data.placeholderHistory["name"] == saved["name"])
        #expect(repository.data.placeholderHistory["nickname"]?.first?.useCount == 2)
        #expect(repository.data.placeholderHistory["nickname"]?.first?.lastUsed == Self.now)
        #expect(repository.snippets.first?.useCount == 1)
    }

    @Test func visibleReferenceStillRecordsValueDeclaredInHiddenBranch() throws {
        let s = snippet("{{#if formal}}{{name[Ada|Bob]}}{{/if}}Hi {{name}}")
        var form = PlaceholderFormModel(snippetContent: s.content,
            placeholders: PlaceholderSyntaxParser.extractPlaceholders(s.content), history: [:], now: Self.now)
        let submission = form.prepareSubmission()
        let prepared = try #require(submission)
        #expect(prepared.content == "Hi Ada")
        #expect(prepared.placeholderValues.contains(.init(key: "name", value: "Ada")))
    }

    @Test func lastValuesRequiresHistoryForTheSelectedElseBranch() throws {
        let s = snippet("{{#if formal}}{{name}}{{#else}}{{nickname}}{{/if}}")
        #expect(SnippetPreparation.lastValuesAvailability(for: s, history: history(["name": "Ada"]), now: Self.now)
            == .unavailable)
        #expect(throws: MissingPlaceholderHistoryError(placeholderKey: "nickname")) {
            try SnippetPreparation.prepareWithLastValues(s, history: history(["name": "Ada"]), now: Self.now)
        }
        let prepared = try SnippetPreparation.prepareWithLastValues(s, history: history(["nickname": "A"]), now: Self.now)
        #expect(prepared.content == "A")
    }

    @Test func defaultOnGuardStillRequiresHistory() {
        let s = snippet("{{#if +signature}}{{name}}{{/if}}")
        #expect(SnippetPreparation.lastValuesAvailability(for: s, history: [:], now: Self.now) == .unavailable)
        #expect(throws: MissingPlaceholderHistoryError(placeholderKey: "name")) {
            try SnippetPreparation.prepareWithLastValues(s, history: [:], now: Self.now)
        }
    }
}
