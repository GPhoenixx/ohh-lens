import SwiftUI

enum LiveCaptionAutoScrollTrigger {
    static func shouldScroll(from previousLines: [String], to nextLines: [String]) -> Bool {
        guard nextLines.isEmpty == false else {
            return false
        }

        if previousLines.count != nextLines.count {
            return true
        }

        return previousLines.last != nextLines.last
    }
}

@MainActor
struct TranscriptFooterBindings {
    let sourceLanguage: Binding<String>
    let targetLanguage: Binding<String>
    let toggleListening: @MainActor () -> Void
}

@MainActor
func makeTranscriptFooterBindings(for appStore: AppStore) -> TranscriptFooterBindings {
    TranscriptFooterBindings(
        sourceLanguage: Binding(
            get: { appStore.languagePair.source },
            set: { newValue in
                let previousSource = appStore.languagePair.source
                appStore.languagePair.source = newValue

                if appStore.languagePair.target == previousSource {
                    appStore.languagePair.target = newValue
                }
            }
        ),
        targetLanguage: Binding(
            get: { appStore.languagePair.target },
            set: { appStore.languagePair.target = $0 }
        ),
        toggleListening: {
            if appStore.isListening {
                appStore.stopListening()
            } else {
                appStore.startListening()
            }
        }
    )
}

struct TranscriptScreenHeader: View {
    let title: String
    let effectiveCaptureMode: EffectiveCaptureMode
    let isListening: Bool
    let isPiPVisible: Bool
    let availableLoopbackDevices: [AudioInputDevice]
    @Binding var selectedLoopbackDeviceID: String?
    let onTogglePiP: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppTheme.ColorToken.textPrimary)

            headerMiddleControl

            Spacer(minLength: 16)

            Button {
                onTogglePiP()
            } label: {
                Label(
                    isPiPVisible ? "Hide PiP" : "Open PiP",
                    systemImage: isPiPVisible ? "pip.exit" : "pip.enter"
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
                        .fill(AppTheme.ColorToken.controlFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
                        .strokeBorder(AppTheme.ColorToken.border, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var headerMiddleControl: some View {
        switch effectiveCaptureMode {
        case .routedSystemAudio, .appAudio:
            CompactSelectionField(
                title: "Loopback Device",
                selection: Binding(
                    get: { selectedLoopbackDeviceID ?? "" },
                    set: { selectedLoopbackDeviceID = $0 }
                ),
                options: availableLoopbackDevices.map(\.id),
                label: loopbackName(for:)
            )
        case .systemAudioFallbackMicrophone:
            MissingLoopbackPill(text: isListening ? "Live Audio" : "Live Audio Ready")
        case .appAudioRequiresLoopback:
            MissingLoopbackPill(text: "App Audio Needs Loopback")
        case .microphone:
            MissingLoopbackPill(text: isListening ? "Microphone Live" : "Microphone Ready")
        }
    }

    private func loopbackName(for deviceID: String) -> String {
        if deviceID.isEmpty {
            return "No Device"
        }

        return availableLoopbackDevices.first(where: { $0.id == deviceID })?.name ?? "No Device"
    }
}

struct TranscriptPanel<Content: View, Footer: View>: View {
    let content: Content
    let footer: Footer

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                content
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .frame(minHeight: 340, alignment: .topLeading)

                Divider()
                    .overlay(AppTheme.ColorToken.border)

                footer
                    .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct LiveCaptionViewport: View {
    let visibleCaptionLines: [String]
    let isListening: Bool
    let idleMessage: String
    let lastError: String?
    @State private var previousVisibleCaptionLines: [String] = []

    private let bottomScrollAnchorID = "live-caption-bottom-anchor"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Caption Stream")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)

                Spacer()

                Text(isListening ? "LIVE" : "OFFLINE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isListening ? AppTheme.ColorToken.accent : AppTheme.ColorToken.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(isListening ? AppTheme.ColorToken.accent.opacity(0.12) : AppTheme.ColorToken.hoverFill)
                    )
            }

            if visibleCaptionLines.isEmpty {
                TranscriptIdleState(
                    title: "Live Subtitles Idle",
                    message: idleMessage
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(Array(visibleCaptionLines.enumerated()), id: \.offset) { index, line in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(index == visibleCaptionLines.count - 1 ? "Now" : "Previous")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(AppTheme.ColorToken.textMuted)
                                        .textCase(.uppercase)
                                        .tracking(0.8)

                                    Text(line)
                                        .font(index == visibleCaptionLines.count - 1 ? .system(size: 28, weight: .semibold) : .system(size: 20, weight: .medium))
                                        .foregroundStyle(index == visibleCaptionLines.count - 1 ? AppTheme.ColorToken.textPrimary : AppTheme.ColorToken.textMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(bottomScrollAnchorID)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: .infinity)
                    .onAppear {
                        previousVisibleCaptionLines = visibleCaptionLines
                        proxy.scrollTo(bottomScrollAnchorID, anchor: .bottom)
                    }
                    .onChange(of: visibleCaptionLines, initial: false) { _, nextLines in
                        let shouldScroll = LiveCaptionAutoScrollTrigger.shouldScroll(
                            from: previousVisibleCaptionLines,
                            to: nextLines
                        )
                        previousVisibleCaptionLines = nextLines

                        guard shouldScroll else {
                            return
                        }

                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(bottomScrollAnchorID, anchor: .bottom)
                        }
                    }
                }
            }

            if let lastError {
                Text(lastError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ConversationViewport: View {
    let rows: [ConversationRow]
    let partialText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Conversation Stream")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)

                Spacer()

                Text("\(rows.count) turns")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.textMuted)
            }

            if rows.isEmpty && partialText.isEmpty {
                TranscriptIdleState(
                    title: "Conversation View Idle",
                    message: "Start listening to watch speaker-grouped transcript bubbles appear here."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(rows) { row in
                            ConversationBubble(row: row)
                        }

                        if partialText.isEmpty == false {
                            ConversationBubble(
                                row: ConversationRow(
                                    id: "conversation-draft",
                                    speaker: rows.last?.speaker ?? "Speaker A",
                                    text: partialText,
                                    timestampLabel: nil,
                                    isPrimarySpeaker: rows.last?.isPrimarySpeaker ?? true
                                ),
                                isDraft: true
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct ConversationBubble: View {
    let row: ConversationRow
    var isDraft = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(row.speaker)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(row.isPrimarySpeaker ? AppTheme.ColorToken.accent : Color(red: 0.090, green: 0.620, blue: 0.290))

                if let timestampLabel = row.timestampLabel {
                    Text(timestampLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.textMuted)
                } else if isDraft {
                    Text("Live")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.textMuted)
                }
            }

            Text(row.text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous)
                .fill(row.isPrimarySpeaker ? AppTheme.ColorToken.accent.opacity(isDraft ? 0.08 : 0.12) : Color.white.opacity(isDraft ? 0.42 : 0.62))
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    row.isPrimarySpeaker ? AppTheme.ColorToken.accent.opacity(0.18) : AppTheme.ColorToken.border,
                    lineWidth: 1
                )
        }
    }
}

struct TranscriptFooterControls: View {
    @Binding var sourceLanguage: String
    @Binding var targetLanguage: String
    let isListening: Bool
    let onToggleListening: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                CompactSelectionField(
                    title: "Language",
                    selection: $sourceLanguage,
                    options: languageOptions.map(\.code),
                    label: languageName(for:)
                )

                CompactSelectionField(
                    title: "Translate",
                    selection: Binding(
                        get: { translationSelection },
                        set: { selection in
                            targetLanguage = selection == "same" ? sourceLanguage : selection
                        }
                    ),
                    options: ["same"] + languageOptions.map(\.code),
                    label: translationLabel(for:)
                )
            }

            Spacer(minLength: 16)

            Button {
                onToggleListening()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isListening ? "stop.fill" : "play.fill")
                    Text(isListening ? "Stop Listening" : "Start Listening")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
                        .fill(AppTheme.ColorToken.accent)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var translationSelection: String {
        targetLanguage == sourceLanguage ? "same" : targetLanguage
    }

    private func languageName(for code: String) -> String {
        languageOptions.first(where: { $0.code == code })?.name ?? code.uppercased()
    }

    private func translationLabel(for code: String) -> String {
        code == "same" ? "No Translation" : languageName(for: code)
    }
}

private struct TranscriptIdleState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.accent)

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)

                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.horizontal, 28)
