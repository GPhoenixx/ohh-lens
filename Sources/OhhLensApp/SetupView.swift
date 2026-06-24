import SwiftUI

struct SetupView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Setup")
                .font(.largeTitle.bold())
            Text("Bootstrap shell for the Ohh Lens setup flow.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
