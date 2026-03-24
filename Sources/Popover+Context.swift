//
//  Popover+Context.swift
//
//
//  Created by A. Zheng (github.com/aheze) on 3/19/23.
//  Copyright © 2023 A. Zheng. All rights reserved.
//

#if os(iOS)
import Combine
import SwiftUI

private func lookupKeyboardPopoverContextDelta(_ oldRect: CGRect, _ newRect: CGRect) -> String {
    "dx=\(newRect.origin.x - oldRect.origin.x); dy=\(newRect.origin.y - oldRect.origin.y); dw=\(newRect.size.width - oldRect.size.width); dh=\(newRect.size.height - oldRect.size.height)"
}

private func logLookupKeyboardPopoverContext(
    _ stage: String,
    popoverID: UUID,
    result: String
) {
    debugPrint(
        "# LOOKUPKEYBOARD",
        [
            "stage": stage,
            "popoverID": popoverID.uuidString,
            "result": result
        ] as [String: Any]
    )
}

public extension Popover {
    /**
     The popover's view model (stores attributes, frame, and other visible traits).
     */
    class Context: Identifiable, ObservableObject {
        /// The popover's ID. Must be unique, unless replacing an existing popover.
        public var id = UUID()
        
        /// The popover's customizable properties.
        public var attributes = Attributes()
        
        @MainActor
        @Published internal var presentationID = UUID()
        @MainActor
        @Published internal var isOffsetInitialized = false
        @MainActor
        @Published internal var offset: CGSize = .zero {
            didSet {
                guard oldValue != offset else { return }
                logLookupKeyboardPopoverContext(
                    "popoverContext.offsetSet",
                    popoverID: id,
                    result: "old={\(oldValue.width), \(oldValue.height)}; new={\(offset.width), \(offset.height)}"
                )
            }
        }

        /// The popover's dynamic size, calculated from SwiftUI. If this is `nil`, the popover is not yet ready to be displayed.
        @MainActor
        @Published public var size: CGSize?
        
        /// The frame of the popover, without drag gesture offset applied.
        @MainActor
        @Published public var staticFrame = CGRect.zero {
            didSet {
                guard oldValue != staticFrame else { return }
                logLookupKeyboardPopoverContext(
                    "popoverContext.staticFrameSet",
                    popoverID: id,
                    result: "old=\(NSCoder.string(for: oldValue)); new=\(NSCoder.string(for: staticFrame)); delta=\(lookupKeyboardPopoverContextDelta(oldValue, staticFrame))"
                )
            }
        }
        
        /// The current frame of the popover.
        @MainActor
        @Published public var frame = CGRect.zero {
            didSet {
                guard oldValue != frame else { return }
                logLookupKeyboardPopoverContext(
                    "popoverContext.frameSet",
                    popoverID: id,
                    result: "old=\(NSCoder.string(for: oldValue)); new=\(NSCoder.string(for: frame)); delta=\(lookupKeyboardPopoverContextDelta(oldValue, frame))"
                )
            }
        }

        /// The visible keyboard frame converted into window coordinates.
        @MainActor
        @Published internal var keyboardFrameInWindow = CGRect.zero {
            didSet {
                guard oldValue != keyboardFrameInWindow else { return }
                logLookupKeyboardPopoverContext(
                    "popoverContext.keyboardFrameSet",
                    popoverID: id,
                    result: "old=\(NSCoder.string(for: oldValue)); new=\(NSCoder.string(for: keyboardFrameInWindow)); delta=\(lookupKeyboardPopoverContextDelta(oldValue, keyboardFrameInWindow))"
                )
            }
        }
//        let ee = UUID().uuidString.prefix(6)
        
        /// The currently selected anchor, if the popover has a `.relative` position.
        @MainActor
        @Published public var selectedAnchor: Popover.Attributes.Position.Anchor?
        
        /// If this is true, the popover is the replacement of another popover.
        @MainActor
        @Published public var isReplacement = false
        
        /// Notify when the context changed.
        public var changeSink: AnyCancellable?
        
        /// Indicates whether the popover can be dragged.
        @MainActor
        public var isDraggingEnabled: Bool {
            get {
                popoverModel?.popoversDraggable ?? false
            }
            set {
                popoverModel?.popoversDraggable = newValue
            }
        }
        
        public var window: UIWindow {
            if let window = presentedPopoverViewController?.view.window {
                return window
            } else {
                print("[Popovers] - This popover is not tied to a window. Please file a bug report (https://github.com/aheze/Popovers/issues).")
                return UIWindow()
            }
        }
        
        /**
         The bounds of the window in which the `Popover` is being presented, or the `zero` frame if the popover has not been presented yet.
         */
        public var windowBounds: CGRect {
            presentedPopoverViewController?.view.window?.bounds ?? .zero
        }
        
        /**
         For the SwiftUI `.popover` view modifier. This is for internal use only - use `Popover.Attributes.onDismiss` if you want to know when the popover is dismissed.
         
         This is called just after the popover is removed from the model - inside the view modifier, set `$present` to false when this is called.
         */
        internal var onAutoDismiss: (() -> Void)?
        
        /// Invoked by the SwiftUI container view when the view has fully disappeared.
        internal var onDisappear: (() -> Void)?
        
        /// The `PopoverContainerViewController` presenting this `Popover`, or `nil` if the popover is currently not being presented.
        public var presentedPopoverViewController: PopoverContainerViewController?
        
        internal var windowSublayersKeyValueObservationToken: NSKeyValueObservation?
        
        /// The `PopoverModel` managing the `Popover`. Sourced from the `presentedPopoverViewController`.
        private var popoverModel: PopoverModel? {
            return presentedPopoverViewController?.view.popoverModel
        }
        
        /// Create a context for the popover. You shouldn't need to use this - it's done automatically when you create a new popover.
        public init() {
            changeSink = objectWillChange.sink { @MainActor [weak self] in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.attributes.onContextChange?(self)
                }
            }
        }
    }
}
#endif
