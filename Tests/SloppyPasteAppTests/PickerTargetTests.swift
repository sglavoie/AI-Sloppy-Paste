import AppKit
import Testing
@testable import SloppyPasteApp

@Suite @MainActor struct PickerTargetTests {
    @Test func ownAppAndMissingFrontmostAppHaveNoPasteTarget() {
        let current = NSRunningApplication.current
        let ownPID = current.processIdentifier

        #expect(PickerPanelController.pasteTarget(frontmost: current, ownPID: ownPID) == nil)
        #expect(PickerPanelController.pasteTarget(frontmost: nil, ownPID: ownPID) == nil)
        #expect(PickerPanelController.pasteTarget(frontmost: current, ownPID: ownPID + 1)?.processIdentifier == ownPID)
    }
}
