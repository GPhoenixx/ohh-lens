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
    }
}

private struct LiveView: View {
    var body: some View {
        Text("Live")
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryView: View {
    var body: some View {
        Text("History")
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FilesView: View {
    var body: some View {
        Text("Files")
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
