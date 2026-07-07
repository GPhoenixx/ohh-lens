import SwiftUI

struct LiveView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        @Bindable var appStore = appStore
        let footerBindings = makeTranscriptFooterBindings(for: appStore)

        VStack(alignment: .leading, spacing: 20) {
            TranscriptScreenHeader(
                title: "Live Subtitles",
                headerPillState: appStore.headerPillState,
                isPiPVisible: appStore.pipState.isVisible,
                availableLoopbackDevices: appStore.availableLoopbackDevices,
                selectedLoopbackDeviceID: $appStore.selectedLoopbackDeviceID,
                showsLoopbackDevicePicker: appStore.effectiveCaptureMode.displayCopy.showsLoopbackDevicePicker,
                onTogglePiP: appStore.togglePiP,
                onHeaderPillTap: appStore.handleHeaderPillAction
            )

            TranscriptPanel {
                LiveCaptionViewport(
                    visibleCaptionLines: appStore.liveTranscriptState.visibleCaptionLines,
                    isListening: appStore.isListening,
                    idleMessage: appStore.liveIdleMessage,
                    lastError: appStore.liveTranscriptState.lastError
                )
            } footer: {
                TranscriptFooterControls(
                    sourceLanguage: footerBindings.sourceLanguage,
                    targetLanguage: footerBindings.targetLanguage,
                    isListening: appStore.isListening,
                    onToggleListening: footerBindings.toggleListening
                )
            }
        }
        .padding(AppTheme.Layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
    }
}
