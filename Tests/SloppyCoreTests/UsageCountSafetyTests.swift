import Foundation
import Testing
@testable import SloppyCore

@Suite struct UsageCountSafetyTests {
    @Test func recordingUseAtMaximumCountStillUpdatesTimestampsAndHistory() throws {
        let json = #"{"snippets":[{"id":"a","title":"A","content":"{{name}}","useCount":\#(Int.max)}],"placeholderHistory":{"name":[{"value":"Ada","useCount":\#(Int.max),"lastUsed":1,"createdAt":1}]}}"#
        let payload = try ImportExport.decodeImport(Data(json.utf8))
        var repository = SnippetRepository(data: ImportExport.replace(with: payload))

        try repository.recordUse(id: "a", placeholderValues: [.init(key: "name", value: "Ada")], now: 42)

        #expect(repository.snippets[0].useCount == Int.max)
        #expect(repository.snippets[0].lastUsedAt == 42)
        #expect(repository.snippets[0].updatedAt == 42)
        #expect(repository.data.placeholderHistory["name"] == [
            PlaceholderHistoryValue(value: "Ada", useCount: Int.max, lastUsed: 42, createdAt: 1)
        ])

        let updated = repository.data.updatePlaceholderValueUsage(key: "name", value: "Ada", now: 43)
        #expect(updated)
        #expect(repository.data.placeholderHistory["name"]?.first?.useCount == Int.max)
        #expect(repository.data.placeholderHistory["name"]?.first?.lastUsed == 43)
    }

    @Test(arguments: [(Int.max, 1, Int.max), (Int.min, -1, Int.min)])
    func usageStatisticsSaturateAtIntegerBounds(first: Int, second: Int, expected: Int) {
        let snippets = [first, second].enumerated().map { index, count in
            Snippet(id: "s\(index)", title: "T", content: "C", tags: ["work"],
                    createdAt: 0, updatedAt: 0, useCount: count)
        }
        #expect(TagStatistics.compute(snippets: snippets, tags: ["work"]).first?.totalUsageCount == expected)

        let values = [first, second].enumerated().map { index, count in
            PlaceholderHistoryValue(value: "v\(index)", useCount: count, lastUsed: 0, createdAt: 0)
        }
        #expect(PlaceholderKeyStats(key: "name", values: values).totalUseCount == expected)
    }
}
