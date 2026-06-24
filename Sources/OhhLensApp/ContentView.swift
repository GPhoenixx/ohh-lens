import SwiftUI
import OhhLensCore

struct ContentView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $appStore.selectedSection)
        } detail: {
            Text("Ohh Lens")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
