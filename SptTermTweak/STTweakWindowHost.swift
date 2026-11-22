import UIKit
import SwiftUI

// -----------------------------------------------------------------------------
// STTweakWindow: Passthrough touches when collapsed; full interaction when expanded
// -----------------------------------------------------------------------------
final class STTweakWindow: UIWindow {
    weak var tweakVC: STTweakViewController?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else {
            return nil
        }

        if let vc = tweakVC, vc.isExpanded {
            return super.hitTest(point, with: event)
        }

        if let pill = tweakVC?.launchPill, !pill.isHidden, pill.alpha > 0.01, pill.isUserInteractionEnabled {
            if let pillSuper = pill.superview {
                let p = pillSuper.convert(point, from: self)
                let hitRect = pill.frame.insetBy(
                    dx: min(0, (pill.frame.width - 44) / 2),
                    dy: min(0, (pill.frame.height - 44) / 2)
                )
                if hitRect.contains(p) {
                    return pill
                }
            }
        }

        return nil
    }
}

// -----------------------------------------------------------------------------
// STTweakPassthroughView
// -----------------------------------------------------------------------------
final class STTweakPassthroughView: UIView {
    weak var tweakVC: STTweakViewController?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else {
            return nil
        }

        if let vc = tweakVC, vc.isExpanded {
            return super.hitTest(point, with: event)
        }

        if let pill = tweakVC?.launchPill, !pill.isHidden, pill.alpha > 0.01, pill.isUserInteractionEnabled {
            let hitRect = pill.frame.insetBy(
                dx: min(0, (pill.frame.width - 44) / 2),
                dy: min(0, (pill.frame.height - 44) / 2)
            )
            if hitRect.contains(point) {
                return pill
            }
        }

        return nil
    }
}

// -----------------------------------------------------------------------------
// STTweakTerminalRootView: SwiftUI wrapper hosting STRootGate + CRT [ _ MINIMIZE ]
// -----------------------------------------------------------------------------
struct STTweakTerminalRootView: View {
    @EnvironmentObject private var theme: TerminalTheme
    var onMinimize: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            STRootGate()

            // CRT styled minimize button in top bar
            Button(action: {
                TermHaptic.tap()
                onMinimize()
            }) {
                Text("[ _ MINIMIZE ]")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.palette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.palette.background.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(theme.palette.accent.opacity(0.8), lineWidth: 1)
                    )
            }
            .padding(.trailing, 12)
            .padding(.top, 6)
            .zIndex(9999)
        }
    }
}

// -----------------------------------------------------------------------------
// STTweakViewController: Manages floating pill & expanded SwiftUI hosting controller
// -----------------------------------------------------------------------------
final class STTweakViewController: UIViewController {
    var launchPill: UIButton?
    var hostingController: UIHostingController<AnyView>?
    var isExpanded: Bool = false
    var didPan: Bool = false
    weak var previousKeyWindow: UIWindow?

    private let env = ServiceEnvironment.forTweak()
    private let tweakDefaults = UserDefaults(suiteName: "com.aditya.sptterm.tweak") ?? .standard
    private lazy var theme = TerminalTheme(storage: UserDefaultsThemeStorage(defaults: tweakDefaults))

    override func loadView() {
        let passView = STTweakPassthroughView(frame: UIScreen.main.bounds)
        passView.backgroundColor = .clear
        passView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        passView.tweakVC = self
        self.view = passView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupFloatingPill()
    }

    private func setupFloatingPill() {
        let btn = UIButton(type: .custom)
        let pillW: CGFloat = 120.0
        let pillH: CGFloat = 36.0

        let savedX = tweakDefaults.double(forKey: "sptterm.tweak.pill.x")
        let savedY = tweakDefaults.double(forKey: "sptterm.tweak.pill.y")
        var originX = view.bounds.width - pillW - 12
        var originY: CGFloat = 120
        if savedX > 0 && savedY > 0 {
            originX = max(4, min(view.bounds.width - pillW - 4, CGFloat(savedX) - pillW / 2))
            originY = max(30, min(view.bounds.height - pillH - 20, CGFloat(savedY) - pillH / 2))
        }

        btn.frame = CGRect(x: originX, y: originY, width: pillW, height: pillH)
        btn.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]

        btn.setTitle("[ >_ SPT.TERM ]", for: .normal)
        btn.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        btn.setTitleColor(UIColor(red: 0.0, green: 1.0, blue: 0.5, alpha: 1.0), for: .normal)
        btn.setTitleColor(UIColor(red: 0.0, green: 0.7, blue: 0.3, alpha: 0.6), for: .highlighted)
        btn.backgroundColor = UIColor(white: 0.02, alpha: 0.92)
        btn.layer.cornerRadius = 4.0
        btn.layer.borderWidth = 1.0
        btn.layer.borderColor = UIColor(red: 0.0, green: 0.8, blue: 0.4, alpha: 0.8).cgColor
        btn.layer.shadowColor = UIColor(red: 0.0, green: 1.0, blue: 0.4, alpha: 0.4).cgColor
        btn.layer.shadowRadius = 4.0
        btn.layer.shadowOpacity = 0.8
        btn.layer.shadowOffset = .zero

