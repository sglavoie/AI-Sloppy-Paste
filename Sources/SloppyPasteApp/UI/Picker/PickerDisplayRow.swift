import SloppyCore

/// A single lazy-list element. Headers and selectable rows share one stable
/// identity space so filtering cannot leave cached, variable-length sections
/// behind. Selection is part of each element's data, not a captured value in
/// nested ForEach closures.
struct PickerDisplayRow: Identifiable, Equatable {
    enum Content: Equatable {
        case header(String, String?)
        case suggestion(SearchSuggestion)
        case snippet(Snippet)
    }

    var id: String
    var content: Content
    var isSelected = false

    static func rows(_ state: PickerListState, selectedID: String?) -> [Self] {
        var rows: [Self] = []
        if !state.suggestions.isEmpty {
            rows.append(Self(id: "header:suggestions", content: .header("Search Suggestions", nil)))
            for suggestion in state.suggestions {
                let id = PickerItem.suggestion(suggestion).id
                rows.append(Self(id: id, content: .suggestion(suggestion), isSelected: id == selectedID))
            }
        }
        for section in state.sections {
            if let title = section.title {
                rows.append(Self(id: "header:\(section.kind)", content: .header(title, section.subtitle)))
            }
            for snippet in section.snippets {
                rows.append(Self(id: snippet.id, content: .snippet(snippet), isSelected: snippet.id == selectedID))
            }
        }
        return rows
    }
}
