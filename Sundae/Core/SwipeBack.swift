import SwiftUI
import UIKit

/// Hiding the system navigation bar also switches off the edge swipe that pops a screen, because
/// UIKit's own gesture delegate refuses to start it without a bar. This installs a delegate that
/// allows the swipe whenever there is something to pop. Add it once to the root of each stack,
/// and with `false` to a screen that must not be swiped away.
extension View {
    func swipeBackEnabled(_ enabled: Bool = true) -> some View {
        background(SwipeBackInstaller(enabled: enabled))
    }
}

private struct SwipeBackInstaller: UIViewControllerRepresentable {
    var enabled: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.enabled = enabled
        controller.install()
    }

    final class Controller: UIViewController {
        var enabled = true
        private let gate = SwipeBackGate()

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            install()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            install()
        }

        func install() {
            guard let navigation = navigationController,
                  let gesture = navigation.interactivePopGestureRecognizer else { return }
            gate.navigation = navigation
            gate.enabled = enabled
            gesture.delegate = gate
            gesture.isEnabled = true
        }
    }
}

/// Lets the pop gesture begin only when the stack has a screen to go back to.
@MainActor
private final class SwipeBackGate: NSObject, UIGestureRecognizerDelegate {
    weak var navigation: UINavigationController?
    var enabled = true

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard enabled, let navigation else { return false }
        return navigation.viewControllers.count > 1
    }
}
