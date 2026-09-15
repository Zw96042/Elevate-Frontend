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

        func synchronize() {
            guard let sourceWindow, let coverWindow else { return }
            let shouldCover = store.isContentCovered
            if shouldCover {
                if originalWindowState == nil {
                    originalWindowState = (sourceWindow.alpha, sourceWindow.isUserInteractionEnabled, sourceWindow.accessibilityElementsHidden)
                    // Only sample a window the user has already seen. Cold
                    // starts and already-hidden content use the opaque base.
                    if hasShownUncoveredContent {
                        backdropView?.image = AppLockBackdrop.image(from: sourceWindow)
                    }
                    sourceWindow.endEditing(true)
                }
                if UIAccessibility.isReduceTransparencyEnabled { backdropView?.image = nil }
                updateBackdropDiagnostic()
                // Hide the source window itself as well, so presented sheets,
                // accessibility, hardware keyboard actions and snapshots cannot
                // expose or interact with a covered screen.
                sourceWindow.alpha = 0
                sourceWindow.isUserInteractionEnabled = false
                sourceWindow.accessibilityElementsHidden = true
                if coverWindow.isHidden {
                    coverWindow.makeKeyAndVisible()
                    coverWindow.layoutIfNeeded()
                    UIAccessibility.post(notification: .screenChanged, argument: host?.view)
                }
            } else {
                backdropView?.image = nil
                updateBackdropDiagnostic()
                restoreSourceWindow()
                coverWindow.isHidden = true
                if !sourceWindow.isHidden, sourceWindow.alpha > 0 {
                    hasShownUncoveredContent = true
                }
            }
        }

        func detach() {
            backdropView?.image = nil
            backdropView = nil
            hasShownUncoveredContent = false
            restoreSourceWindow()
            coverWindow?.isHidden = true
            coverWindow?.rootViewController = nil
            coverWindow = nil
            host = nil
            sourceWindow = nil
            if store.privacyCover === self { store.privacyCover = nil }
        }

        private func restoreSourceWindow() {
            guard let sourceWindow, let originalWindowState else { return }
            sourceWindow.alpha = originalWindowState.alpha
            sourceWindow.isUserInteractionEnabled = originalWindowState.interactive
            sourceWindow.accessibilityElementsHidden = originalWindowState.accessibilityHidden
            if coverWindow?.isKeyWindow == true { sourceWindow.makeKey() }
            self.originalWindowState = nil
        }

        private func belongsToScene(_ notification: Notification) -> Bool {
            (notification.object as? UIScene) === sourceWindow?.windowScene
        }

        @objc private func transparencyPreferenceChanged() {
            // Never recover a backdrop by sampling an already-covered window.
            // Turning transparency back on waits for the next visible session.
            if UIAccessibility.isReduceTransparencyEnabled { backdropView?.image = nil }
            updateBackdropDiagnostic()
        }

        private func updateBackdropDiagnostic() {
#if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("-SampleData"), arguments.contains("-AppLockPreview") else { return }
            // Synthetic runtime verification only; exposes no image or account data.
            guard let pixels = backdropView?.image?.cgImage else {
                coverWindow?.accessibilityValue = "No contextual backdrop"
                return
            }
            switch AppLockBackdrop.hasColorVariation(pixels) {
            case true?: coverWindow?.accessibilityValue = "Blurred backdrop present-varied"
            case false?: coverWindow?.accessibilityValue = "Blurred backdrop present-flat"
            case nil: coverWindow?.accessibilityValue = "Blurred backdrop present"
            }
#endif
        }

        @objc private func sceneWillDeactivate(_ notification: Notification) {
            guard belongsToScene(notification) else { return }
            store.scenePhaseChanged(.inactive)
        }

        @objc private func sceneDidEnterBackground(_ notification: Notification) {
            guard belongsToScene(notification) else { return }
            store.scenePhaseChanged(.background)
        }

        @objc private func sceneDidActivate(_ notification: Notification) {
            guard belongsToScene(notification) else { return }
            store.scenePhaseChanged(.active)
        }

        @objc private func sceneDidDisconnect(_ notification: Notification) {
            guard belongsToScene(notification) else { return }
            store.scenePhaseChanged(.background)
            detach()
        }
    }
}

/// Keeps only coarse colors, never a screen-sized screenshot. The visible view
/// hierarchy draws into at most 2,304 pixels, then those pixels are blurred before
/// any image is installed in the cover. Nothing is saved, logged or encoded.
@MainActor private enum AppLockBackdrop {
    private static let context = CIContext(options: [
        .useSoftwareRenderer: true,
        .cacheIntermediates: false,
    ])

#if DEBUG
    /// Inspect only the already-blurred thumbnail, never the source screen.
    /// A two-level tolerance ignores RGB conversion/rounding noise.
    static func hasColorVariation(_ image: CGImage) -> Bool? {
        guard image.width > 0, image.width <= 32,
              image.height > 0, image.height <= 72 else { return nil }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        return bytes.withUnsafeMutableBytes { buffer -> Bool? in
            guard let graphics = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return nil }
            graphics.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            var minimum = [UInt8](repeating: 255, count: 3)
            var maximum = [UInt8](repeating: 0, count: 3)
            for pixel in stride(from: 0, to: buffer.count, by: 4) {
                for channel in 0..<3 {
                    minimum[channel] = min(minimum[channel], buffer[pixel + channel])
                    maximum[channel] = max(maximum[channel], buffer[pixel + channel])
                }
            }
            return (0..<3).contains { Int(maximum[$0]) - Int(minimum[$0]) > 2 }
        }
    }
#endif

    static func image(from window: UIWindow) -> UIImage? {
        guard !UIAccessibility.isReduceTransparencyEnabled,
              !window.isHidden, window.alpha > 0,
              window.bounds.width > 0, window.bounds.height > 0 else { return nil }
        return autoreleasepool {
            let bounds = window.bounds
            let scale = min(32 / bounds.width, 72 / bounds.height)
            let size = CGSize(width: max(1, floor(bounds.width * scale)),
                              height: max(1, floor(bounds.height * scale)))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            format.preferredRange = .standard
            var isComplete = false
            let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                UIColor.systemBackground.setFill()
                renderer.fill(CGRect(origin: .zero, size: size))
                let graphics = renderer.cgContext
                graphics.interpolationQuality = .high
                graphics.scaleBy(x: size.width / bounds.width, y: size.height / bounds.height)
                graphics.translateBy(x: -bounds.minX, y: -bounds.minY)
                // Draw the current onscreen hierarchy, including composited
                // SwiftUI content, directly into this tiny context. Waiting for
                // updates could incorporate the lock's hidden source state.
                isComplete = window.drawHierarchy(in: bounds, afterScreenUpdates: false)
            }
            // Partial captures use the opaque fallback, never a larger image.
            guard isComplete, let input = CIImage(image: thumbnail) else { return nil }
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = input.clampedToExtent()
            blur.radius = 3
            guard let output = blur.outputImage?.cropped(to: input.extent),
                  let pixels = context.createCGImage(output, from: input.extent) else { return nil }
            return UIImage(cgImage: pixels)
        }
    }
}