        btn.addTarget(self, action: #selector(handlePillTap), for: .touchUpInside)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        btn.addGestureRecognizer(pan)

        view.addSubview(btn)
        self.launchPill = btn
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let pill = launchPill else { return }
        switch pan.state {
        case .began:
            didPan = false
        case .changed:
            let translation = pan.translation(in: view)
            if abs(translation.x) > 3.0 || abs(translation.y) > 3.0 {
                didPan = true
            }
            var center = pill.center
            center.x += translation.x
            center.y += translation.y

            let halfW = pill.bounds.width / 2.0
            let halfH = pill.bounds.height / 2.0
            center.x = max(halfW + 4, min(view.bounds.width - halfW - 4, center.x))
            center.y = max(halfH + 30, min(view.bounds.height - halfH - 20, center.y))
            pill.center = center
            pan.setTranslation(.zero, in: view)
        case .ended, .cancelled:
            tweakDefaults.set(Double(pill.center.x), forKey: "sptterm.tweak.pill.x")
            tweakDefaults.set(Double(pill.center.y), forKey: "sptterm.tweak.pill.y")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.didPan = false
            }
        default:
            break
        }
    }

    @objc private func handlePillTap() {
        if didPan {
            didPan = false
            return
        }
        expandToTerminal()
    }

    func expandToTerminal() {
        guard !isExpanded else { return }

        // Capture currently key window
        var currentKey: UIWindow?
        for scene in UIApplication.shared.connectedScenes {
            if let ws = scene as? UIWindowScene {
                for w in ws.windows where w != view.window && w.isKeyWindow {
                    currentKey = w
                    break
                }
            }
            if currentKey != nil { break }
        }
        self.previousKeyWindow = currentKey
        self.view.window?.makeKey()

        self.isExpanded = true
        self.launchPill?.isHidden = true

        let rootView = AnyView(
            STTweakTerminalRootView(onMinimize: { [weak self] in
                self?.collapseToPill()
            })
            .environmentObject(env)
            .environmentObject(theme)
        )

        let hc = UIHostingController(rootView: rootView)
        hc.view.frame = view.bounds
        hc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hc.view.backgroundColor = UIColor(red: 0.02, green: 0.04, blue: 0.02, alpha: 1.0)

        addChild(hc)
        view.addSubview(hc.view)
        hc.didMove(toParent: self)
        self.hostingController = hc
        STPerfLogger.shared.currentScreen = "terminal"

        NSLog("[SptTermTweak] Expanded full-screen terminal window")
    }

    func collapseToPill() {
        guard isExpanded else { return }

        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil

        self.launchPill?.isHidden = false
        self.isExpanded = false
        STPerfLogger.shared.currentScreen = "pill"

        if let prev = previousKeyWindow {
            prev.makeKey()
            self.previousKeyWindow = nil
        }

        NSLog("[SptTermTweak] Collapsed back to floating launch pill")
    }
}

// -----------------------------------------------------------------------------
// STTweakWindowHost Entry
// -----------------------------------------------------------------------------
@objc(STTweakWindowHost)
final class STTweakWindowHost: NSObject {
    private static var tweakWindow: STTweakWindow?

    @objc static func install() {
        DispatchQueue.main.async {
            guard tweakWindow == nil else { return }

            var targetScene: UIWindowScene?
            for scene in UIApplication.shared.connectedScenes {
                if let ws = scene as? UIWindowScene {
                    if ws.activationState == .foregroundActive {
                        targetScene = ws
                        break
                    }
                    if targetScene == nil {
                        targetScene = ws
                    }
                }
            }

            guard let scene = targetScene else {
                NSLog("[SptTermTweak] No UIWindowScene found, retrying in 1.0s")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    install()
                }
                return
            }

            NSLog("[SptTermTweak] Installing tweak window on scene: %@", scene)

            let window = STTweakWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.windowLevel = UIWindow.Level.alert + 10.0
            window.backgroundColor = .clear

            let vc = STTweakViewController()
            window.rootViewController = vc
            window.tweakVC = vc

            window.isHidden = false
            tweakWindow = window

            NSLog("[SptTermTweak] Tweak overlay window active (level %.1f, launch pill ready)", window.windowLevel.rawValue)
        }
    }
}

extension ServiceEnvironment {
    static func forTweak() -> ServiceEnvironment {
        let player = STInProcessPlayerService()
        let library = STSessionLibraryService.shared
        let auth = MockAuthService(isAuthorized: true)
        let audioTweaks = STAudioTweaksService()
        let artwork = STInProcessArtworkService.shared
        return ServiceEnvironment(
            player: player,
            library: library,
            auth: auth,
            audioTweaks: audioTweaks,
            artwork: artwork
        )
    }
}

