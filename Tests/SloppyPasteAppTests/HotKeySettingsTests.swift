import AppKit
import Carbon.HIToolbox
import Testing
@testable import SloppyPasteApp

@Suite @MainActor struct HotKeySettingsTests {
    @Test(arguments: [UInt32(UInt16.max) + 1, UInt32.max])
    func outOfRangeStoredKeyCodesHaveSafeLabels(keyCode: UInt32) throws {
        let json = Data("{\"keyCode\":\(keyCode),\"carbonModifiers\":\(cmdKey)}".utf8)
        let hotKey = try JSONDecoder().decode(HotKey.self, from: json)

        #expect(hotKey.keyName == "Key \(keyCode)")
        #expect(hotKey.displayString == "⌘Key \(keyCode)")
        #expect(hotKey.menuKeyEquivalent == nil)
    }
}
