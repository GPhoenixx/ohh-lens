import SwiftUI

struct FilesView: View {
    var body: some View {
        ContentUnavailableView(
            "Import audio or video",
            systemImage: "waveform.badge.plus",
            description: Text("Drop a meeting recording, podcast clip, or screen capture here to transcribe it through your local backend.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
