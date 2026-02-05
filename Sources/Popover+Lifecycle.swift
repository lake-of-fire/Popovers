//
//  Popover+Lifecycle.swift
//  Popovers
//
//  Created by A. Zheng (github.com/aheze) on 1/4/22.
//  Copyright © 2022 A. Zheng. All rights reserved.
//
#if os(iOS)
import SwiftUI

/**
 Present a popover.
 */
public extension Popover {
    /**
     Present a popover in a window. It may be easier to use the `UIViewController.present(_:)` convenience method instead.
     */
    @MainActor
    internal func present(in window: UIWindow, forwardBaseTouchesTo: UIView?) {
        /// Use an overlay window to avoid reparenting issues in SwiftUI hosting hierarchies.
        let overlayWindow = PopoverOverlayWindows.shared.overlayWindow(for: window)
        let model = window.popoverModel
        let popoverViewController: PopoverContainerViewController

        if let existingPopoverViewController = overlayWindow.rootViewController as? PopoverContainerViewController {
            popoverViewController = existingPopoverViewController
        } else {
            popoverViewController = PopoverContainerViewController()
            overlayWindow.rootViewController = popoverViewController
        }

        popoverViewController.forwardBaseTouchesTo = forwardBaseTouchesTo ?? window.rootViewController?.view
        popoverViewController.overlayWindow = overlayWindow
        popoverViewController.baseWindow = window
        popoverViewController.isOverlayPresentation = true
        
        /// Hang on to the container for future dismiss/replace actions.
        context.presentedPopoverViewController = popoverViewController
        
        /**
         Add the popover to the container view.
         */
        let displayPopover: () -> Void = {
            model.add(self)
            
            /// Stop VoiceOver from reading out background views if `blocksBackgroundTouches` is true.
            if attributes.blocksBackgroundTouches {
                popoverViewController.view.accessibilityViewIsModal = true
            }
            
            /// Shift VoiceOver focus to the popover.
            if attributes.accessibility.shiftFocus {
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }

        context.presentationID = UUID()
        
        overlayWindow.isHidden = false
        overlayWindow.makeKeyAndVisible()
        displayPopover()

        if attributes.source == .stayAboveWindows {
            fatalError("stayAboveWindows removed until needed")
        }
    }

    /**
     Dismiss a popover.
     */
    func dismiss() {
        guard let presentingViewController = context.presentedPopoverViewController else { return }
        let tagDescription = attributes.tag.map { String(describing: $0) } ?? "nil"
        if presentingViewController.isOverlayPresentation {
            presentingViewController.teardownOverlayWindow()
        } else {
            presentingViewController.dismiss(animated: false)
        }

        /// Let the internal SwiftUI modifiers know that the popover was automatically dismissed.
        context.onAutoDismiss?()

        /// Let the client know that the popover was automatically dismissed.
        attributes.onDismiss?()
    }
}

public extension UIResponder {
    /// Replace a popover with another popover. Convenience method for `Popover.replace(with:)`.
//    func replace(_ oldPopover: Popover, with newPopover: Popover) {
//        oldPopover.replace(with: newPopover)
//    }

    /// Dismiss a popover. Convenience method for `Popover.dismiss()`.
    func dismiss(_ popover: Popover) {
        popover.dismiss()
    }

    /**
     Get a currently-presented popover with a tag. Returns `nil` if no popover with the tag was found.
     - parameter tag: The tag of the popover to look for.
     */
//    func popover(tagged tag: AnyHashable) -> Popover? {
//        return popoverModel.popover(tagged: tag)
//    }

    /**
     Remove all popovers, or optionally the ones tagged with a `tag` that you supply.
     - parameter tag: If this isn't nil, only remove popovers tagged with this.
     */
//    func dismissAllPopovers(with tag: AnyHashable? = nil) {
//        popoverModel.removeAllPopovers(with: tag)
//    }
}

//public extension UIViewController {
//    /// Present a `Popover` using this `UIViewController` as its presentation context.
//    func present(_ popover: Popover) {
//        guard let window = view.window else { return }
//        popover.present(in: window)
//    }
//}

extension UIApplication {
    var mainKeyWindow: UIWindow? {
        if #available(iOS 13, *) {
            return UIApplication.shared.connectedScenes
                .filter { $0.activationState == .foregroundActive }
                .first(where: { $0 is UIWindowScene })
                .flatMap { $0 as? UIWindowScene }?.windows
                .first(where: \.isKeyWindow)
        } else {
            return UIApplication.shared.windows.first { $0.isKeyWindow }
        }
    }
    
    var rootViewController: UIViewController? {
        guard let keyWindow = UIApplication.shared.mainKeyWindow,
              let rootViewController = keyWindow.rootViewController else {
            return nil
        }
        return rootViewController
    }
    
    func topViewController(controller: UIViewController? = nil) -> UIViewController? {
        var current = controller ?? rootViewController
        while true {
            if let nav = current as? UINavigationController, let visible = nav.visibleViewController {
                current = visible
            } else if let tab = current as? UITabBarController, let selected = tab.selectedViewController {
                current = selected
            } else if let presented = current?.presentedViewController {
                current = presented
            } else {
                break
            }
        }
        return current
    }
}

#endif
