import Testing
@testable import tully

@MainActor
struct UpdateCheckerTests {
    @Test func comparesVersionsNumerically() {
        #expect(UpdateChecker.isNewer("v2.3.0", than: "2.2.0"))
        #expect(UpdateChecker.isNewer("v2.10.0", than: "2.9.1"))
        #expect(UpdateChecker.isNewer("v3", than: "2.9.9"))
        #expect(!UpdateChecker.isNewer("v2.2.0", than: "2.2.0"))
        #expect(!UpdateChecker.isNewer("v2.2", than: "2.2.0"))
        #expect(!UpdateChecker.isNewer("v2.1.9", than: "2.2.0"))
    }

    @Test func switchDefaultsOnAndPersists() {
        let defaults = makeDefaults()
        let checker = UpdateChecker(defaults: defaults)
        #expect(checker.isEnabled)
        checker.isEnabled = false
        #expect(!UpdateChecker(defaults: defaults).isEnabled)
    }
}
