import AppKit
import Carbon.HIToolbox
import Testing
@testable import SloppyPasteApp

@Suite @MainActor struct HotKeySettingsTests {
    private final class RejectingHotKeyCenter: HotKeyCenter {
        var rejected: Set<HotKey>
        private(set) var registered: HotKey?

        init(rejected: HotKey) { self.rejected = [rejected] }

        func register(_ hotKey: HotKey, handler: @escaping @MainActor () -> Void) throws {
            if rejected.contains(hotKey) { throw HotKeyRegistrationError(status: -1) }
            registered = hotKey
        }

        func unregister() { registered = nil }
    }

    @Test func launchFallbackPersistsTheShortcutThatActuallyRegistered() throws {
        let suite = "HotKeySettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let unavailable = HotKey(keyCode: 1, carbonModifiers: UInt32(cmdKey))
        defaults.set(try JSONEncoder().encode(unavailable), forKey: HotKeySettings.defaultsKey)
        let center = RejectingHotKeyCenter(rejected: unavailable)

        let settings = HotKeySettings(center: center, defaults: defaults, handler: {})
        settings.registerStored()

        #expect(settings.hotKey == .default)
        #expect(center.registered == .default)
        let saved = try #require(defaults.data(forKey: HotKeySettings.defaultsKey))
        #expect(try JSONDecoder().decode(HotKey.self, from: saved) == .default)
        let nextCenter = RejectingHotKeyCenter(rejected: unavailable)
        let nextLaunch = HotKeySettings(center: nextCenter, defaults: defaults, handler: {})
        #expect(nextLaunch.hotKey == .default)
        nextLaunch.registerStored()
        #expect(nextCenter.registered == .default)
    }

    @Test(arguments: [UInt32(UInt16.max) + 1, UInt32.max])
    func outOfRangeStoredKeyCodesHaveSafeLabels(keyCode: UInt32) throws {
        let json = Data("{\"keyCode\":\(keyCode),\"carbonModifiers\":\(cmdKey)}".utf8)
        let hotKey = try JSONDecoder().decode(HotKey.self, from: json)

        #expect(hotKey.keyName == "Key \(keyCode)")
        #expect(hotKey.displayString == "⌘Key \(keyCode)")
        #expect(hotKey.menuKeyEquivalent == nil)
    }

    @Test func failedChangeKeepsRegisteredShortcutActive() throws {
        let suite = "HotKeySettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let unavailable = HotKey(keyCode: 1, carbonModifiers: UInt32(cmdKey))
        let center = RejectingHotKeyCenter(rejected: unavailable)
        let settings = HotKeySettings(center: center, defaults: defaults, handler: {})
        settings.registerStored()

        #expect(!settings.update(unavailable))
        #expect(center.registered == .default)
        #expect(settings.hotKey == .default)
        #expect(settings.registrationError?.contains("previous shortcut is still active") == true)
    }

    @Test func cancelledRecordingFallsBackWhenPreviousShortcutWasClaimed() throws {
        let suite = "HotKeySettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let custom = HotKey(keyCode: 1, carbonModifiers: UInt32(cmdKey))
        let center = RejectingHotKeyCenter(rejected: .default)
        center.rejected = []
        let settings = HotKeySettings(center: center, defaults: defaults, handler: {})
        #expect(settings.update(custom))
        settings.suspend()
        center.rejected = [custom]

        settings.resume()

        #expect(center.registered == .default)
        #expect(settings.hotKey == .default)
        #expect(settings.registrationError?.contains("Using the default shortcut") == true)
        let saved = try #require(defaults.data(forKey: HotKeySettings.defaultsKey))
        #expect(try JSONDecoder().decode(HotKey.self, from: saved) == .default)
    }

    @Test func rejectedRecordingFallsBackWhenPreviousShortcutWasClaimed() throws {
        let suite = "HotKeySettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let custom = HotKey(keyCode: 1, carbonModifiers: UInt32(cmdKey))
        let rejected = HotKey(keyCode: 2, carbonModifiers: UInt32(cmdKey))
        let center = RejectingHotKeyCenter(rejected: rejected)
        let settings = HotKeySettings(center: center, defaults: defaults, handler: {})
        #expect(settings.update(custom))
        settings.suspend()
        center.rejected = [custom, rejected]

        #expect(!settings.update(rejected))

        #expect(center.registered == .default)
        #expect(settings.hotKey == .default)
        #expect(settings.registrationError?.contains("default shortcut is active") == true)
        let saved = try #require(defaults.data(forKey: HotKeySettings.defaultsKey))
        #expect(try JSONDecoder().decode(HotKey.self, from: saved) == .default)
    }

    @Test func cancelledRecordingReportsWhenNoShortcutCanBeRestored() throws {
        let suite = "HotKeySettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = RejectingHotKeyCenter(rejected: .default)
        center.rejected = []
        let settings = HotKeySettings(center: center, defaults: defaults, handler: {})
        settings.registerStored()
        settings.suspend()
        center.rejected = [.default]

        settings.resume()

        #expect(center.registered == nil)
        #expect(settings.registrationError?.contains("No global shortcut is active") == true)
    }
}
