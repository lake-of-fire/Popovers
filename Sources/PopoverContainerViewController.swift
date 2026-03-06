#if os(iOS)
//  PopoverContainerViewController.swift
//  Popovers
//
//  Created by A. Zheng (github.com/aheze) on 12/23/21.
//  Copyright © 2021 A. Zheng. All rights reserved.
//

import SwiftUI
import Foundation
import WebKit

@inline(__always)
private func lookupOpenPopoverLog(_ stage: String, _ metadata: [String: Any] = [:]) {
    #if DEBUG
    let allowedStages: Set<String> = [
        "popovers.container.hostingAttached",
        "popovers.container.hostingState",
        "popovers.container.viewWillAppear",
        "popovers.container.firstLayout",
        "popovers.container.applyMeasuredContentSize"
    ]
    guard allowedStages.contains(stage) else { return }
    var payload = metadata
    payload["stage"] = stage
    payload["uptimeMs"] = DispatchTime.now().uptimeNanoseconds / 1_000_000
    Swift.debugPrint("# LOOKUPOPEN", payload)
    #endif
}

/**
 The View Controller that hosts `PopoverContainerView`. This is automatically managed.
 */
//public class PopoverContainerViewController: UIViewController {
public class PopoverContainerViewController: HostingParentController {
    /// The `UIView` used to handle gesture interactions for popovers.
    private var popoverGestureContainerView: PopoverGestureContainer?
    private weak var hostingContentView: UIView?

    weak var overlayWindow: UIWindow?
    weak var baseWindow: UIWindow?
    var isOverlayPresentation = false
    
    /// If this is nil, the view hasn't been laid out yet.
    var previousBounds: CGRect?
    private var lastAppliedContentSize: CGSize = .zero
    private let createdAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
    private var didLogFirstLayout = false
    
