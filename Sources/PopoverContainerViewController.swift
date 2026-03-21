#if os(iOS)
//  PopoverContainerViewController.swift
//  Popovers
//
//  Created by A. Zheng (github.com/aheze) on 12/23/21.
//  Copyright © 2021 A. Zheng. All rights reserved.
//

import SwiftUI

/**
 The View Controller that hosts `PopoverContainerView`. This is automatically managed.
 */
//public class PopoverContainerViewController: UIViewController {
public class PopoverContainerViewController: HostingParentController {
    /// The `UIView` used to handle gesture interactions for popovers.
    private var popoverGestureContainerView: PopoverGestureContainer?
    
    /// If this is nil, the view hasn't been laid out yet.
    var previousBounds: CGRect?
    
    /**
     Create a new `PopoverContainerViewController`. This is automatically managed.
     */
    public init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }
    
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        /// Only update frames on a bounds change.
        if let previousBounds = previousBounds, previousBounds != view.bounds {
            /// Orientation or screen bounds changed, so update popover frames.
            Task { @MainActor [weak self] in
                self?.popoverModel.updateFramesAfterBoundsChange()
            }
        }
        
        /// Store the bounds for later.
        previousBounds = view.bounds
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        
//    override public func loadView() {
        popoverGestureContainerView = PopoverGestureContainer(windowAvailable: { [unowned self] window in
            /// Embed `PopoverContainerView` in a view controller.
            let popoverContainerView = PopoverContainerView(popoverModel: popoverModel)
                .environment(\.window, window)
            
            let hostingController = UIHostingController(rootView: popoverContainerView)
            hostingController.view.frame = view.bounds
            hostingController.view.backgroundColor = .clear
            hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            
            hostingController.willMove(toParent: self)
            addChild(hostingController)
            view.addSubview(hostingController.view)
            hostingController.didMove(toParent: self)
        })
        
        makeBackgroundsClear = false
        if let popoverGestureContainerView {
            popoverGestureContainerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(popoverGestureContainerView)
        }
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        /// Use the presenting view controller's view as the next element in the gesture container's responder chain
        /// when a hit test indicates no popover was tapped.
        popoverGestureContainerView?.presentingViewGestureTarget = presentingViewController?.view
    }
    
    override public func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
    }
    
    @objc private func keyboardWillShow(notification: Notification) {
        Task { @MainActor [weak self] in
            self?.popoverModel.updateFramesAfterBoundsChange()
        }
    }
    
    @objc private func keyboardWillHide(notification: Notification) {
        Task { @MainActor [weak self] in
            self?.popoverModel.updateFramesAfterBoundsChange()
        }
    }

    @MainActor
    public func refreshPopoverFrames() {
        popoverModel.updateFramesAfterBoundsChange()
    }

    @MainActor
    public func updatePresentedPopoverAttributes(_ update: (inout Popover.Attributes) -> Void) {
        guard var popover = popoverModel.popover else { return }
        var attributes = popover.attributes
        update(&attributes)
        popover.attributes = attributes
        popoverModel.popover = popover
    }

    private class PopoverGestureContainer: UIView {
        private let windowAvailable: (UIWindow) -> Void
        
        /// The `UIView` to forward hit tests to when a check fails in this view.
        weak var presentingViewGestureTarget: UIView?
        
        init(windowAvailable: @escaping (UIWindow) -> Void) {
            self.windowAvailable = windowAvailable
            super.init(frame: .zero)
        }
        
        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func didMoveToWindow() {
            super.didMoveToWindow()
            
            if let window {
                windowAvailable(window)
            }
        }
        
        /**
         Determine if touches should land on popovers or pass through to the underlying view.
         The popover container view takes up the entire screen, so normally it would block all touches from going through. This method fixes that.
         */
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            /// Make sure the hit event was actually a touch and not a cursor hover or something else.
            guard event.map({ $0.type == .touches }) ?? true else { return nil }
            
            /// Only loop through the popovers that are in this window.
//            let popovers = popoverModel.popovers
            
            /// The current popover's frame.
            /// Recalculate it on demand so hit-testing stays aligned when the keyboard
            /// changes safe-area-driven positioning before the cached context frame settles.
//            let popoverFrames = popovers.map { $0.context.frame }
            let popoverFrame = popoverModel.popover.map { popover in
                popover.calculateFrame(from: popover.context.size)
            }
            let cachedPopoverFrame = popoverModel.popover?.context.frame

            func logLookupKeyboard(
                _ stage: String,
                popover: Popover?,
                excludedFrames: [CGRect] = [],
                allowedFrames: [CGRect] = [],
                result: String
            ) {
                debugPrint(
                    "# LOOKUPKEYBOARD",
                    [
                        "stage": stage,
                        "point": NSCoder.string(for: CGRect(origin: point, size: .zero)),
                        "eventType": event?.type.rawValue as Any,
                        "popoverID": popover?.id.uuidString as Any,
                        "cachedFrame": cachedPopoverFrame.map(NSCoder.string(for:)) as Any,
                        "calculatedFrame": popoverFrame.map(NSCoder.string(for:)) as Any,
                        "excludedFrames": excludedFrames.map(NSCoder.string(for:)),
                        "allowedFrames": allowedFrames.map(NSCoder.string(for:)),
                        "safeAreaInsets": NSCoder.string(for: superview?.safeAreaInsets ?? safeAreaInsets),
                        "keyboardInsetBottom": superview?.safeAreaInsets.bottom ?? safeAreaInsets.bottom,
                        "result": result
                    ] as [String: Any]
                )
            }

            func hitTestHostedSiblings() -> UIView? {
                guard let superview else { return nil }
                for sibling in superview.subviews.reversed() where sibling !== self {
                    let siblingPoint = sibling.convert(point, from: self)
                    if let hit = sibling.hitTest(siblingPoint, with: event) {
                        return hit
                    }
                }
                return nil
            }

            /// Dismiss a popover, knowing that its frame does not contain the touch.
            func dismissPopoverIfNecessary(popoverToDismiss: Popover) {
                if
                    popoverToDismiss.attributes.dismissal.mode.contains(.tapOutside), /// The popover can be automatically dismissed when tapped outside.
                    popoverToDismiss.attributes.dismissal.tapOutsideIncludesOtherPopovers || /// The popover can be dismissed even if the touch hit another popover, **or...**
//                        !popoverFrames.contains(where: { $0.contains(point) }) /// ... no other popover frame contains the point (the touch landed outside)
                        !(popoverFrame?.contains(point) ?? false) /// ... no other popover frame contains the point (the touch landed outside)
                {
                    logLookupKeyboard(
                        "dismissPopoverIfNecessary",
                        popover: popoverToDismiss,
                        result: "dismiss"
                    )
                    popoverToDismiss.dismiss()
                }
            }
            
            /// Loop through the popovers and see if the touch hit it.
            /// `reversed` to start from the most recently presented popovers, working backwards.
            if let popover = popoverModel.popover {
            //            for popover in popovers.reversed() {
                /// Check it the popover was hit.
                if popoverFrame?.contains(point) ?? false {
                    /// Dismiss other popovers if they have `tapOutsideIncludesOtherPopovers` set to true.
//                    for popoverToDismiss in popovers {
//                        if
//                            popoverToDismiss != popover,
//                            !popoverToDismiss.context.frame.contains(point) /// The popover's frame doesn't contain the touch point.
//                        {
//                            dismissPopoverIfNecessary(popoverToDismiss: popoverToDismiss)
//                        }
//                    }
                    
                    /// Receive the touch and block it from going through.
                    let hit = super.hitTest(point, with: event)
                    let hitIsGestureContainer = (hit === self) || String(describing: type(of: hit)).contains("PopoverGestureContainer")
                    if hitIsGestureContainer, let siblingHit = hitTestHostedSiblings() {
                        logLookupKeyboard(
                            "hitPopover.forwardSibling",
                            popover: popover,
                            result: "returnSibling:\(String(describing: siblingHit))"
                        )
                        return siblingHit
                    }
                    if hitIsGestureContainer {
                        logLookupKeyboard(
                            "hitPopover.gestureContainerOnly",
                            popover: popover,
                            result: "returnSuper:\(String(describing: hit))"
                        )
                    }
                    logLookupKeyboard(
                        "hitPopover",
                        popover: popover,
                        result: "returnSuper:\(String(describing: hit))"
                    )
                    return hit
                }
                
                /// If the popover has `blocksBackgroundTouches` set to true, stop underlying views from receiving the touch.
                if popover.attributes.blocksBackgroundTouches {
                    let allowedFrames = popover.attributes.blocksBackgroundTouchesAllowedFrames()
                    
                    if allowedFrames.contains(where: { $0.contains(point) }) {
                        dismissPopoverIfNecessary(popoverToDismiss: popover)
                        
//                        return nil
                        let hit = presentingViewGestureTarget?.hitTest(point, with: event)
                        logLookupKeyboard(
                            "blocksBackgroundTouches.allowed",
                            popover: popover,
                            allowedFrames: allowedFrames,
                            result: "returnPresenting:\(String(describing: hit))"
                        )
                        return hit
                    } else {
                        /// Receive the touch and block it from going through.
                        let hit = super.hitTest(point, with: event)
                        logLookupKeyboard(
                            "blocksBackgroundTouches.block",
                            popover: popover,
                            allowedFrames: allowedFrames,
                            result: "returnSuper:\(String(describing: hit))"
                        )
                        return hit
                    }
                }
                
                /// Check if the touch hit an excluded view. If so, don't dismiss it.
                if popover.attributes.dismissal.mode.contains(.tapOutside) {
                    let excludedFrames = popover.attributes.dismissal.excludedFrames()
                    if excludedFrames.contains(where: { $0.contains(point) }) {
                        /**
                         The touch hit an excluded view, so don't dismiss it.
                         However, if the touch hit another popover, block it from passing through.
                         */
//                        if popoverFrames.contains(where: { $0.contains(point) }) {
                        if popoverFrame?.contains(point) ?? false {
                            let hit = super.hitTest(point, with: event)
                            logLookupKeyboard(
                                "excluded.hitPopover",
                                popover: popover,
                                excludedFrames: excludedFrames,
                                result: "returnSuper:\(String(describing: hit))"
                            )
                            return hit
                        } else {
                            logLookupKeyboard(
                                "excluded.passThrough",
                                popover: popover,
                                excludedFrames: excludedFrames,
                                result: "returnNil"
                            )
                            return nil
                        }
                    }
                }
                
                /// All checks did not pass, which means the touch landed outside the popover. So, dismiss it if necessary.
                logLookupKeyboard(
                    "outside.beforeDismiss",
                    popover: popover,
                    result: "invokeOnTapOutside"
                )
                popover.attributes.onTapOutside?()
                dismissPopoverIfNecessary(popoverToDismiss: popover)
            }
            
            /// The touch did not hit any popover, so pass it through to the hit testing target.
//            return nil
            let hit = presentingViewGestureTarget?.hitTest(point, with: event)
            logLookupKeyboard(
                "noPopover.passThrough",
                popover: nil,
                result: "returnPresenting:\(String(describing: hit))"
            )
            return hit
        }
    }
}
#endif
