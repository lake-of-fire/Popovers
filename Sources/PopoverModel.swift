//
//  PopoverModel.swift
//  Popovers
//
//  Created by A. Zheng (github.com/aheze) on 12/23/21.
//  Copyright © 2022 A. Zheng. All rights reserved.
//

#if os(iOS)
import Combine
import SwiftUI

func lookupKeyboardRectDeltaDescription(_ oldRect: CGRect, _ newRect: CGRect) -> String {
    let deltaX = newRect.origin.x - oldRect.origin.x
    let deltaY = newRect.origin.y - oldRect.origin.y
    let deltaWidth = newRect.size.width - oldRect.size.width
    let deltaHeight = newRect.size.height - oldRect.size.height
    return "dx=\(deltaX); dy=\(deltaY); dw=\(deltaWidth); dh=\(deltaHeight)"
}

private func lookupKeyboardSizeDeltaDescription(_ oldSize: CGSize?, _ newSize: CGSize?) -> String {
    switch (oldSize, newSize) {
    case let (old?, new?):
        return "dw=\(new.width - old.width); dh=\(new.height - old.height)"
    case (nil, let new?):
        return "old=nil; new={\(new.width), \(new.height)}"
    case let (old?, nil):
        return "old={\(old.width), \(old.height)}; new=nil"
    case (nil, nil):
        return "old=nil; new=nil"
    }
}

/**
 The view model for presented popovers within a window.

 Each view model is scoped to a window, which retains the view model.
 Presenting or otherwise managing a popover automatically scopes interactions to the window of the current view hierarchy.
 */
public class PopoverModel: ObservableObject {
    static let shared = PopoverModel()
    private var pendingRefreshWorkItem: DispatchWorkItem?
    
    /// The currently-presented popovers. The oldest are in front, the newest at the end.
//    @Published var popovers = [Popover]()
    @MainActor
    @Published var popover: Popover?

    /// Determines if the popovers can be dragged.
    @MainActor
    @Published var popoversDraggable = true

    /// Store the frames of views (for excluding popover dismissal or source frames).
    @MainActor
    @Published var frameTags: [AnyHashable: CGRect] = [:]

    /**
     Store frames of popover source views when presented using `.popover(selection:tag:attributes:view:)`. These frames are then used as excluded frames for dismissal.

     To opt out of this behavior, set `attributes.dismissal.excludedFrames` manually. To clear this array (usually when you present another view where the frames don't apply), use a `FrameTagReader` to call `FrameTagProxy.clearSavedFrames()`.
     */
    @MainActor
    @Published var selectionFrameTags: [AnyHashable: CGRect] = [:]

    /// Force the container view to update.
    func reload() {
        objectWillChange.send()
    }

    /**
     Refresh the popovers with a new transaction.

     This is called when the screen bounds changes - by setting a transaction for each popover,
     the `PopoverContainerView` knows that it needs to animate a change (processed in `sizeReader`).
     */
    func refresh() {
        /// Update all popovers.
        reload()
    }

    /// Adds a `Popover` to this model.
    @MainActor
    func add(_ popover: Popover) {
        if self.popover == nil {
            self.popover = popover
        }
//        popovers.append(popover)
    }

    /// Removes a `Popover` from this model.
//    func remove(_ popover: Popover) {
//        debugPrint("# remove(popover)")
//        popovers.removeAll { $0 == popover }
//    }

    /**
     Remove all popovers, or optionally the ones tagged with a `tag` that you supply.
     - parameter tag: If this isn't nil, only remove popovers tagged with this.
     */
//    func removeAllPopovers(with tag: AnyHashable? = nil) {
//        debugPrint("# removeAllPopovers")
//        if let tag = tag {
//            popovers.removeAll(where: { $0.attributes.tag == tag })
//        } else {
//            popovers.removeAll()
//        }
//    }

    /// Get the index in the for a popover. Returns `nil` if the popover is not in the array.
//    func index(of popover: Popover) -> Int? {
//        return popovers.firstIndex(of: popover)
//    }

