import SwiftUI
import OhhLensCore

struct SidebarView: View {
    @Binding var selection: AppSection

    var body: some View {
        List(AppSection.allCases, selection: $selection) { section in
            Text(section.rawValue)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240)
    }
}
