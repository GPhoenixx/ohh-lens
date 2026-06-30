import SwiftUI

struct LiveView: View {
    @Environment(AppStore.self) private var appStore

    private let sourceColumns = [
        GridItem(.adaptive(minimum: 180), spacing: 16)
    ]

    var body: some View {
        @Bindable var appStore = appStore

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Live subtitles")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Route local audio into your FunASR service and watch captions update in real time.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                    StatusBadge(text: appStore.statusText)
                }

                LazyVGrid(columns: sourceColumns, alignment: .leading, spacing: 16) {
                    ForEach(AudioSource.allCases) { source in
                        SourceCard(
                            title: sourceTitle(for: source),
                            detail: sourceDetail(for: source),
                            isSelected: appStore.selectedSource == source
                        )
                        .onTapGesture {
                            appStore.selectedSource = source
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    if appStore.selectedSource == .systemAudio || appStore.selectedSource == .appAudio {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Loopback device")
                                .font(.headline)

                            if appStore.availableLoopbackDevices.isEmpty {
                                Text("No virtual audio device found. Install BlackHole or Loopback, then route YouTube audio through it.")
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("Loopback device", selection: Binding(
                                    get: { appStore.selectedLoopbackDeviceID ?? "" },
                                    set: { appStore.selectedLoopbackDeviceID = $0 }
                                )) {
                                    ForEach(appStore.availableLoopbackDevices) { device in
                                        Text(device.name).tag(device.id)
                                    }
                                }
                                .pickerStyle(.menu)

                                Text("Capture is armed. Start playback through the selected loopback device and Ohh Lens will listen for routed audio.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Text("Caption mode")
                        .font(.headline)

                    Picker("Caption mode", selection: $appStore.captionMode) {
                        Text("Original").tag(CaptionMode.originalOnly)
                        Text("Translation").tag(CaptionMode.translationOnly)
                        Text("Dual line").tag(CaptionMode.dualLine)
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        Button(appStore.isListening ? "Listening..." : "Start Listening") {
                            appStore.startListening()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appStore.isListening)

                        Button("Stop") {
                            appStore.stopListening()
                        }
                        .buttonStyle(.bordered)
                        .disabled(appStore.isListening == false)

                        Button("Load Preview Subtitle") {
                            appStore.applyPreviewTranscript()
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                }
                .padding(20)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Current session")
                        .font(.headline)
                    Text(sessionSummary(for: appStore))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if appStore.liveTranscriptState.visibleCaptionLines.isEmpty == false {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(appStore.liveTranscriptState.visibleCaptionLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(index == appStore.liveTranscriptState.visibleCaptionLines.count - 1 ? .title3.weight(.semibold) : .body)
                                    .foregroundStyle(index == appStore.liveTranscriptState.visibleCaptionLines.count - 1 ? .primary : .secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if let lastError = appStore.liveTranscriptState.lastError {
                        Text(lastError)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.16),
                            Color.accentColor.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
            }
            .padding(24)
        }
        .background(Color.clear)
    }

    private func sessionSummary(for store: AppStore) -> String {
        let source = sourceTitle(for: store.selectedSource)
        let mode: String

        switch store.captionMode {
        case .originalOnly:
            mode = "Original only"
        case .translationOnly:
            mode = "Translation only"
        case .dualLine:
            mode = "Dual-line captions"
        }

        let flowSummary: String
        if store.selectedSource == .systemAudio || store.selectedSource == .appAudio {
            flowSummary = "Loopback device: \(store.selectedLoopbackDeviceName() ?? "not selected")."
        } else {
            flowSummary = "Capture is not using a loopback device."
        }

        return "\(source) selected. \(mode). Backend: \(store.backendStatusText). \(flowSummary)"
    }

    private func sourceTitle(for source: AudioSource) -> String {
        switch source {
        case .microphone:
            return "Microphone"
        case .systemAudio:
            return "System audio"
        case .appAudio:
            return "App audio"
        case .importedFile:
            return "Imported file"
        }
    }

    private func sourceDetail(for source: AudioSource) -> String {
        switch source {
        case .microphone:
            return "Use your default input device for speech around you."
        case .systemAudio:
            return "Capture the Mac mix through a loopback device."
        case .appAudio:
            return "Target a single app once your virtual device is ready."
        case .importedFile:
            return "Send a saved recording or video file through the backend."
        }
    }
}

private struct SourceCard: View {
    let title: String
    let detail: String
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(borderStyle, lineWidth: isSelected ? 1.5 : 1)
        }
    }

    private var backgroundStyle: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.20), Color.accentColor.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(.regularMaterial)
    }

    private var borderStyle: Color {
        isSelected ? .accentColor.opacity(0.45) : .white.opacity(0.08)
    }
}