    /**
     Get a currently-presented popover with a tag. Returns `nil` if no popover with the tag was found.
     - parameter tag: The tag of the popover to look for.
     */
//    func popover(tagged tag: AnyHashable) -> Popover? {
//        let matchingPopovers = popovers.filter { $0.attributes.tag == tag }
//        if matchingPopovers.count > 1 {
//            print("[Popovers] - Warning - There are \(matchingPopovers.count) popovers tagged '\(tag)'. Tags should be unique. Try dismissing all existing popovers first.")
//        }
//        return matchingPopovers.first
//    }

    /**
     Update all popover frames.

     This is called when the device rotates or has a bounds change.
     */
    @MainActor
    func updateFramesAfterBoundsChange() {
        /**
         First, update all popovers anyway.

         For some reason, relative positioning + `.center` doesn't need the rotation animation to complete before having a size change.
         */
//        for popover in popovers {
//            popover.updateFrame(with: popover.context.size)
//        }
        if let popover {
            let oldFrame = popover.context.frame
            let oldStaticFrame = popover.context.staticFrame
            let oldSize = popover.context.size
            popover.updateFrame(with: popover.context.size)
            let didChange = oldFrame != popover.context.frame
                || oldStaticFrame != popover.context.staticFrame
                || oldSize != popover.context.size
            debugPrint(
                "# LOOKUPKEYBOARD",
                [
                    "stage": "popoverModel.updateFramesAfterBoundsChange",
                    "popoverID": popover.id.uuidString,
                    "result": "frameOld=\(NSCoder.string(for: oldFrame)); frameNew=\(NSCoder.string(for: popover.context.frame)); frameDelta=\(lookupKeyboardRectDeltaDescription(oldFrame, popover.context.frame)); staticOld=\(NSCoder.string(for: oldStaticFrame)); staticNew=\(NSCoder.string(for: popover.context.staticFrame)); staticDelta=\(lookupKeyboardRectDeltaDescription(oldStaticFrame, popover.context.staticFrame)); sizeDelta=\(lookupKeyboardSizeDeltaDescription(oldSize, popover.context.size)); changed=\(didChange)"
                ] as [String: Any]
            )
            guard didChange else { return }
        }

        /// Reload the container view.
        reload()

        /// Some other popovers need to wait until the rotation has completed before updating.
        pendingRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let popover = self.popover else { return }
            let oldFrame = popover.context.frame
            let oldStaticFrame = popover.context.staticFrame
            let oldSize = popover.context.size
            popover.updateFrame(with: popover.context.size)
            let didChange = oldFrame != popover.context.frame
                || oldStaticFrame != popover.context.staticFrame
                || oldSize != popover.context.size
            debugPrint(
                "# LOOKUPKEYBOARD",
                [
                    "stage": "popoverModel.delayedRefresh",
                    "popoverID": popover.id.uuidString,
                    "result": "frameOld=\(NSCoder.string(for: oldFrame)); frameNew=\(NSCoder.string(for: popover.context.frame)); frameDelta=\(lookupKeyboardRectDeltaDescription(oldFrame, popover.context.frame)); staticOld=\(NSCoder.string(for: oldStaticFrame)); staticNew=\(NSCoder.string(for: popover.context.staticFrame)); staticDelta=\(lookupKeyboardRectDeltaDescription(oldStaticFrame, popover.context.staticFrame)); sizeDelta=\(lookupKeyboardSizeDeltaDescription(oldSize, popover.context.size)); changed=\(didChange)"
                ] as [String: Any]
            )
            guard didChange else { return }
            self.refresh()
        }
        pendingRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Popovers.frameUpdateDelayAfterBoundsChange, execute: workItem)
    }

    /// Access this with `UIResponder.frameTagged(_:)` if inside a `WindowReader`, or `Popover.Context.frameTagged(_:)` if inside a `PopoverReader.`
    @MainActor
    func frame(tagged tag: AnyHashable) -> CGRect {
        let frame = frameTags[tag]
        return frame ?? .zero
    }
}
#endif