//        .background(
//            RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous)
//                .fill(Color.white.opacity(0.42))
//        )
//        .overlay {
//            RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous)
//                .strokeBorder(AppTheme.ColorToken.border, style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
//        }
    }
}

private struct CompactSelectionField<Option: Hashable>: View {
    let title: String
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option))
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(alignment: .leading)
        }
    }
}

@ViewBuilder
func selectionFieldLabel(text: String, minWidth: CGFloat = 150) -> some View {
    HStack(spacing: 12) {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.ColorToken.textPrimary)
            .lineLimit(1)

        Spacer(minLength: 8)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(minWidth: minWidth, alignment: .leading)
    .background(
        RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
            .fill(AppTheme.ColorToken.controlFill)
    )
    .overlay {
        RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
            .strokeBorder(AppTheme.ColorToken.border, lineWidth: 1)
    }
}

private struct MissingLoopbackPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.ColorToken.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
                    .fill(AppTheme.ColorToken.controlFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.ColorToken.border, lineWidth: 1)
            }
    }
}

private struct LanguageOption: Hashable {
    let code: String
    let name: String
}

private let languageOptions: [LanguageOption] = [
    .init(code: "en", name: "English"),
    .init(code: "vi", name: "Vietnamese"),
    .init(code: "es", name: "Spanish"),
    .init(code: "ja", name: "Japanese")
]
