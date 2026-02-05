#if os(iOS)
import UIKit

final class PopoverOverlayWindow: UIWindow {
    weak var baseWindow: UIWindow?
    var passThroughPointPredicate: ((CGPoint) -> Bool)?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if passThroughPointPredicate?(point) == true {
            return false
        }
        return super.point(inside: point, with: event)
    }
}

final class PopoverOverlayWindows {
    static let shared = PopoverOverlayWindows()

    private var windows = [Weak<UIWindow>: PopoverOverlayWindow]()

    private init() {}

    func overlayWindow(for baseWindow: UIWindow) -> PopoverOverlayWindow {
        pruneDeallocatedWindows()
        if let existing = windows.first(where: { key, _ in key.pointee === baseWindow })?.value {
            return existing
        }
        let window: PopoverOverlayWindow
        if let windowScene = baseWindow.windowScene {
            window = PopoverOverlayWindow(windowScene: windowScene)
        } else {
            window = PopoverOverlayWindow(frame: baseWindow.bounds)
        }
        window.baseWindow = baseWindow
        window.windowLevel = max(baseWindow.windowLevel + 1, .alert + 1)
        window.backgroundColor = UIColor.clear
        let weakWindowReference = Weak(pointee: baseWindow)
        windows[weakWindowReference] = window
        return window
    }

    func removeOverlayWindow(for baseWindow: UIWindow) {
        let key = windows.keys.first(where: { $0.pointee === baseWindow })
        if let key, let window = windows[key] {
            window.isHidden = true
            window.rootViewController = nil
        }
        if let key {
            windows[key] = nil
        }
    }

    private func pruneDeallocatedWindows() {
        let keysToRemove = windows.keys.filter(\.isPointeeDeallocated)
        for key in keysToRemove {
            windows[key] = nil
        }
    }

    private final class Weak<T>: NSObject where T: AnyObject {
        private(set) weak var pointee: T?

        var isPointeeDeallocated: Bool {
            pointee == nil
        }

        init(pointee: T) {
            self.pointee = pointee
        }
    }
}
#endif
