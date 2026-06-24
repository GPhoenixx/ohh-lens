import SwiftUI
import OhhLensCore

struct SidebarView: View {
    @Binding var selection: AppSection

    var body: some View {
        List(AppSection.allCases, selection: $selection) { section in
            Label(section.title, systemImage: symbol(for: section))
                .tag(section)
        }
        .listStyle(.sidebar)
        .navigationTitle("Ohh Lens")
        .navigationSplitViewColumnWidth(min: 220, ideal: 240)
    }

    private func symbol(for section: AppSection) -> String {
        switch section {
        case .live:
            return "captions.bubble"
        case .history:
            return "clock.arrow.circlepath"
        case .files:
            return "waveform.path.badge.plus"
        case .setup:
            return "gearshape"
        }
    }
}
