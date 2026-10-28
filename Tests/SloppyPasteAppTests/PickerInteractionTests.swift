import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
import SloppyCore
@testable import SloppyPasteApp

@Suite(.serialized) @MainActor struct PickerInteractionTests {
    @Test(arguments: [1.0, 1.5])
    func selectionHighlightFollowsArrowsThroughFilteredSections(zoom: Double) async throws {
        let picker = try Harness(query: "", zoom: zoom)
        defer { picker.close() }
        await picker.settle()
        try picker.action("focusSearch")
        await picker.settle()
        try picker.typeQuery("plan")
        await picker.settle()
        var previous = try picker.highlightCenter()
        for _ in 0..<3 {
            try picker.press(kVK_DownArrow)
            await picker.settle()
            let current = try picker.highlightCenter()
            #expect(current > previous, "The visible highlight must move down with each selected snippet")
            previous = current
        }
    }

    @Test func escapePreservesSearchThenClosesAndEmptySearchClosesImmediately() async throws {
        let picker = try Harness(query: "plan")
        defer { picker.close() }
        await picker.settle()
        try picker.action("focusSearch")
        await picker.settle()
        try picker.press(kVK_DownArrow)
        await picker.settle()
        let selected = try picker.highlightCenter()
        try picker.press(kVK_Escape)
        await picker.settle()
        #expect(picker.searchField?.stringValue == "plan")
        #expect(picker.closeCount == 0)
        #expect(picker.router.bindings(for: .root).first { $0.id == "vimDown" }?.chord != nil)
        #expect(try picker.highlightCenter() == selected)
        try picker.press(kVK_ANSI_J, characters: "j")
        await picker.settle()
        #expect(try picker.highlightCenter() > selected)
        try picker.press(kVK_Escape)
        #expect(picker.closeCount == 1)

        let empty = try Harness(query: "")
        defer { empty.close() }
        await empty.settle()
        try empty.action("focusSearch")
        await empty.settle()
        try empty.press(kVK_Escape)
        #expect(empty.closeCount == 1)
    }

    @Test func failedDeleteKeepsTheCurrentSelection() async throws {
        let picker = try Harness(query: "")
        defer { picker.close() }
        await picker.settle()
        try picker.press(kVK_DownArrow)
        await picker.settle()
        let selected = try picker.highlightCenter()

        try picker.action("delete")
        await picker.settle()
        try Data("{unfinished".utf8).write(to: picker.file.url)
        try picker.action("confirmDelete")
        await picker.settle()

        #expect(try picker.highlightCenter() == selected)
        #expect(picker.store.lastError != nil)
    }

    @MainActor private final class Harness {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let file: StorageFile
        let store: SnippetStore
        let defaults: UserDefaults
        let suite = UUID().uuidString
        let window: NSWindow
        let router: KeyRouter
        let zoom: Double
        final class CloseCounter { var value = 0 }
        let counter = CloseCounter()
        var closeCount: Int { counter.value }

        init(query: String, zoom: Double = 1) throws {
            _ = NSApplication.shared
            self.zoom = zoom
            defaults = UserDefaults(suiteName: suite)!
            defaults.set(true, forKey: "picker.showingDetail")
            defaults.set(true, forKey: "picker.showRecentSection")
            let now: Int64 = 1_800_000_000_000
            let snippets = (0..<5).map { (index: Int) -> Snippet in
                let lastUsed: Int64? = index < 3 ? now - Int64(index) : nil
                return Snippet(id: "\(index)", title: index < 4 ? "Plan \(index)" : "Other",
                        content: "Content \(index)", createdAt: now, updatedAt: now - Int64(index),
                        lastUsedAt: lastUsed,
                        isPinned: index == 4)
            }
            file = StorageFile(url: directory.appending(path: "data.json"))
            try file.save(StorageData(snippets: snippets))
            store = SnippetStore(file: file, now: { now })
            store.load()
            let navigator = Navigator()
            let counter = counter
            router = KeyRouter(navigator: navigator) { counter.value += 1 }
            let zoomState = PickerZoom()
            zoomState.level = zoom
            let root = PickerRootView(query: query)
                .environment(store)
                .environment(navigator)
                .environment(AccessibilityPermission())
                .environment(ToastCenter())
                .pickerZoom()
                .environment(zoomState)
                .environment(\.keyRouter, router)
                .defaultAppStorage(defaults)
                .environment(\.colorScheme, .light)
                .accentColor(.blue)
                .background(Color.white)
            window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000 * zoom, height: 600 * zoom),
                              styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: root)
            window.orderFront(nil)
        }

        func close() {
            window.close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        func settle() async {
            try? await Task.sleep(for: .milliseconds(100))
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }

        func action(_ id: String) throws {
            let binding = try #require(router.bindings(for: .root).first { $0.id == id })
            binding.perform()
        }

        func typeQuery(_ query: String) throws {
            let field = try #require(searchField)
            field.stringValue = query
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        }

        func press(_ code: Int, characters: String = "") throws {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code)))
            #expect(router.handle(event))
        }

        var searchField: NSTextField? {
            func find(_ view: NSView) -> NSTextField? {
                if let field = view as? NSTextField { return field }
                return view.subviews.lazy.compactMap(find).first
            }
            return window.contentView.flatMap(find)
        }

        /// Sample the left padding of the list, away from text and icons.
        /// Exactly one blue band must be painted, and its center follows selection.
        func highlightCenter() throws -> Double {
            let view = try #require(window.contentView)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let scale = Double(bitmap.pixelsWide) / view.bounds.width * zoom
            let colored = (Int(60 * scale)..<Int(350 * scale)).filter { y in
                guard let color = bitmap.colorAt(x: Int(15 * scale), y: y)?.usingColorSpace(.deviceRGB) else {
                    return false
                }
                return color.blueComponent > color.redComponent + 0.08
                    && color.blueComponent > color.greenComponent + 0.04
            }
            let first = try #require(colored.first, "The selected row must have a visible highlight")
            let last = try #require(colored.last)
            #expect(colored.count == last - first + 1, "Only one row should be highlighted")
            return Double(first + last) / 2 / scale
        }
    }
}
