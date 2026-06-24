import Testing
@testable import OhhLensCore

@Test
func appStoreDefaultsToLiveSection() {
    let store = AppStore()
    #expect(store.selectedSection == .live)
}
