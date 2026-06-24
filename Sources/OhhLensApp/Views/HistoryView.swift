import SwiftUI
import OhhLensCore

struct HistoryView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        Group {
            if appStore.history.isEmpty {
                ContentUnavailableView(
                    "No saved sessions yet",
                    systemImage: "text.badge.clock",
                    description: Text("Finished transcriptions will appear here so you can copy, export, or reopen them later.")
                )
            } else {
                List(appStore.history) { session in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(sourceLabel(for: session.source))
                                .font(.headline)
                            Spacer()
                            Text(session.createdAt, style: .date)
                                .foregroundStyle(.secondary)
                        }

                        Text(languageLabel(for: session.languages))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(sessionPreview(for: session))
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("History")
    }

    private func sourceLabel(for source: AudioSource) -> String {
        switch source {
        case .microphone:
            "Microphone"
        case .systemAudio:
            "System Audio"
        case .appAudio:
            "App Audio"
        case .importedFile:
            "Imported File"
        }
    }

    private func languageLabel(for languages: LanguagePair) -> String {
        "\(languages.source.uppercased()) to \(languages.target.uppercased())"
    }

    private func sessionPreview(for session: SessionRecord) -> String {
        let previewText = session.segments.last?.translatedText ?? session.segments.last?.originalText
        return previewText ?? "No transcript segments saved"
    }
}
