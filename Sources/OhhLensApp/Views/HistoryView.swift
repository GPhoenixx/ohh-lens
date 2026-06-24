import SwiftUI

struct HistoryView: View {
    var body: some View {
        ContentUnavailableView(
            "No saved sessions yet",
            systemImage: "text.badge.clock",
            description: Text("Finished transcriptions will appear here so you can copy, export, or reopen them later.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
