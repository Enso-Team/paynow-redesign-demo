import SwiftUI

/// The signed-in app. Every tab stays alive, so switching keeps scroll position and data and never
/// shows a spinner or asks Face ID.
/// - Compact width (every iPhone): the native TabView with the system Liquid Glass bar and drag-to-switch.
/// - Regular width (the iPhone Duo simulator, where TabView turns into a side bar): our own glass
///   capsule pinned to the bottom, with the tabs kept alive in a ZStack.
struct TabShell: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass

    private struct Item: Identifiable {
        var id: AppTab
        var title: String
        var image: String
        var selectedImage: String
        var accessibilityID: String
    }

    private let items = [
        Item(id: .home, title: "Home", image: "tab-home", selectedImage: "tab-home-on", accessibilityID: "tab.home"),
        Item(id: .pay, title: "Pay & Transfer", image: "tab-pay", selectedImage: "tab-pay-on", accessibilityID: "tab.pay"),
        Item(id: .wealth, title: "Wealth", image: "tab-wealth", selectedImage: "tab-wealth", accessibilityID: "tab.wealth"),
        Item(id: .apply, title: "Apply", image: "tab-apply", selectedImage: "tab-apply-on", accessibilityID: "tab.apply"),
        Item(id: .more, title: "More", image: "tab-more", selectedImage: "tab-more-on", accessibilityID: "tab.more"),
    ]

    var body: some View {
        Group {
            if sizeClass == .regular { capsuleTabs } else { nativeTabs }
        }
        .onChange(of: app.selectedTab) {
            Task {
                await app.session.touch()
                await app.home.refresh()
            }
        }
    }

    private var nativeTabs: some View {
        @Bindable var app = app
        return TabView(selection: $app.selectedTab) {
            ForEach(items) { item in
                Tab(value: item.id) {
                    pane(item.id)
                } label: {
                    Label(item.title, image: app.selectedTab == item.id ? item.selectedImage : item.image)
                }
                .accessibilityIdentifier(item.accessibilityID)
            }
        }
        .tint(Color.brandBlue)
    }

    private var capsuleTabs: some View {
        ZStack {
            ForEach(items) { item in
                let selected = app.selectedTab == item.id
                pane(item.id)
                    .safeAreaPadding(.bottom, 62)
                    .opacity(selected ? 1 : 0)
                    .allowsHitTesting(selected)
                    .accessibilityHidden(!selected)
            }
        }
        .overlay(alignment: .bottom) { bar }
    }

    @ViewBuilder
    private func pane(_ tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .pay: PayTransferView()
        case .wealth: WealthView()
        case .apply: ApplyView()
        case .more: MoreView()
        }
    }

    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let selected = app.selectedTab == item.id
                Button {
                    app.selectedTab = item.id
                } label: {
                    VStack(spacing: 3) {
                        Image(selected ? item.selectedImage : item.image)
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 25, height: 25)
                        Text(item.title)
                            .font(.system(size: 10.5))
                            .tracking(0.2)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundStyle(selected ? Color.white : Color(red: 205 / 255, green: 214 / 255, blue: 220 / 255).opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background {
                        if selected { Capsule().fill(Color.white.opacity(0.12)) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier(item.accessibilityID)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 62)
        .glassEffect(.regular.tint(Color(hex: 0x1E2C36, opacity: 0.74)).interactive(), in: Capsule())
        .shadow(color: Color(hex: 0x0A141E, opacity: 0.28), radius: 15, y: 10)
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
        .animation(.snappy(duration: 0.25), value: app.selectedTab)
    }
}

/// The white top bar with the bell and chat icons, shared by the non-Home tabs.
struct ShellTopBar: View {
    var title: String?

    var body: some View {
        ZStack {
            if let title {
                Text(title).font(.system(size: 18, weight: .medium)).foregroundStyle(Color.ink)
            }
            HStack {
                BellBadge(count: 45, tint: Color.inkSecondary)
                Spacer()
                ChatBubbleIcon(tint: Color.inkSecondary)
            }
            .padding(.horizontal, 22)
        }
        .frame(height: 56)
        .background(.white)
        .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
    }
}
