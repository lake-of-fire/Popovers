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
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        
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

    private func logLookupKeyboardController(
        _ stage: String,
        popoverID: String? = nil,
        result: String
    ) {
        debugPrint(
            "# LOOKUPKEYBOARD",
            [
                "stage": stage,
                "popoverID": popoverID as Any,
                "result": result
            ] as [String: Any]
        )
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override public func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
    }
    
    @objc private func keyboardWillShow(notification: Notification) {
        Task { @MainActor [weak self] in
            self?.logKeyboardNotification("keyboard.willShow", notification: notification)
            self?.updateKeyboardFrame(from: notification)
            self?.popoverModel.updateFramesAfterBoundsChange()
        }
    }
    
    @objc private func keyboardWillHide(notification: Notification) {
        Task { @MainActor [weak self] in
            self?.logKeyboardNotification("keyboard.willHide", notification: notification)
            self?.clearKeyboardFrame()
            self?.popoverModel.updateFramesAfterBoundsChange()
        }
    }

    @objc private func keyboardWillChangeFrame(notification: Notification) {
        Task { @MainActor [weak self] in
            self?.logKeyboardNotification("keyboard.willChangeFrame", notification: notification)
            self?.updateKeyboardFrame(from: notification)
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

    @MainActor
    private func updateKeyboardFrame(from notification: Notification) {
        guard
            let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let popover = popoverModel.popover,
            let window = view.window
        else { return }

        let keyboardFrameInWindow = window.convert(keyboardFrame, from: nil)
        popover.context.keyboardFrameInWindow = keyboardFrameInWindow
        logLookupKeyboardController(
            "keyboard.frameUpdated",
            popoverID: popover.id.uuidString,
            result: "keyboardFrame=\(NSCoder.string(for: keyboardFrameInWindow)); popoverFrame=\(NSCoder.string(for: popover.context.frame))"
        )
    }

    @MainActor
    private func clearKeyboardFrame() {
        if let popover = popoverModel.popover {
            popover.context.keyboardFrameInWindow = .zero
            logLookupKeyboardController(
                "keyboard.frameCleared",
                popoverID: popover.id.uuidString,
                result: "popoverFrame=\(NSCoder.string(for: popover.context.frame))"
            )
        }
    }

    @MainActor
    private func logKeyboardNotification(_ stage: String, notification: Notification) {
        let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int
        let endFrameString = endFrame.map(NSCoder.string(for:)) ?? "nil"
        let durationString = duration.map { String($0) } ?? "nil"
        let curveString = curve.map { String($0) } ?? "nil"
        logLookupKeyboardController(
            stage,
            popoverID: popoverModel.popover?.id.uuidString,
            result: "endFrame=\(endFrameString); duration=\(durationString); curve=\(curveString)"
        )
    }

    private class PopoverGestureContainer: UIView {
        private let windowAvailable: (UIWindow) -> Void
        
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
            
            /// Use the cached frame during hit-testing to avoid re-entering popover
            /// frame calculation from within UIKit's hit-test path.
//            let popoverFrames = popovers.map { $0.context.frame }
            let cachedPopoverFrame = popoverModel.popover?.context.frame
            let popoverFrame = cachedPopoverFrame

            func logLookupKeyboard(
                _ stage: String,
                popover: Popover?,
                result: String
            ) {
                let payload: [String: Any] = [
                    "stage": stage,
                    "point": NSCoder.string(for: CGRect(origin: point, size: .zero)),
                    "popoverID": popover?.id.uuidString as Any,
                    "frame": popoverFrame.map(NSCoder.string(for:)) as Any,
                    "result": result
                ]
                debugPrint(
                    "# LOOKUPKEYBOARD",
                    payload
                )
            }

            func describeViewType(_ view: UIView?) -> String {
                guard let view else { return "nil" }
                return String(describing: type(of: view))
            }

            /// Dismiss a popover, knowing that its frame does not contain the touch.
            func dismissPopoverIfNecessary(popoverToDismiss: Popover) {
                if
                    popoverToDismiss.attributes.dismissal.mode.contains(.tapOutside), /// The popover can be automatically dismissed when tapped outside.
                    popoverToDismiss.attributes.dismissal.tapOutsideIncludesOtherPopovers || /// The popover can be dismissed even if the touch hit another popover, **or...**
//                        !popoverFrames.contains(where: { $0.contains(point) }) /// ... no other popover frame contains the point (the touch landed outside)
                        !(popoverFrame?.contains(point) ?? false) /// ... no other popover frame contains the point (the touch landed outside)
                {
                    popoverToDismiss.dismiss()
                }
            }
            
            /// Loop through the popovers and see if the touch hit it.
            /// `reversed` to start from the most recently presented popovers, working backwards.
            if let popover = popoverModel.popover {
            //            for popover in popovers.reversed() {
                /// Check it the popover was hit.
                if popoverFrame?.contains(point) ?? false {
                    logLookupKeyboard(
                        "branch.hitPopover.enter",
                        popover: popover,
                        result: "popoverFrameContains=true"
                    )
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
                    logLookupKeyboard(
                        "hitPopover",
                        popover: popover,
                        result: "returnSuperType=\(describeViewType(hit))"
                    )
                    return hit
                }

                logLookupKeyboard(
                    "branch.hitPopover.skip",
                    popover: popover,
                    result: "popoverFrameContains=false"
                )
                
                /// If the popover has `blocksBackgroundTouches` set to true, stop underlying views from receiving the touch.
                if popover.attributes.blocksBackgroundTouches {
                    let allowedFrames = popover.attributes.blocksBackgroundTouchesAllowedFrames()
                    
                    if allowedFrames.contains(where: { $0.contains(point) }) {
                        dismissPopoverIfNecessary(popoverToDismiss: popover)
                        
                        let hit: UIView? = nil
                        logLookupKeyboard(
                            "blocksBackgroundTouches.allowed",
                            popover: popover,
                            result: "returnPresentingType=\(describeViewType(hit))"
                        )
                        return hit
                    } else {
                        /// Receive the touch and block it from going through.
                        let hit = super.hitTest(point, with: event)
                        logLookupKeyboard(
                            "blocksBackgroundTouches.block",
                            popover: popover,
                            result: "returnSuperType=\(describeViewType(hit))"
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
                                result: "returnSuperType=\(describeViewType(hit))"
                            )
                            return hit
                        } else {
                            logLookupKeyboard(
                                "excluded.passThrough",
                                popover: popover,
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
            let hit: UIView? = nil
            logLookupKeyboard(
                "noPopover.passThrough",
                popover: nil,
                result: "returnPresentingType=\(describeViewType(hit))"
            )
            return hit
        }
    }
}
#endif
