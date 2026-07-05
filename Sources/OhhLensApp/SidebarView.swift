import SwiftUI

struct SidebarView: View {
    @Environment(AppStore.self) private var appStore

    private struct ItemDescriptor: Identifiable {
        let section: AppSection
        let icon: String
        let group: String

        var id: AppSection { section }
        var title: String { section.title }
    }

    private struct FooterDescriptor {
        let symbol: String
        let title: String
        let detail: String
    }

    private static let itemDescriptors: [ItemDescriptor] = [
        .init(section: .liveSubtitles, icon: "captions.bubble", group: "Captions"),
        .init(section: .conversations, icon: "person.wave.2", group: "Captions"),
        .init(section: .fileTranscriber, icon: "square.and.arrow.down.on.square", group: "Captions"),
        .init(section: .savedTranscripts, icon: "clock.arrow.circlepath", group: "Archive"),
        .init(section: .appSettings, icon: "gearshape", group: "Archive")
    ]

    private static let footerDescriptor = FooterDescriptor(
        symbol: "sparkles",
        title: "Ohh Lens",
        detail: "Local subtitle workspace"
    )

    @Binding var selection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(groupedDescriptors, id: \.group) { group in
                    sidebarGroup(
                        title: group.group,
                        items: group.items
                    )
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 16)

            Divider()
                .overlay(AppTheme.ColorToken.border)

            HStack(spacing: 10) {
                Circle()
                    .fill(AppTheme.avatarGradient(for: appStore.selectedAccentTheme))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: Self.footerDescriptor.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.footerDescriptor.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(Self.footerDescriptor.detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var groupedDescriptors: [(group: String, items: [ItemDescriptor])] {
        Dictionary(grouping: Self.itemDescriptors, by: \.group)
            .map { key, value in (group: key, items: value) }
            .sorted { lhs, rhs in
                groupSortOrder(lhs.group) < groupSortOrder(rhs.group)
            }
    }

    private func sidebarGroup(title: String, items: [ItemDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.leading, 10)

            VStack(spacing: 2) {
                ForEach(items) { item in
                    Button {
                        selection = item.section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 16)

                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))

                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selection == item.section ? Color.white : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(for: item.section, accentTheme: appStore.selectedAccentTheme))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func groupSortOrder(_ group: String) -> Int {
        switch group {
        case "Captions":
            0
        case "Archive":
            1
        default:
            2
        }
    }

    private func background(for section: AppSection, accentTheme: AccentTheme) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selection == section ? AppTheme.accentColor(for: accentTheme) : .clear)
            .overlay {
                if selection == section {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppTheme.accentPressedColor(for: accentTheme).opacity(0.35), lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.001))
                }
            }
    }
}
