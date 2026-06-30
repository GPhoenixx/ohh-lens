import SwiftUI

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

#Preview {
    ContentView()
        .environment(AppStore())
        .frame(width: 1200, height: 760)
}
