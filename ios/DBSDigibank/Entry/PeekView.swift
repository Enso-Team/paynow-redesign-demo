import CoreImage
import SwiftUI
import UIKit

/// Tap and hold on the entry screen. Stage lengths:
/// the card slides up (0.15 s), shows two grey bars (0.5 s), stays empty (0.8 s or until the data
/// arrives), the balance fades in (0.2 s), then the card grows upward. A cached result skips to the balance.
@MainActor
@Observable
final class PeekHold {
    enum Phase { case off, slide, bars, blank, compact, expanded }

    private(set) var phase: Phase = .off
    private(set) var data: PeekBalance?
    private(set) var failed = false
    /// Where the hint sits on screen, so the card and the sharp hint line up with it.
    var hint: CGRect = .zero
    /// The entry page as it looked when the press started, blurred once.
    private(set) var backdrop: UIImage?

    @ObservationIgnored private var run = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var startedAt = Date.distantPast

    /// The `-peekHoldSeconds N` launch argument keeps Peek open N seconds after a press starts,
    /// so a driver can screenshot it after releasing.
    static var minimumHold: TimeInterval { max(0, UserDefaults.standard.double(forKey: "peekHoldSeconds")) }

    var active: Bool { phase != .off }

    func start(_ app: AppModel) {
        guard !active else { return }
        run += 1
        let id = run
        startedAt = .now
        failed = false
        task?.cancel()
        backdrop = PeekBackdrop.capture()

        if let hit = app.peek.cached {
            data = hit
            phase = .compact
            task = Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard run == id else { return }
                withAnimation(.snappy(duration: 0.22)) { phase = .expanded }
            }
            return
        }

        data = nil
        let result = Task { await app.loadPeek() }
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.15)) { phase = .slide }
        task = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard run == id else { return }
            phase = .bars
            try? await Task.sleep(for: .milliseconds(500))
            guard run == id else { return }
            phase = .blank
            try? await Task.sleep(for: .milliseconds(800))
            let loaded = await result.value
            guard run == id else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                data = loaded
                failed = loaded == nil
                phase = .compact
            }
            guard loaded != nil else { return }
            try? await Task.sleep(for: .milliseconds(200))
            guard run == id else { return }
            withAnimation(.snappy(duration: 0.22)) { phase = .expanded }
        }
    }

    func end() {
        guard active else { return }
        let remaining = Self.minimumHold - Date.now.timeIntervalSince(startedAt)
        if remaining > 0 {
            let id = run
            Task {
                try? await Task.sleep(for: .seconds(remaining))
                guard run == id else { return }
                finish()
            }
            return
        }
        finish()
    }

    /// Shows one phase as-is, for render tests.
    func show(_ phase: Phase, data: PeekBalance?, backdrop: UIImage?) {
        run += 1
        task?.cancel()
        self.data = data
        self.backdrop = backdrop
        failed = false
        self.phase = phase
    }

    private func finish() {
        guard active else { return }
        run += 1
        task?.cancel()
        withAnimation(.easeIn(duration: 0.15)) { phase = .off }
    }
}

/// A blurred, slightly darker still of the window. Blurring a still keeps the page smooth with no
/// live-view artefacts.
@MainActor
enum PeekBackdrop {
    private static let context = CIContext()

    static func capture(_ window: UIWindow? = keyWindow) -> UIImage? {
        guard let window, window.bounds.width > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let still = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return blurred(still)
    }

