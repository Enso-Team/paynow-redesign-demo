import LocalAuthentication
import SwiftUI
import UIKit

/// The one Face ID check. Uses `.deviceOwnerAuthentication` (passcode fallback) when biometrics are
/// enrolled, and the mocked Face ID sheet when they aren't, as on the simulator: the glyph for 1.2 s,
/// then the checkmark.
@MainActor
@Observable
final class FaceIDCheck {
    enum MockPhase { case scanning, success }

    private(set) var mockPhase: MockPhase?
    private var overlay: UIWindow?
    private var cancelMock: (() -> Void)?

    static let mockScanning: Duration = .milliseconds(1200)
    static let mockSuccess: Duration = .milliseconds(350)

    var biometricsEnrolled: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Asks once and names the journey. Returns nil when the user cancels.
    func check(_ journey: String) async -> AuthContext? {
        if biometricsEnrolled {
            let context = LAContext()
            context.localizedCancelTitle = "Cancel"
            do {
                guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: journey) else { return nil }
                return AuthContext(context)
            } catch {
                return nil
            }
        }
        return await runMock() ? AuthContext(nil) : nil
    }

    private func runMock() async -> Bool {
        showOverlay()
        defer { hideOverlay() }
        mockPhase = .scanning
        let cancelled = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            var finished = false
            let finish: (Bool) -> Void = { value in
                guard !finished else { return }
                finished = true
                continuation.resume(returning: value)
            }
            cancelMock = { finish(true) }
            Task {
                try? await Task.sleep(for: Self.mockScanning)
                guard !finished else { return }
                withAnimation(.spring(duration: 0.25)) { self.mockPhase = .success }
                try? await Task.sleep(for: Self.mockSuccess)
                finish(false)
            }
        }
        cancelMock = nil
        mockPhase = nil
        return !cancelled
    }

    func cancelMockSheet() { cancelMock?() }

    private func showOverlay() {
        guard overlay == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: MockFaceIDSheet(check: self))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.backgroundColor = .clear
        window.isHidden = false
        overlay = window
    }

    private func hideOverlay() {
        overlay?.isHidden = true
        overlay = nil
    }
}

/// The system Face ID HUD look-alike: a light rounded square with the glyph and "Face ID".
struct MockFaceIDSheet: View {
    let check: FaceIDCheck
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { check.cancelMockSheet() }
                .accessibilityLabel("Cancel Face ID")
                .accessibilityAddTraits(.isButton)
            VStack(spacing: 22) {
                ZStack {
                    if check.mockPhase == .success {
                        Image(systemName: "checkmark")
                            .font(.system(size: 64, weight: .regular))
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "faceid")
                            .font(.system(size: 72, weight: .light))
                            .symbolEffect(.pulse, options: .repeating)
                            .transition(.opacity)
                    }
                }
                .frame(height: 76)
                .foregroundStyle(Color(hex: 0x1C1C1E))
                Text("Face ID")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
            }
            .frame(width: 162, height: 162)
            .glassEffect(.regular.tint(.white.opacity(0.75)), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("faceid.sheet")
        }
        .onAppear { withAnimation(.spring(duration: 0.25)) { appeared = true } }
    }
}
