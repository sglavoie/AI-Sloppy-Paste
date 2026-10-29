import Testing
@testable import SloppyPasteApp

@Suite @MainActor struct PasterTests {
    @Test func storedDelayStaysWithinSettingsRange() {
        #expect(Paster.sanitizedDelayMilliseconds(nil) == Paster.defaultDelayMilliseconds)
        #expect(Paster.sanitizedDelayMilliseconds(-10) == 0)
        #expect(Paster.sanitizedDelayMilliseconds(250) == 250)
        #expect(Paster.sanitizedDelayMilliseconds(Int.max) == Paster.maximumDelayMilliseconds)
    }
}
