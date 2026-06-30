import SwiftUI

@main
struct OhhLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appStore = AppStore()

    var body: some Scene {
        WindowGroup("Ohh Lens") {
            ContentView()
                .environment(appStore)
                .frame(minWidth: 980, minHeight: 640)
        }

        Settings {
            SetupView()
                .environment(appStore)
                .frame(width: 680, height: 520)
        }
    }
}
