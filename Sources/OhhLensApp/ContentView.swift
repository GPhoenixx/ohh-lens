import SwiftUI
import OhhLensCore

struct ContentView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        @Bindable var appStore = appStore

        NavigationSplitView {
            SidebarView(selection: $appStore.selectedSection)
        } detail: {
            Text("Ohh Lens")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
