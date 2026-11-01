import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case library
    case search
    case effects
    case settings

    var title: String {
        switch self {
        case .library:
            return "音乐库"
        case .search:
            return "搜索"
        case .effects:
            return "音质与音效"
        case .settings:
            return "设置"
        }
    }

    var shortTitle: String {
        switch self {
        case .library:
            return "音乐库"
        case .search:
            return "搜索"
        case .effects:
            return "音效"
        case .settings:
            return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .library:
            return "square.stack.3d.up.fill"
        case .search:
            return "magnifyingglass"
        case .effects:
            return "waveform.badge.plus"
        case .settings:
            return "gearshape.fill"
        }
    }
}

struct GlassTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 16, weight: .semibold))

                        Text(tab.shortTitle)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(
                        selection == tab
                            ? AppTheme.primaryButtonText
                            : AppTheme.textTertiary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppTheme.accentGradient)
                                .matchedGeometryEffect(
                                    id: "selectedTab",
                                    in: selectionNamespace
                                )
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel(tab.title)
            }
        }
        .padding(6)
        .glassPanel(cornerRadius: 24, tint: AppTheme.ice, strokeOpacity: 0.16)
    }
}
