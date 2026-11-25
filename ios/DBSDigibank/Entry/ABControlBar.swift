import SwiftUI

/// The A/B demo switches on the entry screen: which flow runs, and how slow the backend is.
struct ABControlBar: View {
    @AppStorage(ABSettings.flowKey) private var flow = FlowMode.router.rawValue
    @AppStorage(ABSettings.multiplierKey) private var multiplier = 1

    var body: some View {
        HStack(spacing: 8) {
            group {
                ForEach(FlowMode.allCases, id: \.self) { mode in
                    option(mode.title, on: flow == mode.rawValue, id: "ab.flow.\(mode.rawValue)") { flow = mode.rawValue }
                }
            }
            group {
                ForEach(ABSettings.multipliers, id: \.self) { value in
                    option("\(value)x", on: multiplier == value, id: "ab.latency.\(value)") { multiplier = value }
                }
            }
        }
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
            .padding(3)
            .background(Color(hex: 0x1C1E22, opacity: 0.7), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
    }

    private func option(_ title: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(on ? Color.black : .white.opacity(0.75))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background { if on { Capsule().fill(.white) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
