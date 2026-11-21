import SwiftUI
import UIKit

/// Owns the floating trigger and the SptTerm content window.
@MainActor
final class STWindowHost {
    static let shared = STWindowHost()

    private var contentWindow: UIWindow?
    private var triggerWindow: UIWindow?
    private var isPresented = false

    func install() {
        guard triggerWindow == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first else { return }

        let button = UIButton(type: .system)
        button.setTitle(">_", for: .normal)
        button.titleLabel?.font = .monospacedSystemFont(ofSize: 16, weight: .bold)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        button.layer.cornerRadius = 22
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.green.withAlphaComponent(0.6).cgColor
        button.addTarget(self, action: #selector(present), for: .touchUpInside)

        let host = UIViewController()
        host.view.backgroundColor = .clear
        host.view.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: host.view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: host.view.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])

        let side: CGFloat = 56
        let bounds = scene.coordinateSpace.bounds

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(
            x: bounds.width - side - 8,
            y: bounds.midY,
            width: side,
            height: side
        )
        window.rootViewController = host
        window.backgroundColor = .clear
        window.windowLevel = .alert + 1
        window.isHidden = false
        triggerWindow = window
    }

    @objc private func present() {
        guard !isPresented, let scene = triggerWindow?.windowScene else { return }

        let root = UIHostingController(
            rootView: STRootGate().environmentObject(TerminalTheme())
        )
        let window = UIWindow(windowScene: scene)
        window.rootViewController = root
        window.windowLevel = .alert + 2
        window.isHidden = false

        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(dismiss))
        swipe.direction = .down
        root.view.addGestureRecognizer(swipe)

        contentWindow = window
        isPresented = true
    }

    @objc private func dismiss() {
        contentWindow?.isHidden = true
        contentWindow = nil
        isPresented = false
    }
}
