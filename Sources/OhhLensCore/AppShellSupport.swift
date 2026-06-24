import SwiftUI

public enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case live = "Live"
    case history = "History"
    case files = "Files"
    case setup = "Setup"

    public var id: Self { self }
}

@MainActor
public final class AppStore: ObservableObject {
    @Published public var selectedSection: AppSection

    public init(selectedSection: AppSection = .live) {
        self.selectedSection = selectedSection
    }

    public static let preview = AppStore()
}

public struct SidebarView: View {
    @Binding private var selection: AppSection

    public init(selection: Binding<AppSection>) {
        _selection = selection
    }

    public var body: some View {
        List(AppSection.allCases, selection: $selection) { section in
            Text(section.rawValue)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240)
    }
}

public struct SetupView: View {
    public init() {}

    public var body: some View {
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
