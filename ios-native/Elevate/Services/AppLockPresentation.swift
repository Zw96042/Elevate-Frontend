import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

/// A scene-local cover above sheets and full-screen presentations. Keeping the
/// app's original window mounted preserves navigation while the lock is shown.
struct AppLockPresentation<Content: View>: UIViewRepresentable {
    var store: AppLockStore
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(store: store, content: content()) }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.isUserInteractionEnabled = false
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(_ view: AttachmentView, context: Context) {
        context.coordinator.content = content()
        context.coordinator.host?.rootView = context.coordinator.content
        context.coordinator.attach(to: view.window)
        context.coordinator.synchronize()
    }

    static func dismantleUIView(_ view: AttachmentView, coordinator: Coordinator) {
        view.onWindowChanged = nil
        coordinator.detach()
    }

    final class AttachmentView: UIView {
        var onWindowChanged: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChanged?(window)
        }
    }

    @MainActor final class Coordinator: NSObject, AppLockCoverUpdating {
        let store: AppLockStore
        var content: Content
        weak var sourceWindow: UIWindow?
        var coverWindow: UIWindow?
        var host: UIHostingController<Content>?
        private var backdropView: UIImageView?
        private var hasShownUncoveredContent = false
        private var originalWindowState: (alpha: CGFloat, interactive: Bool, accessibilityHidden: Bool)?

        init(store: AppLockStore, content: Content) {
            self.store = store
            self.content = content
            super.init()
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(sceneWillDeactivate), name: UIScene.willDeactivateNotification, object: nil)
            center.addObserver(self, selector: #selector(sceneDidEnterBackground), name: UIScene.didEnterBackgroundNotification, object: nil)
            center.addObserver(self, selector: #selector(sceneDidActivate), name: UIScene.didActivateNotification, object: nil)
            center.addObserver(self, selector: #selector(sceneDidDisconnect), name: UIScene.didDisconnectNotification, object: nil)
            center.addObserver(self, selector: #selector(transparencyPreferenceChanged), name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        func attach(to window: UIWindow?) {
            // A full-screen presentation may temporarily detach the presenting
            // SwiftUI view. Keep protecting its scene until a real dismantle or
            // scene disconnect, including while onboarding is presented.
            guard let window, let scene = window.windowScene else { return }
            guard window !== sourceWindow else { return }
            detach()
            sourceWindow = window
            let host = UIHostingController(rootView: content)
            host.view.backgroundColor = .clear
            host.view.isOpaque = false
            let container = UIViewController()
            container.view.backgroundColor = .systemBackground
            let backdrop = UIImageView(frame: container.view.bounds)
            backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            backdrop.contentMode = .scaleAspectFill
            backdrop.clipsToBounds = true
            backdrop.isUserInteractionEnabled = false
            backdrop.accessibilityElementsHidden = true
            container.view.addSubview(backdrop)
            container.addChild(host)
            host.view.frame = container.view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.view.addSubview(host.view)
            host.didMove(toParent: container)
            let cover = UIWindow(windowScene: scene)
            cover.frame = scene.coordinateSpace.bounds
            cover.windowLevel = .alert + 1
            cover.backgroundColor = .systemBackground
            cover.rootViewController = container
            cover.accessibilityViewIsModal = true
            cover.accessibilityIdentifier = "app.lock.cover"
            self.host = host
            backdropView = backdrop
            coverWindow = cover
            store.privacyCover = self
            switch scene.activationState {
            case .foregroundActive: store.scenePhaseChanged(.active)
            case .background, .unattached: store.scenePhaseChanged(.background)
            default: store.scenePhaseChanged(.inactive)
            }
            synchronize()
        }

