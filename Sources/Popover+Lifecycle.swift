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
    internal func present(in window: UIWindow, forwardBaseTouchesTo: UIView?) {
        /// Locate the topmost presented `UIViewController` in this window. We'll be presenting on top of this one.
        let presentingViewController = UIApplication.shared.topViewController(controller: window.rootViewController)
        
        /// There may already be a view controller presenting another popover - if so, let's use that.
        let popoverViewController: PopoverContainerViewController
        
        /// Get the popover model that's tied to the window.
        let model = window.popoverModel

        if let existingPopoverViewController = presentingViewController as? PopoverContainerViewController {
            popoverViewController = existingPopoverViewController
        } else {
            popoverViewController = PopoverContainerViewController()
        }
        
        popoverViewController.forwardBaseTouchesTo = forwardBaseTouchesTo
        
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
        
        if presentingViewController === popoverViewController {
            displayPopover()
        } else {
            /**
             If we've prepared a new controller to present, then do so.
             This isn't animated as we perform the popover animation inside the container view instead -
             the view controller hosts the container that animates.
             */
            presentingViewController?.present(popoverViewController, animated: false, completion: displayPopover)
        }

        if attributes.source == .stayAboveWindows {
            fatalError("stayAboveWindows removed until needed")
        }
    }

    /**
     Dismiss a popover.
     */
    func dismiss() {
        guard let presentingViewController = context.presentedPopoverViewController else { return }
        presentingViewController.dismiss(animated: false)

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
        
        if controller == nil {
            return topViewController(controller: rootViewController)
        }
        
        if let navigationController = controller as? UINavigationController {
            return topViewController(controller: navigationController.visibleViewController)
        }
        
        if let tabController = controller as? UITabBarController,
           let selectedViewController = tabController.selectedViewController {
            return topViewController(controller: selectedViewController)
        }
        
        if let presentedViewController = controller?.presentedViewController {
            return topViewController(controller: presentedViewController)
        }
        
        return controller
    }
}

#endif
