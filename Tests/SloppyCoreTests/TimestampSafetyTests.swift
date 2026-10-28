import Foundation
import Testing
@testable import SloppyCore

@Suite struct TimestampSafetyTests {
    @Test func extremeImportedTimestampsCanBeSearchedAndDisplayed() throws {
        let json = #"{"snippets":[{"id":"s","title":"Old","content":"text","createdAt":-9223372036854775808,"lastUsedAt":-9223372036854775808,"useCount":1}]}"#
        let data = try ImportExport.replace(with: ImportExport.decodeImport(Data(json.utf8)))
        let snippet = try #require(data.snippets.first)
        let analytics = Staleness.analyze(snippet, now: .max)
        #expect(analytics.daysUnused == 213_503_982_334)
        #expect(analytics.isStale)
        #expect(Formatting.relativeTime(.min, now: .max) == "584942417y ago")
        #expect(Formatting.relativeTime(.max, now: .min) == "just now")
        let list = SnippetListPipeline.build(data.snippets, query: "", now: .max)
        #expect(list.rows.map(\.id) == ["s"])
    }

    @Test func extremeHistoryTimestampsCanBeRanked() {
        let values: [PlaceholderHistoryValue] = [
            .init(value: "old", useCount: 1, lastUsed: .min, createdAt: .min),
            .init(value: "recent", useCount: 1, lastUsed: .max, createdAt: .max),
        ]
        #expect(PlaceholderHistoryRanking.rankedValues(values, now: .max) == ["recent", "old"])
        #expect(PlaceholderHistoryRanking.rankedValues(values, now: .min) == ["old", "recent"])
    }

    @Test func ageBoundariesKeepMillisecondPrecision() {
        let now = Int64.max
        let day: Int64 = 86_400_000
        for elapsed in [day - 1, day, day + 1] {
            let snippet = Snippet(id: "s", title: "T", content: "x", createdAt: now,
                updatedAt: now, lastUsedAt: now - elapsed, useCount: 1)
            #expect(Staleness.analyze(snippet, now: now).daysUnused == Int(elapsed / day))
        }
        #expect(Formatting.relativeTime(now - 59_999, now: now) == "just now")
        #expect(Formatting.relativeTime(now - 60_000, now: now) == "1m ago")
    }
}
