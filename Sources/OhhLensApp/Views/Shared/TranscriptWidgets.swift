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

enum LiveStatusBadgeState {
    static func text(isListening: Bool) -> String {
        isListening ? "LIVE" : "OFFLINE"
    }

    static func isAnimated(isListening: Bool) -> Bool {
        isListening
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

                if appStore.languagePair.target == previousSource || appStore.languagePair.target == "same" {
                    appStore.languagePair.target = newValue == "auto" ? "same" : newValue
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
    let headerPillState: AppStore.HeaderPillState?
    let availableLoopbackDevices: [AudioInputDevice]
    @Binding var selectedLoopbackDeviceID: String?
    let showsLoopbackDevicePicker: Bool
    let onHeaderPillTap: @MainActor () async -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppTheme.ColorToken.textPrimary)

            headerMiddleControl

            Spacer(minLength: 16)
        }
    }

    @ViewBuilder
    private var headerMiddleControl: some View {
        HStack(spacing: 10) {
            if let headerPillState {
                MissingLoopbackPill(
                    text: headerPillState.text,
                    tone: headerPillState.tone,
                    symbolName: headerPillState.symbolName,
                    isInteractive: headerPillState.isInteractive,
                    onTap: onHeaderPillTap
                )
            }

            if showsLoopbackDevicePicker {
                CompactSelectionField(
                    title: "Virtual Device",
                    selection: Binding(
                        get: { selectedLoopbackDeviceID ?? "" },
                        set: { selectedLoopbackDeviceID = $0 }
                    ),
                    options: pickerOptions,
                    label: loopbackName(for:)
                )
            }
        }
    }

    private var pickerOptions: [String] {
        let ids = availableLoopbackDevices.map(\.id)
        return ids.isEmpty ? [""] : ids
    }

    private func loopbackName(for deviceID: String) -> String {
        if deviceID.isEmpty {
            return "No Virtual Device"
        }

        return availableLoopbackDevices.first(where: { $0.id == deviceID })?.name ?? "No Virtual Device"
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
    let translatedCaptionPairs: [LiveSubtitlePair]
    let untranslatedDraftText: String?
    let isListening: Bool
    let idleMessage: String
    let lastError: String?
    @State private var previousVisibleCaptionLines: [String] = []

    private let bottomScrollAnchorID = "live-caption-bottom-anchor"
    private let translationBottomScrollAnchorID = "translation-caption-bottom-anchor"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Caption Stream")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)

                Spacer()

                LiveStatusBadge(isListening: isListening)
            }

            if visibleCaptionLines.isEmpty && translatedCaptionPairs.isEmpty {
                TranscriptIdleState(
                    title: "Live Subtitles Idle",
                    message: idleMessage
                )
                .frame(maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 24) {
                    liveTranscriptColumn

                    Divider()
                        .overlay(AppTheme.ColorToken.border)

                    translatedPairsColumn
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if let lastError {
                Text(lastError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var liveTranscriptColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            columnHeader("Now")

            ScrollViewReader { proxy in
                ScrollView {
                    Text(liveTranscriptText)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Color.clear
                        .frame(height: 1)
                        .id(bottomScrollAnchorID)
                }
                .scrollIndicators(.hidden)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var translatedPairsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            columnHeader("Vietnamese")

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if translatedCaptionPairs.isEmpty {
                            Text("Waiting for a 2-second translation block...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppTheme.ColorToken.textMuted)
                        } else {
                            ForEach(translatedCaptionPairs) { pair in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(pair.englishText)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AppTheme.ColorToken.textPrimary)

                                    Text(pair.vietnameseText)
                                        .font(.system(size: 19, weight: .medium))
                                        .foregroundStyle(AppTheme.ColorToken.textPrimary)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(translationBottomScrollAnchorID)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    proxy.scrollTo(translationBottomScrollAnchorID, anchor: .bottom)
                }
                .onChange(of: translatedCaptionPairs, initial: false) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(translationBottomScrollAnchorID, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var liveTranscriptText: String {
        let transcript = visibleCaptionLines.joined(separator: "\n")
        return transcript.isEmpty ? (untranslatedDraftText ?? "") : transcript
    }

    private func columnHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.ColorToken.textMuted)
            .textCase(.uppercase)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LiveStatusBadge: View {
    let isListening: Bool

    var body: some View {
        let isAnimated = LiveStatusBadgeState.isAnimated(isListening: isListening)

        HStack(spacing: 8) {
            if isAnimated {
                ActivityWaveformGlyph()
                    .frame(width: 20, height: 12)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
            }

            Text(LiveStatusBadgeState.text(isListening: isListening))
                .font(.system(size: 11, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(isAnimated ? AppTheme.ColorToken.accent : AppTheme.ColorToken.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isAnimated ? AppTheme.ColorToken.accent.opacity(0.12) : AppTheme.ColorToken.hoverFill)
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    isAnimated ? AppTheme.ColorToken.accent.opacity(0.24) : .clear,
                    lineWidth: 1
                )
        }
        .shadow(
            color: isAnimated ? AppTheme.ColorToken.accent.opacity(0.14) : .clear,
            radius: 10,
            y: 0
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isAnimated)
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
                            targetLanguage = selection == "same" ? "same" : selection
                        }
                    ),
                    options: ["same"] + languageOptions.filter { $0.code != "auto" }.map(\.code),
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
        targetLanguage == "same" || targetLanguage == sourceLanguage ? "same" : targetLanguage
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

struct MissingLoopbackPill: View {
    let text: String
    let tone: AppStore.HeaderPillState.Tone
    let symbolName: String?
    let isInteractive: Bool
    let onTap: @MainActor () async -> Void

    var body: some View {
        Button {
            Task { await onTap() }
        } label: {
            HStack(spacing: 8) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 11, weight: .bold))
                }

                if isReadyState {
                    Circle()
                        .fill(readyAccentColor)
                        .frame(width: 6, height: 6)
                }

                Text(text)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: 10, y: 0)
        }
        .buttonStyle(.plain)
        .disabled(isInteractive == false)
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral where isReadyState:
            return AppTheme.ColorToken.textPrimary
        case .neutral:
            return AppTheme.ColorToken.textMuted
        case .accent, .warning:
            return AppTheme.ColorToken.textPrimary
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral where isReadyState:
            return AppTheme.ColorToken.controlFill.opacity(0.96)
        case .neutral:
            return AppTheme.ColorToken.controlFill
        case .accent:
            return AppTheme.ColorToken.accent.opacity(0.16)
        case .warning:
            return Color(red: 0.78, green: 0.46, blue: 0.10).opacity(0.18)
        }
    }

    private var borderColor: Color {
        switch tone {
        case .neutral where isReadyState:
            return readyAccentColor.opacity(0.42)
        case .neutral:
            return AppTheme.ColorToken.border
        case .accent:
            return AppTheme.ColorToken.accent.opacity(0.42)
        case .warning:
            return Color(red: 0.84, green: 0.52, blue: 0.12).opacity(0.52)
        }
    }

    private var shadowColor: Color {
        switch tone {
        case .neutral where isReadyState:
            return readyAccentColor.opacity(0.14)
        case .neutral:
            return .clear
        case .accent:
            return AppTheme.ColorToken.accent.opacity(0.14)
        case .warning:
            return Color(red: 0.84, green: 0.52, blue: 0.12).opacity(0.12)
        }
    }

    private var isReadyState: Bool {
        tone == .neutral && isInteractive == false
    }

    private var readyAccentColor: Color {
        Color(.green)
    }
}

private struct ActivityWaveformGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 0.12, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(AppTheme.ColorToken.accent)
                        .frame(width: 3, height: barHeight(for: index, time: time))
                }
            }
            .frame(width: 24, height: 14, alignment: .center)
        }
        .accessibilityHidden(true)
    }

    private func barHeight(for index: Int, time: TimeInterval) -> CGFloat {
        guard reduceMotion == false else {
            return [6.0, 10.0, 8.0, 12.0][index]
        }

        let phaseOffsets = [0.0, 0.9, 1.8, 2.7]
        let phase = (time * 6.4) + phaseOffsets[index]
        let amplitude = (sin(phase) + 1) * 0.5

        return 5 + (amplitude * 9)
    }
}

