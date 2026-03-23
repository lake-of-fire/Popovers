//
//  Popover+Calculations.swift
//
//
//  Created by A. Zheng (github.com/aheze) on 3/19/23.
//  Copyright © 2023 A. Zheng. All rights reserved.
//

#if os(iOS)
import SwiftUI

public extension Popover {
    /// Updates the popover's frame using its size.
    @MainActor
    func updateFrame(with size: CGSize?) {
        let frame = calculateFrame(from: size)
        context.size = size
        context.staticFrame = frame
        context.frame = frame
        context.offset = CGSize(width: frame.origin.x, height: frame.origin.y)
    }

    /// Calculate the popover's frame based on its size and position.
    @MainActor
    func calculateFrame(from size: CGSize?) -> CGRect {
        guard let window = context.presentedPopoverViewController?.view.window else { return .zero }
        let screenEdgePadding = attributes.screenEdgePadding()
        let safeWindowFrame = availableWindowFrame(
            in: window,
            keyboardFrame: context.keyboardFrameInWindow,
            screenEdgePadding: screenEdgePadding
        )
        var popoverFrame = CGRect.zero

        switch attributes.position {
        case let .absolute(originAnchor, popoverAnchor):
            popoverFrame = attributes.position.absoluteFrame(
                originAnchor: originAnchor,
                popoverAnchor: popoverAnchor,
                originFrame: attributes.sourceFrame().inset(by: attributes.sourceFrameInset()),
                popoverSize: size ?? .zero
            )
        case let .relative(popoverAnchors):

            /// Set the selected anchor to the first one.
            if context.selectedAnchor == nil {
                context.selectedAnchor = popoverAnchors.first
            }

            popoverFrame = attributes.position.relativeFrame(
                selectedAnchor: context.selectedAnchor ?? popoverAnchors.first ?? .bottom,
                containerFrame: attributes.sourceFrame().inset(by: attributes.sourceFrameInset()),
                popoverSize: size ?? .zero
            )
        }

        return clamp(popoverFrame, to: safeWindowFrame, screenEdgePadding: screenEdgePadding)
    }

    /// Calculate if the popover should be dismissed via drag **or** animated to another position (if using `.relative` positioning with multiple anchors). Called when the user stops dragging the popover.
    @MainActor
    func positionChanged(to point: CGPoint) {
        let windowBounds = context.windowBounds

        if
            attributes.dismissal.mode.contains(.dragDown),
            point.y >= windowBounds.height - windowBounds.height * attributes.dismissal.dragDismissalProximity
        {
            if attributes.dismissal.dragMovesPopoverOffScreen {
                var newFrame = context.staticFrame
                newFrame.origin.y = windowBounds.height
                context.staticFrame = newFrame
                context.frame = newFrame
            }
            dismiss()
            return
        }
        if
            attributes.dismissal.mode.contains(.dragUp),
            point.y <= windowBounds.height * attributes.dismissal.dragDismissalProximity
        {
            if attributes.dismissal.dragMovesPopoverOffScreen {
                var newFrame = context.staticFrame
                newFrame.origin.y = -newFrame.height
                context.staticFrame = newFrame
                context.frame = newFrame
            }
            dismiss()
            return
        }

        if case let .relative(popoverAnchors) = attributes.position {
            let frame = attributes.sourceFrame().inset(by: attributes.sourceFrameInset())
            let size = context.size ?? .zero

            let closestAnchor = attributes.position.relativeClosestAnchor(
                popoverAnchors: popoverAnchors,
                containerFrame: frame,
                popoverSize: size,
                targetPoint: point
            )
            let popoverFrame = attributes.position.relativeFrame(
                selectedAnchor: closestAnchor,
                containerFrame: frame,
                popoverSize: size
            )

            context.selectedAnchor = closestAnchor
            context.staticFrame = popoverFrame
            context.frame = popoverFrame
        }
    }
}

@MainActor
private func clamp(
    _ popoverFrame: CGRect,
    to availableFrame: CGRect,
    screenEdgePadding: UIEdgeInsets
) -> CGRect {
    var popoverFrame = popoverFrame
    let minX = availableFrame.minX + screenEdgePadding.left
    let minY = availableFrame.minY + screenEdgePadding.top
    let maxX = availableFrame.maxX - screenEdgePadding.right
    let maxY = availableFrame.maxY - screenEdgePadding.bottom

    if popoverFrame.origin.x < minX {
        popoverFrame.origin.x = minX
    }
    if popoverFrame.origin.y < minY {
        popoverFrame.origin.y = minY
    }
    if popoverFrame.maxX > maxX {
        popoverFrame.origin.x -= (popoverFrame.maxX - maxX)
    }
    if popoverFrame.maxY > maxY {
        popoverFrame.origin.y -= (popoverFrame.maxY - maxY)
    }

    if popoverFrame.origin.x < minX {
        popoverFrame.origin.x = minX
    }
    if popoverFrame.origin.y < minY {
        popoverFrame.origin.y = minY
    }

    return popoverFrame
}

@MainActor
private func availableWindowFrame(
    in window: UIWindow,
    keyboardFrame: CGRect,
    screenEdgePadding: UIEdgeInsets
) -> CGRect {
    var safeWindowFrame = window.safeAreaLayoutGuide.layoutFrame
    let overlappingKeyboardFrame = safeWindowFrame.intersection(keyboardFrame)
    let keyboardTouchesBottomEdge =
        !keyboardFrame.isEmpty &&
        keyboardFrame.maxY >= safeWindowFrame.maxY &&
        keyboardFrame.minY < safeWindowFrame.maxY

    if
        keyboardTouchesBottomEdge,
        !overlappingKeyboardFrame.isNull,
        !overlappingKeyboardFrame.isEmpty
    {
        safeWindowFrame.size.height = max(
            0,
            overlappingKeyboardFrame.minY - safeWindowFrame.minY
        )
    }

    if safeWindowFrame.width < screenEdgePadding.left + screenEdgePadding.right {
        safeWindowFrame.size.width = screenEdgePadding.left + screenEdgePadding.right
    }
    if safeWindowFrame.height < screenEdgePadding.top + screenEdgePadding.bottom {
        safeWindowFrame.size.height = screenEdgePadding.top + screenEdgePadding.bottom
    }

    return safeWindowFrame
}
#endif
