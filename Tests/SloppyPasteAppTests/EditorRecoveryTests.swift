import Foundation
import Testing
import SloppyCore
@testable import SloppyPasteApp

@Suite @MainActor struct EditorRecoveryTests {
    @Test func recoveredDraftCannotOverwriteExternalEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let draftURL = directory.appending(path: "drafts.json")
        let snippet = Snippet(id: "a", title: "Original", content: "Saved", createdAt: 1, updatedAt: 1)
        try file.save(StorageData(snippets: [snippet]))
        let first = Navigator(draftURL: draftURL)
        let session = first.startEditor(.edit(snippetID: snippet.id), draft: SnippetDraft(snippet: snippet))
        session.draft.content = "Unfinished local edit"

        let restarted = Navigator(draftURL: draftURL)
        let recovered = try #require(restarted.pendingEditor)
        let store = SnippetStore(file: file, now: { 10 })
        store.load()
        var external = snippet
        external.content = "External edit made while draft was closed"
        // Keep updatedAt unchanged: compare the edited fields, not timestamps.
        try file.save(StorageData(snippets: [external]))
        let savedBytes = try Data(contentsOf: file.url)

        #expect(throws: SnippetDraftError.conflict) {
            try store.mutate { repository, now in
                try recovered.draft.update(id: snippet.id, in: &repository, now: now, original: recovered.original)
            }
        }
        #expect(try Data(contentsOf: file.url) == savedBytes)
        #expect(restarted.pendingEditor === recovered)
        #expect(Navigator(draftURL: draftURL).pendingEditor?.draft.content == "Unfinished local edit")
    }

    @Test func draftsSurviveRestartAndDisappearAfterSaveOrDiscard() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "drafts.json")
        let first = Navigator(draftURL: url)
        let new = first.startEditor(.new, draft: SnippetDraft())
        new.draft.title = "Unfinished"
        new.draft.content = "  Preserve whitespace\n\n"
        new.draft.tagsText = "work,  unfinished,"
        let edit = first.startEditor(.edit(snippetID: "existing"), draft: SnippetDraft(title: "Original", content: "saved"))
        edit.draft.content = "Unsaved edit"
        _ = first.startEditor(.fromClipboard, draft: SnippetDraft(title: "Clipboard", content: "copied"))

        let restarted = Navigator(draftURL: url)
        #expect(restarted.draftRecoveryError == nil)
        #expect(restarted.editorSessions.count == 3)
        #expect(restarted.pendingEditor?.mode == .fromClipboard)
        #expect(restarted.editorSession(for: .new)?.draft.content == "  Preserve whitespace\n\n")
        #expect(restarted.editorSession(for: .new)?.draft.tagsText == "work,  unfinished,")
        #expect(restarted.editorSession(for: .edit(snippetID: "existing"))?.original.content == "saved")
        for mode in [EditorMode.new, .fromClipboard, .edit(snippetID: "existing")] { restarted.finishEditor(mode) }
        #expect(Navigator(draftURL: url).editorSessions.isEmpty)
    }

    @Test func unreadableDraftsArePreservedAndNewEditsStayInMemory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "drafts.json")
        let invalid = Data("not JSON".utf8)
        try invalid.write(to: url)
        let navigator = Navigator(draftURL: url)
        let session = navigator.startEditor(.new, draft: SnippetDraft())
        session.draft.content = "Do not overwrite recovery data"
        #expect(navigator.draftRecoveryError != nil)
        #expect(navigator.pendingEditor === session)
        #expect(try Data(contentsOf: url) == invalid)
    }

    @Test(arguments: [false, true])
    func secondInstanceCannotOverwriteChangedDrafts(firstWritesBeforeSecond: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "drafts.json")
        let first = Navigator(draftURL: url)
        let second: Navigator
        if firstWritesBeforeSecond {
            let session = first.startEditor(.new, draft: SnippetDraft())
            session.draft.title = "First version"
            second = Navigator(draftURL: url)
            session.draft.title = "Latest version"
        } else {
            second = Navigator(draftURL: url)
            let session = first.startEditor(.new, draft: SnippetDraft())
            session.draft.title = "Latest version"
        }
        let savedBytes = try Data(contentsOf: url)
        let secondSession = second.startEditor(.edit(snippetID: "other"), draft: SnippetDraft())
        secondSession.draft.content = "Unsaved in second instance"

        #expect(second.draftRecoveryError?.contains("another copy") == true)
        #expect(second.pendingEditor === secondSession)
        #expect(try Data(contentsOf: url) == savedBytes)
        #expect(Navigator(draftURL: url).editorSession(for: .new)?.draft.title == "Latest version")
    }

    @Test func returningToOriginalDraftRemovesItFromRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "drafts.json")
        let navigator = Navigator(draftURL: url)
        let session = navigator.startEditor(.new, draft: SnippetDraft())
        session.draft.title = "Changed"
        session.draft.title = ""
        #expect(Navigator(draftURL: url).pendingEditor == nil)
    }

    @Test func reopeningPickerKeepsDirtyEditorAndStartsAtRoot() {
        let navigator = Navigator()
        navigator.push(.editor(.new))
        let session = navigator.startEditor(.new, draft: SnippetDraft())
        session.draft.title = "Unfinished"
        session.draft.content = "  Keep this\n"

        navigator.reset()

        #expect(navigator.current == .root)
        #expect(navigator.session == 1)
        #expect(navigator.pendingEditor === session)
        #expect(navigator.startEditor(.new, draft: SnippetDraft()) === session)
        #expect(session.draft.content == "  Keep this\n")
        navigator.push(.editor(session.mode))
        #expect(navigator.current == .editor(.new))
    }

    @Test func clipboardDraftSurvivesBeforeAnyEdits() {
        let navigator = Navigator()
        let session = navigator.startEditor(.fromClipboard, draft: SnippetDraft(title: "Clipboard", content: "Text"))
        navigator.reset()
        #expect(navigator.pendingEditor === session)
    }

    @Test func cleanEditorsAreReleasedAndSavedOrDiscardedDraftsDoNotReturn() {
        let navigator = Navigator()
        let clean = navigator.startEditor(.edit(snippetID: "saved"), draft: SnippetDraft(title: "Saved", content: "text"))
        let dirty = navigator.startEditor(.new, draft: SnippetDraft())
        dirty.draft.title = "Draft"
        navigator.reset()
        #expect(navigator.editorSession(for: clean.mode) == nil)
        navigator.finishEditor(dirty.mode)
        navigator.reset()
        #expect(navigator.pendingEditor == nil)
        #expect(navigator.editorSessions.isEmpty)
    }

    @Test func differentEditorsDoNotOverwriteEachOther() {
        let navigator = Navigator()
        let first = navigator.startEditor(.new, draft: SnippetDraft())
        first.draft.title = "First"
        let second = navigator.startEditor(.edit(snippetID: "other"), draft: SnippetDraft(title: "Other", content: "text"))
        second.draft.content = "Changed"
        navigator.reset()
        #expect(navigator.pendingEditor === second)
        navigator.finishEditor(second.mode)
        #expect(navigator.pendingEditor === first)
    }
}
