import Testing
import SloppyCore
@testable import sloppyctl

@Suite struct StatsTests {
    @Test func tagCountsUseNormalizedTagIdentity() {
        let snippets = [
            Snippet(id: "1", title: "One", content: "One", tags: [" Work ", "WORK", ""], createdAt: 0, updatedAt: 0),
            Snippet(id: "2", title: "Two", content: "Two", tags: ["work/child"], createdAt: 0, updatedAt: 0),
            Snippet(id: "3", title: "Three", content: "Three", tags: ["", " \n "], createdAt: 0, updatedAt: 0),
            Snippet(id: "4", title: "Four", content: "Four", createdAt: 0, updatedAt: 0),
        ]
        let stats = Stats(StorageData(snippets: snippets), now: 0)
        #expect(stats.tagged == 2)
        #expect(stats.untagged == 2)
        #expect(stats.distinctTags == 2)
    }
}
