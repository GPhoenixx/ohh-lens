import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        @Bindable var appStore = appStore

        NavigationSplitView {
            SidebarView(selection: $appStore.selectedSection)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .navigationSplitViewColumnWidth(
                    min: AppTheme.Layout.sidebarWidth,
                    ideal: AppTheme.Layout.sidebarWidth,
                    max: 280
                )
        } detail: {
            detailContent(for: appStore.selectedSection)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func detailContent(for section: AppSection) -> some View {
        ZStack(alignment: .topLeading) {
            currentSectionView(for: section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func currentSectionView(for section: AppSection) -> some View {
        switch section {
        case .liveSubtitles:
            LiveView()
        case .conversations:
            ConversationsView()
        case .fileTranscriber:
            FilesView()
        case .savedTranscripts:
            HistoryView()
        case .appSettings:
            SetupView()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
        .frame(width: 1200, height: 760)
}
