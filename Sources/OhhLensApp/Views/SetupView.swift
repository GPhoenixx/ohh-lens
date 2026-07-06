import SwiftUI

struct SetupView: View {
    @Environment(AppStore.self) private var appStore
    @State private var selectedWhisperModel: WhisperModelOption = .medium
    @State private var selectedSubtitlePreset: SubtitlePresetOption = .liquidBlack

    var body: some View {
        @Bindable var appStore = appStore

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("App Settings")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)

                VStack(alignment: .leading, spacing: 20) {
                    settingsGroup(title: "Audio & Transcription Model") {
                        settingsRow(
                            title: "Loopback Device",
                            detail: "Virtual devices enable true routed System Audio and App Audio capture. Without one, System Audio falls back to Live Audio through the microphone."
                        ) {
                            HStack(spacing: 8) {
                                Picker(
                                    "Loopback Device",
                                    selection: Binding(
                                        get: { appStore.selectedLoopbackDeviceID ?? "" },
                                        set: { appStore.selectedLoopbackDeviceID = $0 }
                                    )
                                ) {
                                    ForEach(appStore.availableLoopbackDevices) { device in
                                        Text(device.name)
                                            .tag(device.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(alignment: .leading)

                                Button("Scan System") {
                                    appStore.refreshLoopbackDevices()
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                                .background(controlBackground)
                            }
                        }

                        settingsRow(
                            title: "Whisper Model Size",
                            detail: "Larger models are more accurate but consume memory"
                        ) {
                            Picker("Whisper Model Size", selection: $selectedWhisperModel) {
                                ForEach(WhisperModelOption.allCases, id: \.self) { option in
                                    Text(option.title)
                                        .tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(alignment: .leading)
                        }
                    }

                    settingsGroup(title: "Subtitles Layout & Styling") {
                        settingsRow(
                            title: "Target Subtitle Preset",
                            detail: "Choose visual appearance of overlay window"
                        ) {
                            Picker("Target Subtitle Preset", selection: $selectedSubtitlePreset) {
                                ForEach(SubtitlePresetOption.allCases, id: \.self) { option in
                                    Text(option.title)
                                        .tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(alignment: .leading)
                        }

                        settingsRow(
                            title: "Appearance",
                            detail: "Choose whether the app follows system, light, or dark mode"
                        ) {
                            Picker("Appearance", selection: $appStore.selectedAppearanceMode) {
                                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                                    Text(mode.title)
                                        .tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(alignment: .leading)
                        }

                        settingsRow(
                            title: "System Accent Color",
                            detail: "Choose primary accent color for UI elements"
                        ) {
                            HStack(spacing: 10) {
                                ForEach(accentSwatches, id: \.theme) { swatch in
                                    Button {
                                        appStore.selectedAccentTheme = swatch.theme
                                    } label: {
                                        Circle()
                                            .fill(swatch.color)
                                            .frame(width: 18, height: 18)
                                            .overlay {
                                                Circle()
                                                    .strokeBorder(
                                                        appStore.selectedAccentTheme == swatch.theme ? AppTheme.ColorToken.textPrimary : .clear,
                                                        lineWidth: 1.5
                                                    )
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Local Runtime Status")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.textPrimary)

                        statusLine(title: "Backend service", detail: appStore.backendStatusText)
                        statusLine(title: "Diagnostics", detail: appStore.setupMessage)
                        statusLine(title: "Microphone permission", detail: "Grant access in System Settings so live capture can start instantly.")
                    }
                }
            }
            .padding(AppTheme.Layout.contentPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.clear)
    }

    private func settingsGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)
                    .padding(.bottom, 6)

                content()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func settingsRow<Accessory: View>(
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)

                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.ColorToken.border)
                .frame(height: 1)
        }
    }

    private func statusLine(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.textMuted)
        }
    }

    private var controlBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
            .fill(AppTheme.ColorToken.controlFill)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Layout.controlCornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.ColorToken.border, lineWidth: 1)
            }
    }

    private var accentSwatches: [(theme: AccentTheme, color: Color)] {
        [
            (.blue, AppTheme.accentColor(for: .blue)),
            (.purple, AppTheme.accentColor(for: .purple)),
            (.pink, AppTheme.accentColor(for: .pink)),
            (.red, AppTheme.accentColor(for: .red)),
            (.orange, AppTheme.accentColor(for: .orange)),
            (.green, AppTheme.accentColor(for: .green)),
            (.graphite, AppTheme.accentColor(for: .graphite))
        ]
    }
}

private enum WhisperModelOption: CaseIterable {
    case tiny
    case base
    case medium
    case large

    var title: String {
        switch self {
        case .tiny:
            "Whisper-Tiny (75MB / Low Latency)"
        case .base:
            "Whisper-Base (140MB)"
        case .medium:
            "Whisper-Medium (760MB / Recommended)"
        case .large:
            "Whisper-Large (1.5GB / Max Precision)"
        }
    }
}

private enum SubtitlePresetOption: CaseIterable {
    case liquidBlack
    case cobaltCore
    case minimalInk

    var title: String {
        switch self {
        case .liquidBlack:
            "Liquid Black (Translucent)"
        case .cobaltCore:
            "Cobalt Core (Accent color plate)"
        case .minimalInk:
            "Minimal Ink (Text only)"
        }
    }
}
