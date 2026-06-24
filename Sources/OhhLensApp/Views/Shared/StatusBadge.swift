import SwiftUI

struct StatusBadge: View {
    let text: String

    private var tint: Color {
        switch text.lowercased() {
        case _ where text.lowercased().contains("listen"):
            return .green
        case _ where text.lowercased().contains("attention"):
            return .orange
        default:
            return .secondary
        }
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        }
    }
}