    /**
     Create a new `PopoverContainerViewController`. This is automatically managed.
     */
    public init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        lookupOpenPopoverLog(
            "popovers.container.init",
            [
                "controller": String(describing: ObjectIdentifier(self))
            ]
        )
    }
    
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didLogFirstLayout {
            didLogFirstLayout = true
            lookupOpenPopoverLog(
                "popovers.container.firstLayout",
                [
                    "controller": String(describing: ObjectIdentifier(self)),
                    "bounds": NSCoder.string(for: view.bounds),
                    "frame": NSCoder.string(for: view.frame),
                    "alpha": view.alpha,
                    "hidden": view.isHidden,
                    "subviewCount": view.subviews.count,
                    "subviewTypes": view.subviews.map { String(describing: type(of: $0)) },
                    "hostingFrame": hostingContentView.map { NSCoder.string(for: $0.frame) } as Any,
                    "hostingHidden": hostingContentView?.isHidden as Any,
                    "hostingAlpha": hostingContentView?.alpha as Any,
                    "elapsedMs": Int((DispatchTime.now().uptimeNanoseconds - createdAtUptimeNanoseconds) / 1_000_000)
                ]
            )
        }
        
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
        lookupOpenPopoverLog(
            "popovers.container.viewDidLoad",
            [
                "controller": String(describing: ObjectIdentifier(self)),
                "elapsedMs": Int((DispatchTime.now().uptimeNanoseconds - createdAtUptimeNanoseconds) / 1_000_000)
            ]
        )
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        
//    override public func loadView() {
        popoverGestureContainerView = PopoverGestureContainer(windowAvailable: { [unowned self] window in
            /// Embed `PopoverContainerView` in a view controller.
            let popoverContainerView = PopoverContainerView(popoverModel: window.popoverModel)
                .environment(\.window, window)
            
            let hostingController = UIHostingController(rootView: popoverContainerView)
            hostingController.view.frame = view.bounds
            hostingController.view.backgroundColor = .clear
            hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            
            hostingController.willMove(toParent: self)
            addChild(hostingController)
            view.addSubview(hostingController.view)
            hostingController.didMove(toParent: self)
            hostingContentView = hostingController.view
            lookupOpenPopoverLog(
                "popovers.container.hostingAttached",
                [
                    "controller": String(describing: ObjectIdentifier(self)),
                    "hostingFrame": NSCoder.string(for: hostingController.view.frame),
                    "hostingBounds": NSCoder.string(for: hostingController.view.bounds),
                    "hostingHidden": hostingController.view.isHidden,
                    "hostingAlpha": hostingController.view.alpha,
                    "subviewTypes": view.subviews.map { String(describing: type(of: $0)) }
                ]
            )
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
        lookupOpenPopoverLog(
            "popovers.container.viewWillAppear",
            [
                "controller": String(describing: ObjectIdentifier(self)),
                "overlayPresentation": isOverlayPresentation,
                "hasOverlayWindow": overlayWindow != nil,
                "hasBaseWindow": baseWindow != nil,
                "viewFrame": NSCoder.string(for: view.frame),
                "viewBounds": NSCoder.string(for: view.bounds),
                "viewHidden": view.isHidden,
                "viewAlpha": view.alpha,
                "subviewCount": view.subviews.count,
                "subviewTypes": view.subviews.map { String(describing: type(of: $0)) },
                "hostingFrame": hostingContentView.map { NSCoder.string(for: $0.frame) } as Any,
                "hostingHidden": hostingContentView?.isHidden as Any,
                "hostingAlpha": hostingContentView?.alpha as Any,
                "windowHidden": view.window?.isHidden as Any,
                "windowKey": view.window?.isKeyWindow as Any,
                "elapsedMs": Int((DispatchTime.now().uptimeNanoseconds - createdAtUptimeNanoseconds) / 1_000_000)
            ]
        )
        lookupOpenPopoverLog(
            "popovers.container.hostingState",
            [
                "controller": String(describing: ObjectIdentifier(self)),
                "hostingFrame": hostingContentView.map { NSCoder.string(for: $0.frame) } as Any,
                "hostingBounds": hostingContentView.map { NSCoder.string(for: $0.bounds) } as Any,
                "hostingHidden": hostingContentView?.isHidden as Any,
                "hostingAlpha": hostingContentView?.alpha as Any,
                "hostingSuperview": hostingContentView?.superview.map { String(describing: type(of: $0)) } as Any,
                "subviewTypes": view.subviews.map { String(describing: type(of: $0)) }
            ]
        )
        
        /// Use the presenting view controller's view as the next element in the gesture container's responder chain
        /// when a hit test indicates no popover was tapped.
        let target = forwardBaseTouchesTo
            ?? presentingViewController?.view
            ?? presentingViewController?.viewIfLoaded
            ?? view.superview
        popoverGestureContainerView?.presentingViewGestureTarget = target
        forwardBaseTouchesTo = target

        if let overlayWindow = overlayWindow as? PopoverOverlayWindow {
            overlayWindow.passThroughPointPredicate = { [weak self, weak overlayWindow] point in
                self?.shouldPassThrough(pointInOverlayWindow: point, overlayWindow: overlayWindow) ?? false
            }
        }
    }

    private func shouldPassThrough(
        pointInOverlayWindow point: CGPoint,
        overlayWindow: PopoverOverlayWindow?
    ) -> Bool {
        guard let popover = popoverModel.popover else { return false }
        guard popover.attributes.dismissal.mode.contains(.tapOutside) else { return false }

        let windowPoint: CGPoint
        let predicateWindow: UIWindow?
        if let overlayWindow, let baseWindow {
            let screenPoint = overlayWindow.convert(point, to: nil)
            windowPoint = baseWindow.convert(screenPoint, from: nil)
            predicateWindow = baseWindow
        } else {
            windowPoint = point
            predicateWindow = overlayWindow ?? baseWindow
        }

        if popover.context.frame.contains(windowPoint) {
            return false
        }

        let excludedFrames = popover.attributes.dismissal.excludedFrames()
        guard excludedFrames.contains(where: { $0.contains(windowPoint) }) else { return false }
        let shouldRespect = popover.attributes.dismissal.excludedFramesPointPredicate(windowPoint, predicateWindow)
        if shouldRespect {
            let tagDescription = popover.attributes.tag.map { String(describing: $0) } ?? "nil"
            let pointDescription = NSCoder.string(for: CGRect(origin: windowPoint, size: .zero))
        }
        return shouldRespect
    }

    func teardownOverlayWindow(preserveRootViewController: Bool = false) {
        guard isOverlayPresentation else { return }
        lookupOpenPopoverLog(
            "popovers.container.teardownOverlayWindow.begin",
            [
                "controller": String(describing: ObjectIdentifier(self)),
                "hasOverlayWindow": overlayWindow != nil,
                "hasBaseWindow": baseWindow != nil,
                "preserveRootViewController": preserveRootViewController
            ]
        )
        if let baseWindow {
            baseWindow.makeKey()
        }
        overlayWindow?.isHidden = true
        if !preserveRootViewController {
            overlayWindow?.rootViewController = nil
            overlayWindow = nil
        }
        baseWindow = nil
        isOverlayPresentation = false
        lookupOpenPopoverLog(
            "popovers.container.teardownOverlayWindow.done",
            [
                "controller": String(describing: ObjectIdentifier(self)),
                "preserveRootViewController": preserveRootViewController
            ]
        )
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
                lookupOpenPopoverLog(
                    "popovers.container.gesture.didMoveToWindow",
                    [
                        "window": String(describing: ObjectIdentifier(window)),
                        "controllerAssigned": popoverController != nil
                    ]
                )
                windowAvailable(window)
            }
        }
        
        /**
         Determine if touches should land on popovers or pass through to the underlying view.
         The popover container view takes up the entire screen, so normally it would block all touches from going through. This method fixes that.
         */
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
            guard self.point(inside: point, with: event) else { return nil }

            /// Make sure the hit event was actually a touch and not a cursor hover or something else.
            guard event.map({ $0.type == .touches }) ?? true else { return nil }

            let popover = popoverModel.popover
            let pointString = NSCoder.string(for: point)
            var windowPointForForwarding: CGPoint? = nil
            var baseWindowPointForForwarding: CGPoint? = nil

            func resolveBaseWindowPoint(from localPoint: CGPoint) -> CGPoint? {
                guard let overlayWindow = window,
                      let baseWindow = popoverController?.baseWindow else { return nil }
                let screenPoint = overlayWindow.convert(localPoint, to: nil)
                return baseWindow.convert(screenPoint, from: nil)
            }

            /// Dismiss a popover, knowing that its frame does not contain the touch.
            func dismissPopoverIfNecessary(popoverToDismiss: Popover) {
                if
                    popoverToDismiss.attributes.dismissal.mode.contains(.tapOutside), /// The popover can be automatically dismissed when tapped outside.
                    popoverToDismiss.attributes.dismissal.tapOutsideIncludesOtherPopovers
                {
                    let tagDescription = popoverToDismiss.attributes.tag.map { String(describing: $0) } ?? "nil"
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
                    baseWindowPointForForwarding = resolveBaseWindowPoint(from: point)
                } else {
                    windowPointForForwarding = point
                    baseWindowPointForForwarding = resolveBaseWindowPoint(from: point)
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

                let shouldHandleTapOutside = popover.attributes.dismissal.mode.contains(.tapOutside)
                    || popover.attributes.onTapOutside != nil
                if shouldHandleTapOutside {
                    let excludedFrames = popover.attributes.dismissal.excludedFrames()
                    if excludedFrames.contains(where: { $0.contains(point) }) {
                        let windowPoint = baseWindowPointForForwarding ?? windowPointForForwarding ?? convert(point, to: window)
                        let predicateWindow = popoverController?.baseWindow ?? window
                        let shouldRespectExcludedFrames = popover.attributes.dismissal.excludedFramesPointPredicate(windowPoint, predicateWindow)
                        let tagDescription = popover.attributes.tag.map { String(describing: $0) } ?? "nil"
                        let windowPointDescription = NSCoder.string(for: CGRect(origin: windowPoint, size: .zero))
                        if shouldRespectExcludedFrames {
                            popoverController?.popoverDebugLog(
                                "PopoverGestureContainer.excludedFrame",
                                ("point", pointString),
                                ("component", popover.attributes.tag ?? "nil")
                            )
                            popoverController?.popoverDebugLog(
                                "PopoverGestureContainer.excludedFrameForward",
                                ("point", pointString),
                                ("component", popover.attributes.tag ?? "nil")
                            )
                            return forwardTouchToPresentingView(
                                point: point,
                                windowPoint: windowPoint,
                                event: event
                            )
                        }
                    }
                    if let controller = popoverController {
                        let tapPoint = baseWindowPointForForwarding ?? windowPointForForwarding ?? point
                        Task { @MainActor [weak controller] in
                            controller?.handleTapOutside(at: tapPoint)
                        }
                    } else {
                        popover.attributes.onTapOutside?()
                    }
                }

                dismissPopoverIfNecessary(popoverToDismiss: popover)
            }

            if windowPointForForwarding == nil, let window {
                windowPointForForwarding = convert(point, to: window)
                baseWindowPointForForwarding = resolveBaseWindowPoint(from: point)
            }

            return forwardTouchToPresentingView(
                point: point,
                windowPoint: baseWindowPointForForwarding ?? windowPointForForwarding,
                event: event
            )
        }

        private func forwardTouchToPresentingView(point: CGPoint, windowPoint: CGPoint?, event: UIEvent?) -> UIView? {
            let resolvedWindow = popoverController?.baseWindow ?? window
            if let windowPoint, let resolvedWindow {
                if let hit = resolvedWindow.hitTest(windowPoint, with: event) {
                    if let filteredHit = filtered(hit) {
                        debugForwardHit(
                            hit: filteredHit,
                            label: "window.hitTest",
                            windowPoint: windowPoint,
                            resolvedWindow: resolvedWindow
                        )
                        return filteredHit
                    }
                }
            }
            if let presenting = presentingViewGestureTarget {
                if let windowPoint,
                   let resolvedWindow {
                    if let hit = hitTestPreferred(
                        in: presenting,
                        windowPoint: windowPoint,
                        resolvedWindow: resolvedWindow
                    ) {
                        debugForwardHit(
                            hit: hit,
                            label: "presenting.windowHit",
                            windowPoint: windowPoint,
                            resolvedWindow: resolvedWindow
                        )
                        popoverController?.popoverDebugLog(
                            "forward.presenting.windowHit",
                            ("view", String(describing: type(of: hit)))
                        )
                        return filtered(hit)
                    }
                }
                let localPoint = presenting.convert(point, from: self)
                if let hit = hitTestPreferred(
                    in: presenting,
                    localPoint: localPoint
                ) {
                    debugForwardHit(
                        hit: hit,
                        label: "presenting.localHit",
                        windowPoint: windowPoint,
                        resolvedWindow: resolvedWindow
                    )
                    popoverController?.popoverDebugLog(
                        "forward.presenting.localHit",
                        ("view", String(describing: type(of: hit)))
                    )
                    return filtered(hit)
                }
            }

            if let resolvedWindow,
               let rootView = resolvedWindow.rootViewController?.view {
                let resolvedWindowPoint = windowPoint ?? convert(point, to: resolvedWindow)
                if let hit = hitTestPreferred(
                    in: rootView,
                    windowPoint: resolvedWindowPoint,
                    resolvedWindow: resolvedWindow
                ) {
                    debugForwardHit(
                        hit: hit,
                        label: "root.windowHit",
                        windowPoint: resolvedWindowPoint,
                        resolvedWindow: resolvedWindow
                    )
                    popoverController?.popoverDebugLog(
                        "forward.window.rootHit",
                        ("view", String(describing: type(of: hit)))
                    )
                    return filtered(hit)
                }
            }

            if let forwardTarget = popoverController?.forwardBaseTouchesTo {
                if let windowPoint,
                   let resolvedWindow {
                    if let hit = hitTestPreferred(
                        in: forwardTarget,
                        windowPoint: windowPoint,
                        resolvedWindow: resolvedWindow
                    ) {
                        debugForwardHit(
                            hit: hit,
                            label: "base.windowHit",
                            windowPoint: windowPoint,
                            resolvedWindow: resolvedWindow
                        )
                        popoverController?.popoverDebugLog(
                            "forward.base.windowHit",
                            ("view", String(describing: type(of: hit)))
                        )
                        return filtered(hit)
                    }
                }
                let localPoint = forwardTarget.convert(point, from: self)
                if let hit = hitTestPreferred(
                    in: forwardTarget,
                    localPoint: localPoint
                ) {
                    debugForwardHit(
                        hit: hit,
                        label: "base.localHit",
                        windowPoint: windowPoint,
                        resolvedWindow: resolvedWindow
                    )
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
            let pointDescription = windowPoint.map { NSCoder.string(for: CGRect(origin: $0, size: .zero)) } ?? "nil"
            return nil
        }

        private func debugForwardHit(
            hit: UIView,
            label: String,
            windowPoint: CGPoint?,
            resolvedWindow: UIWindow?
        ) {
            let hitType = String(describing: type(of: hit))
            let windowPointDescription = windowPoint.map { NSCoder.string(for: CGRect(origin: $0, size: .zero)) } ?? "nil"
            var hierarchy: [String] = []
            var cursor: UIView? = hit
            var isWebView = false
            while let view = cursor, hierarchy.count < 6 {
                let viewType = String(describing: type(of: view))
                hierarchy.append(viewType)
                if view is WKWebView {
                    isWebView = true
                }
                cursor = view.superview
            }
            let frameInWindow: String = {
                guard let resolvedWindow else { return "nil" }
                let frame = hit.convert(hit.bounds, to: resolvedWindow)
                return NSCoder.string(for: frame)
            }()
            popoverController?.popoverDebugLog(
                "PopoverGestureContainer.forwardDecision",
                ("label", label),
                ("hit", hitType),
                ("isWebView", isWebView),
                ("windowPoint", windowPointDescription),
                ("frame", frameInWindow),
                ("hierarchy", hierarchy.joined(separator: " -> "))
            )
        }

        private func hitTestPreferred(
            in view: UIView,
            windowPoint: CGPoint,
            resolvedWindow: UIWindow
        ) -> UIView? {
            let localPoint = view.convert(windowPoint, from: resolvedWindow)
            return hitTestPreferred(
                in: view,
                localPoint: localPoint,
                containerBounds: resolvedWindow.bounds
            )
        }

        private func hitTestPreferred(
            in view: UIView,
            localPoint: CGPoint,
            containerBounds: CGRect? = nil
        ) -> UIView? {
            guard view.bounds.contains(localPoint) else { return nil }
            guard view.isUserInteractionEnabled, !view.isHidden, view.alpha > 0.01 else { return nil }
            for subview in view.subviews.reversed() {
                let subPoint = subview.convert(localPoint, from: view)
                if let hit = hitTestPreferred(in: subview, localPoint: subPoint, containerBounds: containerBounds) {
                    return hit
                }
            }
            let className = String(describing: type(of: view))
            let normalized = className.lowercased()
            if normalized.contains("hosting")
                || normalized.contains("swiftui")
                || normalized.contains("platform")
                || normalized.contains("wrapper")
                || normalized.contains("transition")
                || normalized.contains("passthrough") {
                return nil
            }
            if normalized.contains("container"), let containerBounds {
                let size = view.bounds.size
                let matchesContainer = abs(size.width - containerBounds.width) < 2
                    && abs(size.height - containerBounds.height) < 2
                if matchesContainer, view.subviews.isEmpty == false {
                    return nil
                }
            }
            return view
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
        let deltaWidth = abs(size.width - lastAppliedContentSize.width)
        let deltaHeight = abs(size.height - lastAppliedContentSize.height)
        guard deltaWidth > 0.5 || deltaHeight > 0.5 else { return }

        popover.updateFrame(with: size)
        updatePreferredContentSize(size: popover.context.size ?? size)
        lastAppliedContentSize = size
        lookupOpenPopoverLog(
            "popovers.container.applyMeasuredContentSize",
            [
                "controller": String(describing: ObjectIdentifier(self)),
                "width": size.width,
                "height": size.height,
                "preferredContentSize": NSCoder.string(for: CGRect(origin: .zero, size: preferredContentSize)),
                "currentContentSize": NSCoder.string(for: CGRect(origin: .zero, size: currentContentSize()))
            ]
        )
    }

    @MainActor
    public func refreshPopoverFrames() {
        popoverModel.updateFramesAfterBoundsChange()
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
        let predicateWindow = baseWindow ?? view.window
        let predicateWindowDescription = predicateWindow.map { NSCoder.string(for: $0.bounds) } ?? "nil"
        let windowIdentity = predicateWindow.map { ObjectIdentifier($0).debugDescription } ?? "nil"

        popoverDebugLog(
            "tapOutside.begin",
            ("component", popover.context.attributes.tag ?? "nil"),
            ("windowPoint", NSCoder.string(for: CGRect(origin: windowPoint, size: .zero)))
        )
        let tagDescription = popover.context.attributes.tag.map { String(describing: $0) } ?? "nil"

        let excludedFrames = popover.attributes.dismissal.excludedFrames()
        if let matchedFrame = excludedFrames.first(where: { $0.contains(windowPoint) }) {
            let shouldRespectExcludedFrames = popover.attributes.dismissal.excludedFramesPointPredicate(windowPoint, predicateWindow)
            if !shouldRespectExcludedFrames {
                popoverDebugLog(
                    "tapOutside.excluded.ignored",
                    ("component", popover.context.attributes.tag ?? "nil"),
                    ("frame", NSCoder.string(for: matchedFrame))
                )
            } else {
                popoverDebugLog(
                    "tapOutside.excluded",
                    ("component", popover.context.attributes.tag ?? "nil"),
                    ("frame", NSCoder.string(for: matchedFrame))
                )
                return
            }
        }

        popover.attributes.onTapOutside?()

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
        if tapOutsideEnabled {
            popover.dismiss()
        } else {
        }
    }
}
#endif
