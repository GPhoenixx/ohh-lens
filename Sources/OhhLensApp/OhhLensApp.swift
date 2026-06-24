import SwiftUI
import OhhLensCore

@main
struct OhhLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appStore = AppStore.preview

    var body: some Scene {
        WindowGroup("Ohh Lens") {
            ContentView()
                .environmentObject(appStore)
                .frame(minWidth: 980, minHeight: 640)
        }

        Settings {
            SetupView()
                .environmentObject(appStore)
                .frame(width: 680, height: 520)
        }
    }
}
