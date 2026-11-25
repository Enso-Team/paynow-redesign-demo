import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

@main
struct DBSDigibankApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        ZStack {
            switch app.phase {
            case .setup:
                SetupView()
                    .preferredColorScheme(.light)
            case .signedOut:
                EntryView()
                    .preferredColorScheme(.dark)
                    .transition(.opacity)
            case .signedIn:
                TabShell()
                    .preferredColorScheme(.light)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.phase)
        .overlay {
            if let stage = app.stage, stage != .paySkeleton { LoadingStageView(stage: stage).transition(.opacity) }
        }
        .fullScreenCover(item: $app.journey, onDismiss: { app.journeyDismissed() }) { _ in
            JourneyView()
                .environment(app)
                .preferredColorScheme(.light)
        }
        .overlay(alignment: .top) {
            if let toast = app.toast {
                ToastView(text: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: app.toast)
        .background(WindowTouchHook { app.userInteracted() })
    }
}

/// Watches every touch in the app's window without taking it, so any tap counts as activity.
/// Sheets and full-screen covers live in the same window.
struct WindowTouchHook: UIViewRepresentable {
    var onTouch: () -> Void

    func makeUIView(context: Context) -> HookView { HookView(onTouch: onTouch) }
    func updateUIView(_ uiView: HookView, context: Context) { uiView.onTouch = onTouch }

    final class HookView: UIView {
        var onTouch: () -> Void
        private var installed: UIGestureRecognizer?

        init(onTouch: @escaping () -> Void) {
            self.onTouch = onTouch
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, installed == nil else { return }
            let recognizer = TouchWatcher { [weak self] in self?.onTouch() }
            window.addGestureRecognizer(recognizer)
            installed = recognizer
        }
    }

    /// Sees touches begin, then fails at once so it never claims or delays them.
    final class TouchWatcher: UIGestureRecognizer {
        private let onTouch: () -> Void

        init(onTouch: @escaping () -> Void) {
            self.onTouch = onTouch
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            onTouch()
            state = .failed
        }

        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }
}

struct ToastView: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: Capsule())
            .padding(.horizontal, 20)
            .accessibilityIdentifier("toast")
    }
}
