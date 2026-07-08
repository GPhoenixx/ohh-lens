import SwiftUI

struct ConversationsView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        @Bindable var appStore = appStore
        let footerBindings = makeTranscriptFooterBindings(for: appStore)

        VStack(alignment: .leading, spacing: 20) {
            TranscriptScreenHeader(
                title: "Conversations",
                headerPillState: appStore.headerPillState,
                availableLoopbackDevices: appStore.availableLoopbackDevices,
                selectedLoopbackDeviceID: $appStore.selectedLoopbackDeviceID,
                showsLoopbackDevicePicker: appStore.showsHeaderLoopbackPicker,
                onHeaderPillTap: appStore.handleHeaderPillAction
            )

            TranscriptPanel {
                ConversationViewport(
                    rows: appStore.conversationRows,
                    partialText: appStore.liveTranscriptState.partialText
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
