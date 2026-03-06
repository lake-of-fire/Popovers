//
//  Popover+Lifecycle.swift
//  Popovers
//
//  Created by A. Zheng (github.com/aheze) on 1/4/22.
//  Copyright © 2022 A. Zheng. All rights reserved.
//
#if os(iOS)
import Foundation
import SwiftUI

@inline(__always)
private func lookupOpenPopoverLog(_ stage: String, _ metadata: [String: Any] = [:]) {
    #if DEBUG
    let allowedStages: Set<String> = [
        "popovers.lifecycle.present.begin",
        "popovers.lifecycle.present.containerReady",
        "popovers.lifecycle.present.displayed",
        "popovers.lifecycle.dismiss.begin",
        "popovers.lifecycle.dismiss.done"
    ]
    guard allowedStages.contains(stage) else { return }
    var payload = metadata
    payload["stage"] = stage
    payload["uptimeMs"] = DispatchTime.now().uptimeNanoseconds / 1_000_000
    Swift.debugPrint("# LOOKUPOPEN", payload)
    #endif
}

/**
 Present a popover.
 */
public extension Popover {
    /**
     Present a popover in a window. It may be easier to use the `UIViewController.present(_:)` convenience method instead.
     */
    @MainActor
    internal func present(in window: UIWindow, forwardBaseTouchesTo: UIView?) {
        let startedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        let tagDescription = attributes.tag.map { String(describing: $0) } ?? "nil"
        lookupOpenPopoverLog(
            "popovers.lifecycle.present.begin",
            [
                "tag": tagDescription,
                "window": String(describing: ObjectIdentifier(window)),
                "hasForwardBaseTouchesTo": forwardBaseTouchesTo != nil,
                "windowLevel": window.windowLevel.rawValue,
                "windowHidden": window.isHidden,
                "windowKey": window.isKeyWindow
            ]
        )
        /// Use an overlay window to avoid reparenting issues in SwiftUI hosting hierarchies.
        let overlayWindow = PopoverOverlayWindows.shared.overlayWindow(for: window)
        let model = window.popoverModel
        let popoverViewController: PopoverContainerViewController
        let reusedController: Bool

        if let existingPopoverViewController = overlayWindow.rootViewController as? PopoverContainerViewController {
            popoverViewController = existingPopoverViewController
            reusedController = true
        } else {
            popoverViewController = PopoverContainerViewController()
            overlayWindow.rootViewController = popoverViewController
            reusedController = false
        }
        lookupOpenPopoverLog(
            "popovers.lifecycle.present.containerReady",
            [
                "tag": tagDescription,
                "reusedController": reusedController,
                "controller": String(describing: ObjectIdentifier(popoverViewController)),
                "overlayWindow": String(describing: ObjectIdentifier(overlayWindow)),
                "overlayWindowLevel": overlayWindow.windowLevel.rawValue,
                "overlayWindowHidden": overlayWindow.isHidden,
                "rootViewController": String(describing: type(of: overlayWindow.rootViewController as Any))
            ]
        )

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
        if let initialContextSize = attributes.initialContextSize,
           initialContextSize.width.isFinite,
           initialContextSize.height.isFinite,
           initialContextSize.width > 0,
           initialContextSize.height > 0
        {
            updateFrame(with: initialContextSize)
            context.isOffsetInitialized = true
        }
        displayPopover()
        lookupOpenPopoverLog(
            "popovers.lifecycle.present.displayed",
            [
                "tag": tagDescription,
                "presentationID": context.presentationID.uuidString,
                "elapsedMs": Int((DispatchTime.now().uptimeNanoseconds - startedAtUptimeNanoseconds) / 1_000_000),
                "reusedController": reusedController,
                "overlayWindowHidden": overlayWindow.isHidden,
                "overlayWindowLevel": overlayWindow.windowLevel.rawValue,
                "overlayWindowKey": overlayWindow.isKeyWindow,
                "baseWindowKey": window.isKeyWindow,
                "frame": NSCoder.string(for: context.frame),
                "staticFrame": NSCoder.string(for: context.staticFrame)
            ]
        )

        if attributes.source == .stayAboveWindows {
            fatalError("stayAboveWindows removed until needed")
        }
    }

    /**
     Dismiss a popover.
     */
    @MainActor
    func dismiss() {
        guard let presentingViewController = context.presentedPopoverViewController else { return }
        let popoverModel = presentingViewController.view.popoverModel
        let startedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        let tagDescription = attributes.tag.map { String(describing: $0) } ?? "nil"
        lookupOpenPopoverLog(
            "popovers.lifecycle.dismiss.begin",
            [
                "tag": tagDescription,
                "isOverlayPresentation": presentingViewController.isOverlayPresentation,
                "preservesOverlayWindowOnDismiss": attributes.preservesOverlayWindowOnDismiss
            ]
        )
        if presentingViewController.isOverlayPresentation {
            presentingViewController.teardownOverlayWindow(
                preserveRootViewController: attributes.preservesOverlayWindowOnDismiss
            )
        } else {
            presentingViewController.dismiss(animated: false)
        }
        popoverModel.popover = nil

        /// Let the internal SwiftUI modifiers know that the popover was automatically dismissed.
        context.onAutoDismiss?()

        /// Let the client know that the popover was automatically dismissed.
        attributes.onDismiss?()
        lookupOpenPopoverLog(
            "popovers.lifecycle.dismiss.done",
            [
                "tag": tagDescription,
                "elapsedMs": Int((DispatchTime.now().uptimeNanoseconds - startedAtUptimeNanoseconds) / 1_000_000)
            ]
        )
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
