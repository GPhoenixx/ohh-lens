import SwiftUI
import OhhLensCore

struct SetupView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Setup")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("Get the local subtitle stack healthy before you start listening.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                setupRow(
                    title: "Backend service",
                    detail: appStore.backendStatusText
                )
                setupRow(
                    title: "Diagnostics",
                    detail: appStore.setupMessage
                )
                setupRow(
                    title: "Microphone permission",
                    detail: "Grant access in System Settings so live capture can start instantly."
                )
                setupRow(
                    title: "Loopback device",
                    detail: appStore.selectedLoopbackDeviceName() ?? "Install or choose your virtual audio device when you want system or app audio subtitles."
                )
                setupRow(
                    title: "Loopback status",
                    detail: "Use the Live view to start listening after your Mac output is routed through the selected loopback device."
                )
            }
            .padding(20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Button("Open System Settings") {}
                .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func setupRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
