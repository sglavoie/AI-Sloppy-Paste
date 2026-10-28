import Testing
@testable import SloppyCore

@Suite struct UntaggedFilterTests {
    @Test func literalUntaggedTagDoesNotSelectUntaggedSnippets() {
        let snippets = [
            Snippet(id: "tagged", title: "Tagged", content: "Text", tags: ["__untagged__"], createdAt: 0, updatedAt: 0),
            Snippet(id: "child", title: "Child", content: "Text", tags: ["__untagged__/child"], createdAt: 0, updatedAt: 0),
            Snippet(id: "empty", title: "Empty", content: "Text", createdAt: 0, updatedAt: 0),
        ]
        #expect(Validation.validateTag("__untagged__").isValid)
        #expect(TagHierarchy.filterSnippets(snippets, byTag: "__untagged__").map(\.id) == ["tagged", "child"])
        #expect(TagFilterChooser.entries(snippets: snippets, showArchived: false, selectedTag: nil, searchText: "") == [
            .allTags, .untagged(count: 1), .tag("__untagged__", count: 2), .tag("__untagged__/child", count: 1),
        ])
        #expect(SnippetListPipeline.filter(snippets, query: ParsedQuery(),
            options: SnippetFilterOptions(selectedTag: .tag("__untagged__")), now: 0).map(\.id) == ["tagged", "child"])
    }

    @Test func normalizedTagsPreserveOrderAndStoredSpelling() {
        let tags = [" Work ", "", "WORK", "Personal", "\n", "work/child"]
        let snippet = Snippet(id: "1", title: "Title", content: "Text", tags: tags, createdAt: 0, updatedAt: 0)
        #expect(snippet.normalizedTags == ["work", "personal", "work/child"])
        #expect(snippet.tags == tags)
    }

    @Test func blankExternalTagsAreUntaggedAcrossFiltersAndCounts() {
        let snippets = [
            Snippet(id: "blank", title: "Blank", content: "Text", tags: ["", " \n "], createdAt: 0, updatedAt: 0),
            Snippet(id: "empty", title: "Empty", content: "Text", createdAt: 0, updatedAt: 0),
            Snippet(id: "tagged", title: "Tagged", content: "Text", tags: ["", " Work "], createdAt: 0, updatedAt: 0),
        ]
        #expect(TagFilter.untagged.apply(to: snippets).map(\.id) == ["blank", "empty"])
        #expect(SearchFilter.apply(snippets, query: QueryParser.parse("is:untagged")).map(\.id) == ["blank", "empty"])
        #expect(SearchFilter.apply(snippets, query: QueryParser.parse("not:untagged")).map(\.id) == ["tagged"])
        #expect(TagFilterChooser.entries(snippets: snippets, showArchived: false, selectedTag: nil, searchText: "") == [
            .allTags, .untagged(count: 2), .tag("work", count: 1),
        ])
    }
}
