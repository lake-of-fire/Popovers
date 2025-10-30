#if os(iOS)
//  PopoverContainerViewController.swift
//  Popovers
//
//  Created by A. Zheng (github.com/aheze) on 12/23/21.
//  Copyright © 2021 A. Zheng. All rights reserved.
//

import SwiftUI
import Foundation

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
    
    private func popoverDebugLog(_ message: String, _ metadata: (String, Any?)...) {
#if DEBUG
        let formatted = metadata
            .map { key, value -> String in
                if let value {
                    return "\(key)=\(value)"
                } else {
                    return "\(key)=nil"
                }
            }
            .joined(separator: " ")
        debugPrint("# POPOVER \(message) \(formatted)")
#endif
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
        popoverGestureContainerView?.popoverController = self
        
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
        let target = presentingViewController?.view ?? presentingViewController?.viewIfLoaded ?? view.superview
        popoverGestureContainerView?.presentingViewGestureTarget = target
        forwardBaseTouchesTo = target
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

    private class PopoverGestureContainer: UIView {
        private let windowAvailable: (UIWindow) -> Void

        /// The `UIView` to forward hit tests to when a check fails in this view.
        weak var presentingViewGestureTarget: UIView?
        weak var popoverController: PopoverContainerViewController?

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

            let popover = popoverModel.popover
            let pointString = NSCoder.string(for: point)
            var windowPointForForwarding: CGPoint? = nil

            /// Dismiss a popover, knowing that its frame does not contain the touch.
            func dismissPopoverIfNecessary(popoverToDismiss: Popover) {
                if
                    popoverToDismiss.attributes.dismissal.mode.contains(.tapOutside), /// The popover can be automatically dismissed when tapped outside.
                    popoverToDismiss.attributes.dismissal.tapOutsideIncludesOtherPopovers
                {
                    popoverToDismiss.dismiss()
                }
            }

            if let popover = popover {
                if popover.context.frame.contains(point) {
                    popoverController?.popoverDebugLog(
                        "PopoverGestureContainer.hitInside",
                        ("point", pointString),
                        ("component", popover.attributes.tag ?? "nil")
                    )
                    return super.hitTest(point, with: event)
                }

                if let window {
                    let converted = convert(point, to: window)
                    windowPointForForwarding = converted
                    if let controller = popoverController {
                        Task { @MainActor [weak controller] in
                            controller?.handleTapOutside(at: converted)
                        }
                    } else {
                        popover.attributes.onTapOutside?()
                    }
                } else {
                    windowPointForForwarding = point
                    if let controller = popoverController {
                        Task { @MainActor [weak controller] in
                            controller?.handleTapOutside(at: point)
                        }
                    } else {
                        popover.attributes.onTapOutside?()
                    }
                }

                if popover.attributes.blocksBackgroundTouches {
                    let allowedFrames = popover.attributes.blocksBackgroundTouchesAllowedFrames()
                    if allowedFrames.contains(where: { $0.contains(point) }) {
                        popoverController?.popoverDebugLog(
                            "PopoverGestureContainer.allowedFrame",
                            ("point", pointString),
                            ("component", popover.attributes.tag ?? "nil")
                        )
                        dismissPopoverIfNecessary(popoverToDismiss: popover)
                        return forwardTouchToPresentingView(point: point, windowPoint: windowPointForForwarding, event: event)
                    }
                    popoverController?.popoverDebugLog(
                        "PopoverGestureContainer.blocksBackground",
                        ("point", pointString),
                        ("component", popover.attributes.tag ?? "nil")
                        )
                    return super.hitTest(point, with: event)
                }

                if popover.attributes.dismissal.mode.contains(.tapOutside) {
                    let excludedFrames = popover.attributes.dismissal.excludedFrames()
                    if excludedFrames.contains(where: { $0.contains(point) }) {
                        popoverController?.popoverDebugLog(
                            "PopoverGestureContainer.excludedFrame",
                            ("point", pointString),
                            ("component", popover.attributes.tag ?? "nil")
                        )
                        return super.hitTest(point, with: event)
                    }
                }

                dismissPopoverIfNecessary(popoverToDismiss: popover)
            }

            if windowPointForForwarding == nil, let window {
                windowPointForForwarding = convert(point, to: window)
            }

            return forwardTouchToPresentingView(point: point, windowPoint: windowPointForForwarding, event: event)
        }

        private func forwardTouchToPresentingView(point: CGPoint, windowPoint: CGPoint?, event: UIEvent?) -> UIView? {
            if let presenting = presentingViewGestureTarget {
                if let windowPoint,
                   let window {
                    let presentingPoint = presenting.convert(windowPoint, from: window)
                    if let hit = presenting.hitTest(presentingPoint, with: event) {
                        popoverController?.popoverDebugLog(
                            "forward.presenting.windowHit",
                            ("view", String(describing: type(of: hit)))
                        )
                        return filtered(hit)
                    }
                }
                let localPoint = presenting.convert(point, from: self)
                if let hit = presenting.hitTest(localPoint, with: event) {
                    popoverController?.popoverDebugLog(
                        "forward.presenting.localHit",
                        ("view", String(describing: type(of: hit)))
                    )
                    return filtered(hit)
                }
            }

            if let window = window,
               let rootView = window.rootViewController?.view {
                let resolvedWindowPoint = windowPoint ?? convert(point, to: window)
                let rootPoint = rootView.convert(resolvedWindowPoint, from: window)
                if let hit = rootView.hitTest(rootPoint, with: event) {
                    popoverController?.popoverDebugLog(
                        "forward.window.rootHit",
                        ("view", String(describing: type(of: hit)))
                    )
                    return filtered(hit)
                }
            }

            if let forwardTarget = popoverController?.forwardBaseTouchesTo {
                if let windowPoint,
                   let window {
                    let forwardPoint = forwardTarget.convert(windowPoint, from: window)
                    if let hit = forwardTarget.hitTest(forwardPoint, with: event) {
                        popoverController?.popoverDebugLog(
                            "forward.base.windowHit",
                            ("view", String(describing: type(of: hit)))
                        )
                        return filtered(hit)
                    }
                }
                let localPoint = forwardTarget.convert(point, from: self)
                if let hit = forwardTarget.hitTest(localPoint, with: event) {
                    popoverController?.popoverDebugLog(
                        "forward.base.localHit",
                        ("view", String(describing: type(of: hit)))
                    )
                    return filtered(hit)
                }
            }

            popoverController?.popoverDebugLog(
                "forward.none",
                ("point", windowPoint.map { NSCoder.string(for: CGRect(origin: $0, size: .zero)) } ?? "nil")
            )
            return nil
        }

        private func filtered(_ view: UIView) -> UIView? {
            if view === self || view.isDescendant(of: self) {
                return nil
            }
            return view
        }
    }

    @MainActor
    public func applyMeasuredContentSize(_ size: CGSize) {
        guard size.width.isFinite,
              size.height.isFinite else { return }
        guard size.width > 40,
              size.height > 40 else { return }
        guard let popover = popoverModel.popover else { return }

        popover.updateFrame(with: size)
        updatePreferredContentSize(size: popover.context.size ?? size)
    }

    public func currentContentSize() -> CGSize {
        if let popover = popoverModel.popover,
           let contextSize = popover.context.size,
           contextSize.width.isFinite,
           contextSize.height.isFinite {
            return contextSize
        }
        return preferredContentSize
    }

    public func updatePreferredContentSize(size: CGSize) {
        guard size.width.isFinite,
              size.height.isFinite else { return }
        preferredContentSize = CGSize(width: max(size.width, 1), height: max(size.height, 1))
    }

    @MainActor
    func handleTapOutside(at windowPoint: CGPoint) {
        guard let popover = popoverModel.popover else { return }

        popoverDebugLog(
            "tapOutside.begin",
            ("component", popover.context.attributes.tag ?? "nil"),
            ("windowPoint", NSCoder.string(for: CGRect(origin: windowPoint, size: .zero)))
        )

        popover.attributes.onTapOutside?()

        let excludedFrames = popover.attributes.dismissal.excludedFrames()
        if let matchedFrame = excludedFrames.first(where: { $0.contains(windowPoint) }) {
            popoverDebugLog(
                "tapOutside.excluded",
                ("component", popover.context.attributes.tag ?? "nil"),
                ("frame", NSCoder.string(for: matchedFrame))
            )
            return
        }

        let tapOutsideEnabled = popover.attributes.dismissal.mode.contains(.tapOutside)
        popoverDebugLog(
            tapOutsideEnabled ? "tapOutside.tapOutsideEnabled" : "tapOutside.tapOutsideDisabled",
            ("component", popover.context.attributes.tag ?? "nil")
        )

        if popover.attributes.blocksBackgroundTouches {
            let allowedFrames = popover.attributes.blocksBackgroundTouchesAllowedFrames()
            if allowedFrames.contains(where: { $0.contains(windowPoint) }) {
                popoverDebugLog(
                    "tapOutside.allowedFrame",
                    ("component", popover.context.attributes.tag ?? "nil")
                )
                return
            }
        }

        popoverDebugLog(
            "tapOutside.dismiss",
            ("component", popover.context.attributes.tag ?? "nil")
        )
        popover.dismiss()
    }
}
#endif