    static func blurred(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let extent = input.extent
        let output = input.clampedToExtent()
            .applyingGaussianBlur(sigma: 18)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.15, kCIInputBrightnessKey: -0.06])
            .cropped(to: extent)
        guard let cgImage = context.createCGImage(output, from: extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

/// Peek over the entry page: the blurred still with a dark veil, the white card whose bottom edge sits
/// 14 pt above the hint and which grows upward to the safe area at most, and the hint kept sharp.
struct PeekOverlay<Hint: View>: View {
    let hold: PeekHold
    let hint: CGRect
    let safeTop: CGFloat
    /// The page's width inside the side safe areas, so the card lines up with the page.
    let contentWidth: CGFloat
    @ViewBuilder var hintView: Hint

    var body: some View {
        GeometryReader { geo in
            let cardBottom = max(0, hint.minY - 14)
            ZStack(alignment: .topLeading) {
                Group {
                    if let backdrop = hold.backdrop {
                        Image(uiImage: backdrop).resizable().frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        Color(hex: 0x05080C)
                    }
                }
                Color(hex: 0x080A0E, opacity: 0.26)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if hold.phase != .off {
                        PeekCard(hold: hold)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.asymmetric(insertion: .offset(y: 26).combined(with: .opacity), removal: .opacity))
                    }
                }
                .padding(.top, safeTop + 8)
                .padding(.horizontal, 40)
                .frame(width: contentWidth, height: cardBottom)

                hintView
                    .frame(width: hint.width, height: hint.height)
                    .position(x: hint.midX, y: hint.midY)
                    .accessibilityHidden(true)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
    }
}

/// The white Peek card. It sits on the hint and grows upward as rows appear.
struct PeekCard: View {
    let hold: PeekHold

    private var shown: Bool { hold.phase == .compact || hold.phase == .expanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hold.phase == .bars {
                VStack(spacing: 10) {
                    Capsule().fill(Color(hex: 0xE2E3E6)).frame(width: 0.34 * 364, height: 10)
                    Capsule().fill(Color(hex: 0xE2E3E6)).frame(width: 0.52 * 364, height: 10)
                }
                .frame(maxWidth: .infinity, minHeight: 84)
            } else if shown, hold.failed {
                Text("Couldn't load your balance. Try again.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color(hex: 0x3F454A))
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .transition(.opacity)
            } else if shown, let data = hold.data {
                content(data)
                    .transition(.opacity)
            } else {
                Color.clear.frame(height: 84)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 3).fill(.white).shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek.card")
    }

    private func content(_ data: PeekBalance) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Deposit balance")
                .font(.system(size: 12.5))
                .tracking(0.2)
                .foregroundStyle(Color(hex: 0x6E7377))
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(data.currency).font(.system(size: 15, weight: .medium)).foregroundStyle(Color(hex: 0x3F454A))
                Text(data.balance).font(.system(size: 25, weight: .semibold)).tracking(-0.3).foregroundStyle(Color(hex: 0x1D1D1F))
            }
            .padding(.top, 3)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("peek.balance")
            if hold.phase == .expanded {
                details(data)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 13)
        .frame(minHeight: 84, alignment: .topLeading)
    }

    private func details(_ data: PeekBalance) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("As of \(PeekFormat.asOf(data.asOf))")
                .font(.system(size: 11.5))
                .foregroundStyle(Color(hex: 0x8A8F93))
                .padding(.top, 2)
            Rectangle().fill(Color(hex: 0xECECEE)).frame(height: 1).padding(.top, 11)
            Text("Latest transactions (within last 30 days)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x3F454A))
                .padding(.top, 10)
            if data.transactions.isEmpty {
                Text("No transactions in the last 30 days")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(hex: 0x8A8F93))
                    .padding(.top, 8)
            }
            ForEach(Array(data.transactions.enumerated()), id: \.offset) { index, transaction in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(transaction.type).font(.system(size: 13.5)).foregroundStyle(Color(hex: 0x1D1D1F))
                        Text(PeekFormat.day(transaction.date)).font(.system(size: 11.5)).foregroundStyle(Color(hex: 0x8A8F93))
                    }
                    Spacer()
                    Text(PeekFormat.signed(transaction.amount))
                        .font(.system(size: 13.5))
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: 0x1D1D1F))
                }
                .padding(.top, 6)
                .padding(.bottom, index == data.transactions.count - 1 ? 0 : 6)
                .overlay(alignment: .bottom) {
                    if index < data.transactions.count - 1 { Rectangle().fill(Color(hex: 0xF2F2F4)).frame(height: 1) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("peek.transaction.\(index)")
            }
        }
    }
}
