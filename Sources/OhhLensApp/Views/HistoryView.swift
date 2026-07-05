import SwiftUI

struct HistoryView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Saved Transcripts")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ColorToken.textPrimary)

            HStack(alignment: .top, spacing: 20) {
                historyListCard
                    .frame(width: 280)

                historyViewerCard
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(AppTheme.Layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
    }

    private var historyListCard: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.textMuted)

                    TextField(
                        "Search transcript content...",
                        text: Binding(
                            get: { appStore.historyViewer.searchText },
                            set: { appStore.updateHistorySearch($0) }
                        )
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
                        .fill(AppTheme.ColorToken.controlFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
                        .strokeBorder(AppTheme.ColorToken.border, lineWidth: 1)
                }
                .padding(16)

                Divider()
                    .overlay(AppTheme.ColorToken.border)

                if filteredHistory.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "text.badge.clock")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(AppTheme.ColorToken.textMuted)

                        Text("No matching transcripts")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.textPrimary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .padding(16)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(filteredHistory) { session in
                                Button {
                                    appStore.selectHistorySession(session.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(sessionTitle(for: session))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(activeSession?.id == session.id ? .white : AppTheme.ColorToken.textPrimary)
                                            .lineLimit(1)

                                        HStack {
                                            Text(historyDateLabel(for: session))
                                            Spacer()
                                            Text(fileSizeLabel(for: session))
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(activeSession?.id == session.id ? Color.white.opacity(0.88) : AppTheme.ColorToken.textMuted)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(historyItemBackground(isActive: activeSession?.id == session.id))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var historyViewerCard: some View {
        GlassCard {
            if let activeSession {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sessionTitle(for: activeSession))
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.textPrimary)

                        Text(sessionMeta(for: activeSession))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.ColorToken.textMuted)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(activeSession.segments.enumerated()), id: \.element.id) { index, segment in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Text(index == 0 ? "Speaker A (Host)" : "Speaker \(index.isMultiple(of: 2) ? "A" : "B")")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(index.isMultiple(of: 2) ? AppTheme.ColorToken.accent : Color(red: 0.090, green: 0.620, blue: 0.290))

                                        Text(timestampLabel(for: segment))
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(AppTheme.ColorToken.textMuted)
                                    }

                                    Text(translatedText(for: segment))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AppTheme.ColorToken.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous)
                                        .fill(index.isMultiple(of: 2) ? AppTheme.ColorToken.accent.opacity(0.12) : Color.white.opacity(0.62))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous)
                                        .strokeBorder(
                                            index.isMultiple(of: 2) ? AppTheme.ColorToken.accent.opacity(0.18) : AppTheme.ColorToken.border,
                                            lineWidth: 1
                                        )
                                }
                            }
                        }
                    }
                    .frame(minHeight: 320)
                    .scrollIndicators(.hidden)

                    HStack(spacing: 12) {
                        Menu {
                            Button("Translation: Off") { appStore.historyViewer.translationTarget = "none" }
                            Button("Translate to: Spanish") { appStore.historyViewer.translationTarget = "es" }
                            Button("Translate to: Japanese") { appStore.historyViewer.translationTarget = "ja" }
                            Button("Translate to: Vietnamese") { appStore.historyViewer.translationTarget = "vi" }
                        } label: {
                            selectionFieldLabel(text: historyTranslationLabel, minWidth: 180)
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(.plain)

                        Spacer()

                        Button("Export") {
                            _ = appStore.exportHistorySRT(for: activeSession)
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
                    .padding(.top, 8)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.textMuted)

                    Text("No saved sessions yet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.textPrimary)

                    Text("Finished transcriptions will appear here so you can reopen and export them later.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var activeSession: SessionRecord? {
        if let selectedSessionID = appStore.historyViewer.selectedSessionID {
            return filteredHistory.first(where: { $0.id == selectedSessionID })
                ?? appStore.history.first(where: { $0.id == selectedSessionID })
        }

        return filteredHistory.first ?? appStore.history.first
    }

    private var filteredHistory: [SessionRecord] {
        let query = appStore.historyViewer.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard query.isEmpty == false else {
            return appStore.history
        }

        return appStore.history.filter { session in
            let haystack = [
                sessionTitle(for: session),
                sourceLabel(for: session.source),
                session.segments.map(\.originalText).joined(separator: " "),
                session.segments.compactMap(\.translatedText).joined(separator: " ")
            ]
            .joined(separator: " ")

            return haystack.localizedCaseInsensitiveContains(query)
        }
    }

    private func historyItemBackground(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isActive ? AppTheme.ColorToken.accent : .clear)
    }

    private func sourceLabel(for source: AudioSource) -> String {
        switch source {
        case .microphone:
            return "Microphone"
        case .systemAudio:
            return "Audio Loopback"
        case .appAudio:
            return "App Audio"
        case .importedFile:
            return "Imported File"
        }
    }

    private func sessionTitle(for session: SessionRecord) -> String {
        if let firstLine = session.segments.first?.originalText, firstLine.isEmpty == false {
            return String(firstLine.prefix(32))
        }

        return sourceLabel(for: session.source)
    }

    private func historyDateLabel(for session: SessionRecord) -> String {
        let calendar = Calendar.current

        if calendar.isDateInYesterday(session.createdAt) {
            return "Yesterday"
        }

        if calendar.isDateInToday(session.createdAt) {
            return "Today"
        }

        return session.createdAt.formatted(date: .abbreviated, time: .omitted)
    }

    private func fileSizeLabel(for session: SessionRecord) -> String {
        let characters = session.segments.reduce(0) { $0 + $1.originalText.count + ($1.translatedText?.count ?? 0) }
        return "\(max(1, characters / 512 + 1)).\(characters % 10) MB"
    }

    private func sessionMeta(for session: SessionRecord) -> String {
        "\(sourceLabel(for: session.source)) / \(durationLabel(for: session)) duration / SRT formatted"
    }

    private func durationLabel(for session: SessionRecord) -> String {
        guard
            let first = session.segments.first?.startedAt,
            let last = session.segments.last?.endedAt,
            last > first
        else {
            return "\(max(session.segments.count, 1)).0 mins"
        }

        return String(format: "%.1f mins", (last - first) / 60)
    }

    private func timestampLabel(for segment: TranscriptSegment) -> String {
        let minutes = Int(segment.startedAt) / 60
        let seconds = Int(segment.startedAt) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func translatedText(for segment: TranscriptSegment) -> String {
        switch appStore.historyViewer.translationTarget {
        case "none":
            return segment.originalText
        default:
            return segment.translatedText ?? segment.originalText
        }
    }

    private var historyTranslationLabel: String {
        switch appStore.historyViewer.translationTarget {
        case "es":
            "Translate to: Spanish"
        case "ja":
            "Translate to: Japanese"
        case "vi":
            "Translate to: Vietnamese"
        default:
            "Translation: Off"
        }
    }
}
