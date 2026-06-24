import SwiftUI

struct FilesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Files")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Import audio or video files for local transcription and translation.")
                .foregroundStyle(.secondary)

            Text("Supported workflow")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Text("1. Choose or drop a file into this workspace.")
                Text("2. Route it through the local FunASR backend.")
                Text("3. Save the resulting transcript to History.")
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
