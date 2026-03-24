#if os(iOS)
//  PopoverContainerViewController.swift
//  Popovers
//
//  Created by A. Zheng (github.com/aheze) on 12/23/21.
//  Copyright © 2021 A. Zheng. All rights reserved.
//

import SwiftUI

private func lookupKeyboardResponderDescription(_ responder: UIResponder?) -> String {
    guard let responder else { return "nil" }
    if let view = responder as? UIView {
        return "\(type(of: view))"
    }
    if let viewController = responder as? UIViewController {
        return "\(type(of: viewController))"
    }
    return String(describing: type(of: responder))
}

private extension UIView {
    func lookupKeyboardFindFirstResponder() -> UIResponder? {
        if isFirstResponder { return self }
        for subview in subviews {
            if let responder = subview.lookupKeyboardFindFirstResponder() {
                return responder
            }
        }
        return nil
    }
}

/**
 The View Controller that hosts `PopoverContainerView`. This is automatically managed.
 */
//public class PopoverContainerViewController: UIViewController {
public class PopoverContainerViewController: HostingParentController {
    /// The `UIView` used to handle gesture interactions for popovers.
    private var popoverGestureContainerView: PopoverGestureContainer?
    private var pendingKeyboardFrameTask: Task<Void, Never>?
    
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

    deinit {
        pendingKeyboardFrameTask?.cancel()
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

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pendingKeyboardFrameTask?.cancel()
        pendingKeyboardFrameTask = nil
    }

