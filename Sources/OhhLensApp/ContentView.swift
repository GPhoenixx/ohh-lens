import SwiftUI
import OhhLensCore

struct ContentView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        @Bindable var appStore = appStore

        NavigationSplitView {
            SidebarView(selection: $appStore.selectedSection)
        } detail: {
            switch appStore.selectedSection {
            case .live:
                LiveView()
            case .history:
                HistoryView()
            case .files:
                FilesView()
            case .setup:
                SetupView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
