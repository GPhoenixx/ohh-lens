import SwiftUI

struct GlassCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    init(
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous)
                    .fill(AppTheme.ColorToken.cardGlass)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.ColorToken.border, lineWidth: 1)
            }
            .shadow(color: AppTheme.subtleShadow, radius: 8, y: 3)
    }
}