    private func logLookupKeyboardController(
        _ stage: String,
        popoverID: String? = nil,
        result: String
    ) {
        let firstResponder = view.window?.lookupKeyboardFindFirstResponder()
        debugPrint(
            "# LOOKUPKEYBOARD",
            [
                "stage": stage,
                "popoverID": popoverID as Any,
                "result": result,
                "windowFirstResponder": lookupKeyboardResponderDescription(firstResponder)
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
            self?.pendingKeyboardFrameTask?.cancel()
            self?.updateKeyboardFrame(from: notification)
            self?.popoverModel.updateFramesAfterBoundsChange()
        }
    }
    
    @objc private func keyboardWillHide(notification: Notification) {
        Task { @MainActor [weak self] in
            self?.logKeyboardNotification("keyboard.willHide", notification: notification)
            self?.scheduleKeyboardFrameClear(from: notification)
        }
    }

    @objc private func keyboardWillChangeFrame(notification: Notification) {
        Task { @MainActor [weak self] in
            self?.logKeyboardNotification("keyboard.willChangeFrame", notification: notification)
            guard let self else { return }
            if self.notificationMovesKeyboardOffscreen(notification) {
                return
            }
            self.updateKeyboardFrame(from: notification)
            self.popoverModel.updateFramesAfterBoundsChange()
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
    public func updateColorScheme(_ colorScheme: ColorScheme) {
        let interfaceStyle: UIUserInterfaceStyle
        switch colorScheme {
        case .light:
            interfaceStyle = .light
        case .dark:
            interfaceStyle = .dark
        @unknown default:
            interfaceStyle = .unspecified
        }
        overrideUserInterfaceStyle = interfaceStyle
        children.forEach { $0.overrideUserInterfaceStyle = interfaceStyle }
        popoverModel.reload()
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
    private func hasActiveTextInputFirstResponder() -> Bool {
        guard let firstResponder = view.window?.lookupKeyboardFindFirstResponder() else { return false }
        return firstResponder is UITextField || firstResponder is UITextView
    }

    @MainActor
    private func scheduleKeyboardFrameClear(from notification: Notification) {
        pendingKeyboardFrameTask?.cancel()

        if hasActiveTextInputFirstResponder() {
            logLookupKeyboardController(
                "keyboard.frameClearSuppressed",
                popoverID: popoverModel.popover?.id.uuidString,
                result: "reason=activeTextInput"
            )
            pendingKeyboardFrameTask = nil
            return
        }

        let delayNanoseconds: UInt64
        if keyboardAnimationDuration(from: notification) == 0, notificationMovesKeyboardOffscreen(notification) {
            delayNanoseconds = 150_000_000
        } else {
            delayNanoseconds = 0
        }

        if delayNanoseconds == 0 {
            clearKeyboardFrame()
            popoverModel.updateFramesAfterBoundsChange()
            pendingKeyboardFrameTask = nil
            return
        }

        pendingKeyboardFrameTask = Task { @MainActor [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }

            guard let self, !Task.isCancelled else { return }
            if self.hasActiveTextInputFirstResponder() {
                self.logLookupKeyboardController(
                    "keyboard.frameClearSuppressed",
                    popoverID: self.popoverModel.popover?.id.uuidString,
                    result: "reason=activeTextInputAfterDelay"
                )
                self.pendingKeyboardFrameTask = nil
                return
            }
            self.clearKeyboardFrame()
            self.popoverModel.updateFramesAfterBoundsChange()
            self.pendingKeyboardFrameTask = nil
        }
    }

    @MainActor
    private func keyboardAnimationDuration(from notification: Notification) -> Double {
        notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0
    }

    @MainActor
    private func notificationMovesKeyboardOffscreen(_ notification: Notification) -> Bool {
        guard
            let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let window = view.window
        else { return false }

        let keyboardFrameInWindow = window.convert(keyboardFrame, from: nil)
        return keyboardFrameInWindow.minY >= window.bounds.maxY
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
        private var activeTouchCount = 0
        private var isPerformingDirectContentHitTest = false
        
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

        private func logLookupTouch(_ stage: String) {
            let firstResponder = window?.lookupKeyboardFindFirstResponder()
            debugPrint(
                "# LOOKUPKEYBOARD",
                [
                    "stage": stage,
                    "activeTouchCount": activeTouchCount,
                    "windowFirstResponder": lookupKeyboardResponderDescription(firstResponder)
                ] as [String: Any]
            )
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            activeTouchCount += touches.count
            logLookupTouch("touchesBegan")
            super.touchesBegan(touches, with: event)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            activeTouchCount = max(0, activeTouchCount - touches.count)
            logLookupTouch("touchesEnded")
            super.touchesEnded(touches, with: event)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            activeTouchCount = max(0, activeTouchCount - touches.count)
            logLookupTouch("touchesCancelled")
            super.touchesCancelled(touches, with: event)
        }
        
        /**
         Determine if touches should land on popovers or pass through to the underlying view.
         The popover container view takes up the entire screen, so normally it would block all touches from going through. This method fixes that.
         */
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            if isPerformingDirectContentHitTest {
                return nil
            }

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

            func describeViewIdentity(_ view: UIView?) -> String {
                guard let view else { return "nil" }
                return "\(describeViewType(view))@\(ObjectIdentifier(view))"
            }

            func isHostingView(_ view: UIView) -> Bool {
                String(describing: type(of: view)).contains("_UIHostingView")
            }

            func ancestorChain(for view: UIView?) -> String {
                guard let view else { return "nil" }
                var chain: [String] = [describeViewIdentity(view)]
                var currentSuperview = view.superview
                var depth = 0
                while depth < 8, let current = currentSuperview {
                    chain.append(describeViewIdentity(current))
                    depth += 1
                    currentSuperview = current.superview
                }
                return chain.joined(separator: " <- ")
            }

            func gestureRecognizerSnapshot(for view: UIView?, maxAncestorDepth: Int = 6) -> String {
                guard let view else { return "nil" }
                var entries: [String] = []
                var current: UIView? = view
                var depth = 0

                while let unwrappedCurrent = current, depth <= maxAncestorDepth {
                    let recognizers = (unwrappedCurrent.gestureRecognizers ?? []).map { recognizer in
                        let recognizerType = String(describing: type(of: recognizer))
                        return "\(recognizerType)(state=\(recognizer.state.rawValue); cancels=\(recognizer.cancelsTouchesInView); delaysBegan=\(recognizer.delaysTouchesBegan); delaysEnded=\(recognizer.delaysTouchesEnded))"
                    }
                    let recognizerSummary = recognizers.isEmpty ? "none" : recognizers.joined(separator: ", ")
                    entries.append("\(String(repeating: "^", count: depth))\(describeViewIdentity(unwrappedCurrent)) => \(recognizerSummary)")
                    current = unwrappedCurrent.superview
                    depth += 1
                }

                return entries.joined(separator: " | ")
            }

            func descendantSnapshot(for view: UIView?, maxDepth: Int = 3, maxEntries: Int = 16) -> String {
                guard let view else { return "nil" }
                var entries: [String] = []

                func walk(_ current: UIView, depth: Int) {
                    guard entries.count < maxEntries, depth <= maxDepth else { return }
                    entries.append(String(repeating: ">", count: depth) + describeViewIdentity(current))
                    for subview in current.subviews {
                        guard entries.count < maxEntries else { return }
                        walk(subview, depth: depth + 1)
                    }
                }

                for subview in view.subviews {
                    guard entries.count < maxEntries else { break }
                    walk(subview, depth: 1)
                }

                return entries.isEmpty ? "none" : entries.joined(separator: " | ")
            }

            func findDescendantTextField(in view: UIView?) -> UITextField? {
                guard let view else { return nil }
                if let textField = view as? UITextField {
                    return textField
                }
                for subview in view.subviews {
                    if let textField = findDescendantTextField(in: subview) {
                        return textField
                    }
                }
                return nil
            }

            func nearestAncestorHostedTextField(for view: UIView?) -> UITextField? {
                var current = view
                var depth = 0

                while let unwrappedCurrent = current, depth < 8 {
                    if let textField = findDescendantTextField(in: unwrappedCurrent) {
                        return textField
                    }
                    current = unwrappedCurrent.superview
                    depth += 1
                }

                return nil
            }

            func nearestAncestorContainerHostingTextField(for view: UIView?) -> UIView? {
                var current = view
                var depth = 0

                while let unwrappedCurrent = current, depth < 8 {
                    if findDescendantTextField(in: unwrappedCurrent) != nil {
                        return unwrappedCurrent
                    }
                    current = unwrappedCurrent.superview
                    depth += 1
                }

                return nil
            }

            func directPopoverContentHitTest() -> UIView? {
                guard let containerSuperview = superview else { return nil }
                isUserInteractionEnabled = false
                defer { isUserInteractionEnabled = true }

                let superviewPoint = containerSuperview.convert(point, from: self)
                let hit = containerSuperview.hitTest(superviewPoint, with: event)
                if hit === self || hit is PopoverGestureContainer {
                    return nil
                }
                return hit
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
                    let overlayHit = super.hitTest(point, with: event)
                    let directContentHit = directPopoverContentHitTest()
                    let hostedTextFieldHit = nearestAncestorHostedTextField(for: directContentHit)
                    let hostedContainerHit = nearestAncestorContainerHostingTextField(for: directContentHit)
                    let hit: UIView?
                    if overlayHit === self || overlayHit is PopoverGestureContainer {
                        hit = hostedContainerHit ?? directContentHit ?? overlayHit
                    } else {
                        hit = overlayHit
                    }
                    let hitDescription = describeViewIdentity(hit)
                    let overlayHitDescription = describeViewIdentity(overlayHit)
                    let directHitDescription = describeViewIdentity(directContentHit)
                    let hostedTextFieldDescription = hostedTextFieldHit.map { "UITextField@\(ObjectIdentifier($0)); isFirstResponder=\($0.isFirstResponder)" } ?? "nil"
                    let hostedContainerDescription = describeViewIdentity(hostedContainerHit)
                    let descendantTextFieldDescription: String
                    if let textField = findDescendantTextField(in: hit) {
                        descendantTextFieldDescription = "UITextField@\(ObjectIdentifier(textField)); isFirstResponder=\(textField.isFirstResponder)"
                    } else {
                        descendantTextFieldDescription = "nil"
                    }
                    logLookupKeyboard(
                        "hitPopover",
                        popover: popover,
                        result: "overlayHit=\(overlayHitDescription); directContentHit=\(directHitDescription); hostedContainer=\(hostedContainerDescription); hostedTextField=\(hostedTextFieldDescription); returnHit=\(hitDescription); descendantTextField=\(descendantTextFieldDescription); directAncestors=\(ancestorChain(for: directContentHit)); directDescendants=\(descendantSnapshot(for: directContentHit)); returnGestures=\(gestureRecognizerSnapshot(for: hit)); directGestures=\(gestureRecognizerSnapshot(for: directContentHit))"
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
