import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @Environment(AppStore.self) private var appStore

    @State private var isDropTargeted = false
    @State private var selectedTranslation = "none"
    @State private var didCopyTranscript = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                switch appStore.fileTranscription.phase {
                case .idle:
                    idleDropZone
                case .processing:
                    processingCard
                case .completed:
                    resultCard
                }
            }
            .padding(AppTheme.Layout.contentPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.clear)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Offline File Transcriber")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ColorToken.textPrimary)

            Text("Transcribe custom audio or video files directly on your Mac.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var idleDropZone: some View {
        GlassCard {
            VStack(spacing: 18) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.accent)

                VStack(spacing: 6) {
                    Text("Drag and drop audio or video files here")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.textPrimary)

                    Text("Supports MP3, WAV, M4A, MP4, MOV, and MKV.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.textMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }

                HStack(spacing: 12) {
                    Button("Use Preview File") {
                        appStore.beginFileTranscription(for: previewFileURL)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
                            .fill(AppTheme.ColorToken.accent)
                    )

                    Text("demo-interview.mp4")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.ColorToken.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
                                .fill(AppTheme.ColorToken.controlFill)
                        )
                }
            }
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous)
                    .fill(isDropTargeted ? AppTheme.ColorToken.accent.opacity(0.08) : .clear)
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? AppTheme.ColorToken.accent : AppTheme.ColorToken.border,
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 8])
                )
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop(providers:))
    }

    private var processingCard: some View {
        let steps = appStore.fileTranscriptionPreviewSteps()

        return GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Processing File")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.textPrimary)

                        Text(appStore.fileTranscription.selectedFileURL?.lastPathComponent ?? "Imported file")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.ColorToken.textMuted)
                    }

                    Spacer()

                    Text(progressLabel(appStore.fileTranscription.progress))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                }

                ProgressView(value: appStore.fileTranscription.progress, total: 1)
                    .tint(AppTheme.ColorToken.accent)
                    .scaleEffect(x: 1, y: 1.4, anchor: .center)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        fileStepRow(
                            title: step.currentStep,
                            isComplete: appStore.fileTranscription.progress >= step.fractionCompleted,
                            isCurrent: appStore.fileTranscription.currentStep == step.currentStep
                        )
                    }
                }

                HStack(spacing: 12) {
                    Button("Generate Preview Result") {
                        if let selectedFileURL = appStore.fileTranscription.selectedFileURL {
                            appStore.loadDemoFileTranscript(for: selectedFileURL)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
                            .fill(AppTheme.ColorToken.accent)
                    )

                    Button("Reset") {
                        appStore.resetFileTranscription()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
                            .fill(AppTheme.ColorToken.controlFill)
                    )
                }
            }
        }
    }

    private var resultCard: some View {
        let transcriptText = appStore.fileTranscription.completedLines.joined(separator: "\n\n")

        return GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Transcription Completed")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.textPrimary)

                        Text(appStore.fileTranscription.selectedFileURL?.lastPathComponent ?? "Imported file")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.ColorToken.textMuted)
                    }

                    Spacer()

                    Text("100% complete")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                }

                HStack(spacing: 12) {
                    translationPicker

                    Spacer(minLength: 12)

                    Button(didCopyTranscript ? "Copied" : "Copy Text") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(transcriptText, forType: .string)
                        didCopyTranscript = true
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
                            .fill(AppTheme.ColorToken.controlFill)
                    )

                    Button("Download SRT") {
                        exportTranscript(transcriptText)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
                            .fill(AppTheme.ColorToken.accent)
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(appStore.fileTranscription.completedLines.enumerated()), id: \.offset) { index, line in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Segment \(index + 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.ColorToken.textMuted)
                                .textCase(.uppercase)
                                .tracking(0.6)

                            Text(line)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous)
                                .fill(Color.white.opacity(0.46))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous)
                                .strokeBorder(AppTheme.ColorToken.border, lineWidth: 1)
                        }
                    }
                }

                Button("Transcribe Another File") {
                    didCopyTranscript = false
                    selectedTranslation = "none"
                    appStore.resetFileTranscription()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
                        .fill(AppTheme.ColorToken.controlFill)
                )
            }
        }
    }

    private var translationPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Translate")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.textMuted)
                .textCase(.uppercase)
                .tracking(0.6)

            Menu {
                Button("No Translation") { selectedTranslation = "none" }
                Button("Vietnamese") { selectedTranslation = "vi" }
                Button("Spanish") { selectedTranslation = "es" }
                Button("Japanese") { selectedTranslation = "ja" }
            } label: {
                selectionFieldLabel(text: translationLabel, minWidth: 180)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
        }
    }

    private func fileStepRow(title: String, isComplete: Bool, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isComplete ? AppTheme.ColorToken.accent : Color.white.opacity(0.72))
                    .frame(width: 24, height: 24)

                Image(systemName: isComplete ? "checkmark" : "circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isComplete ? .white : AppTheme.ColorToken.borderStrong)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)

                Text(isCurrent ? "In progress" : (isComplete ? "Ready" : "Pending"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isCurrent ? AppTheme.ColorToken.accent : AppTheme.ColorToken.textMuted)
            }

            Spacer()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard
                let data = item as? Data,
                let url = URL(dataRepresentation: data, relativeTo: nil)
            else {
                return
            }

            Task { @MainActor in
                didCopyTranscript = false
                selectedTranslation = "none"
                appStore.beginFileTranscription(for: url)
            }
        }

        return true
    }

    private func exportTranscript(_ transcriptText: String) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = (appStore.fileTranscription.selectedFileURL?.deletingPathExtension().lastPathComponent ?? "transcript") + ".srt"
        savePanel.allowedContentTypes = [.plainText]

        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            return
        }

        try? transcriptText.write(to: destinationURL, atomically: true, encoding: .utf8)
    }

    private func progressLabel(_ progress: Double) -> String {
        "\(Int((progress * 100).rounded()))%"
    }

    private var previewFileURL: URL {
        URL(fileURLWithPath: "/tmp/demo-interview.mp4")
    }

    private var translationLabel: String {
        switch selectedTranslation {
        case "vi":
            "Vietnamese"
        case "es":
            "Spanish"
        case "ja":
            "Japanese"
        default:
            "No Translation"
        }
    }
}