private struct LanguageOption: Hashable {
    let code: String
    let name: String
}

private let languageOptions: [LanguageOption] = [
    .init(code: "auto", name: "Auto-detect"),
    .init(code: "zh", name: "Chinese"),
    .init(code: "en", name: "English"),
    .init(code: "yue", name: "Cantonese"),
    .init(code: "ar", name: "Arabic"),
    .init(code: "de", name: "German"),
    .init(code: "fr", name: "French"),
    .init(code: "es", name: "Spanish"),
    .init(code: "pt", name: "Portuguese"),
    .init(code: "id", name: "Indonesian"),
    .init(code: "it", name: "Italian"),
    .init(code: "ko", name: "Korean"),
    .init(code: "ru", name: "Russian"),
    .init(code: "th", name: "Thai"),
    .init(code: "vi", name: "Vietnamese"),
    .init(code: "ja", name: "Japanese"),
    .init(code: "tr", name: "Turkish"),
    .init(code: "hi", name: "Hindi"),
    .init(code: "ms", name: "Malay"),
    .init(code: "nl", name: "Dutch"),
    .init(code: "sv", name: "Swedish"),
    .init(code: "da", name: "Danish"),
    .init(code: "fi", name: "Finnish"),
    .init(code: "pl", name: "Polish"),
    .init(code: "cs", name: "Czech"),
    .init(code: "fil", name: "Filipino"),
    .init(code: "fa", name: "Persian"),
    .init(code: "el", name: "Greek"),
    .init(code: "hu", name: "Hungarian"),
    .init(code: "mk", name: "Macedonian"),
    .init(code: "ro", name: "Romanian")
]
