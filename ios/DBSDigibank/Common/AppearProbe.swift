import SwiftUI

/// Reports UIKit's viewDidAppear, which fires when the transition that brought the screen in has finished.
struct AppearProbe: UIViewControllerRepresentable {
    var onAppear: () -> Void

    func makeUIViewController(context: Context) -> Controller { Controller(onAppear: onAppear) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.onAppear = onAppear }

    final class Controller: UIViewController {
        var onAppear: () -> Void

        init(onAppear: @escaping () -> Void) {
            self.onAppear = onAppear
            super.init(nibName: nil, bundle: nil)
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onAppear()
        }
    }
}
