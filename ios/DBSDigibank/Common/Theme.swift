import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    static let dbsRed = Color(hex: 0xE1251B)
    static let brandBlue = Color(hex: 0x0072CE)
    static let keyBlue = Color(hex: 0x00ACFF)
    static let ink = Color(hex: 0x1D2A36)
    static let inkSecondary = Color(hex: 0x5D6B78)
    static let hairline = Color(hex: 0xE3E6EA)
    static let canvas = Color(hex: 0xF4F6F8)
    static let paynowTag = Color(hex: 0xC8102E)
    static let sentGreen = Color(hex: 0x1DA462)
    static let scannerOrange = Color(hex: 0xF5A623)
    static let infoPurple = Color(hex: 0x7B4DE8)
}

/// The blue full-width primary button used across the app ("Next", "Done").
struct PrimaryButtonStyle: ButtonStyle {
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.brandBlue.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: 4))
    }
}

/// The notification bell with its red count badge.
struct BellBadge: View {
    var count: Int
    var tint: Color
    var badge: Color = .dbsRed

    var body: some View {
        Image(systemName: "bell")
            .font(.system(size: 21, weight: .light))
            .foregroundStyle(tint)
            .overlay(alignment: .topTrailing) {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 16)
                    .background(badge, in: Capsule())
                    .alignmentGuide(.trailing) { $0[.leading] + 12 }
                    .alignmentGuide(.top) { $0[.top] + 6 }
            }
            .accessibilityLabel("Notifications, \(count)")
    }
}

/// The chat bubble icon.
struct ChatBubbleIcon: View {
    var tint: Color

    var body: some View {
        Image(systemName: "bubble.left")
            .font(.system(size: 21, weight: .light))
            .scaleEffect(x: -1)
            .foregroundStyle(tint)
            .accessibilityLabel("Chat")
    }
}

/// The neutral bank mark: a columned building glyph.
struct BankMark: View {
    var color: Color = .keyBlue

    var body: some View {
        Image(systemName: "building.columns.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// The PAY/NOW wordmark tile used on Home and Pay & Transfer.
/// A shortcut tile: an icon image with a label underneath.
struct QuickTile: View {
    var title: String
    var image: String
    var id: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(image)
                    .resizable()
                    .frame(width: 39, height: 39)
                Text(title)
                    .font(.system(size: 13.3))
                    .foregroundStyle(Color(hex: 0x1D1D1F))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.replacingOccurrences(of: "\n", with: " "))
        .accessibilityIdentifier(id ?? "")
    }
}

/// The title bar used by modal screens: centred title, X on the right.
struct ModalHeader: View {
    var title: String
    var leading: AnyView?
    var trailing: AnyView?
    var onClose: (() -> Void)?

    init(_ title: String, onClose: (() -> Void)? = nil) {
        self.title = title
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.ink)
            HStack {
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 19, weight: .light))
                            .foregroundStyle(Color.ink)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 52)
    }
}

/// The info banner with the purple bar, used on the PayNow screens.
struct PayNowProfileBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white, Color.infoPurple)
            Text("Link your mobile number to \(Text("PayNow").underline()) to get paid by anyone in Singapore")
                .font(.system(size: 14))
                .foregroundStyle(Color.inkSecondary)
                .lineSpacing(3)
        }
        .padding(.vertical, 16)
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .overlay(alignment: .leading) { Rectangle().fill(Color.infoPurple).frame(width: 4) }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.hairline))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

/// A simple screen for tiles that are out of the demo's scope.
struct PlaceholderScreen: View {
    var title: String
    var message: String = "This part of the app isn't in the demo."
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title, onClose: onClose)
            Divider()
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "hammer")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color.inkSecondary)
                Text(title).font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.ink)
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            Spacer()
        }
        .background(.white)
    }
}
