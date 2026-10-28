import Testing
import SloppyCore
@testable import SloppyPasteApp

@Suite @MainActor struct TagFilterChooserModelTests {
    @Test func literalTagAndUntaggedCategoryRemainSeparateSelections() {
        let snippets = [
            Snippet(id: "tagged", title: "Tagged", content: "Text", tags: ["__untagged__"], createdAt: 0, updatedAt: 0),
            Snippet(id: "empty", title: "Empty", content: "Text", createdAt: 0, updatedAt: 0),
        ]
        var applied: TagFilter?
        let model = TagFilterChooserModel(snippets: snippets, showArchived: false,
            currentTag: .tag("__untagged__")) { applied = $0 }
        #expect(model.selection == .tag("__untagged__", count: 1))
        model.activate()
        #expect(applied?.apply(to: snippets).map(\.id) == ["tagged"])

        model.select(TagFilterChooser.Entry.untagged(count: 1).id)
        model.activate()
        #expect(applied?.apply(to: snippets).map(\.id) == ["empty"])

        model.select(TagFilterChooser.Entry.allTags.id)
        model.activate()
        #expect(applied == nil)
    }
}
