//
//  Popover+Calculations.swift
//
//
//  Created by A. Zheng (github.com/aheze) on 3/19/23.
//  Copyright © 2023 A. Zheng. All rights reserved.
//

#if os(iOS)
import SwiftUI

private func lookupKeyboardRectDeltaDescriptionInCalculations(_ oldRect: CGRect, _ newRect: CGRect) -> String {
    "dx=\(newRect.origin.x - oldRect.origin.x); dy=\(newRect.origin.y - oldRect.origin.y); dw=\(newRect.size.width - oldRect.size.width); dh=\(newRect.size.height - oldRect.size.height)"
}

private func lookupKeyboardAnchorDescription(_ anchor: Popover.Attributes.Position.Anchor?) -> String {
    guard let anchor else { return "nil" }
    switch anchor {
    case .topLeft: return "topLeft"
    case .top: return "top"
    case .topRight: return "topRight"
    case .right: return "right"
    case .bottomRight: return "bottomRight"
    case .bottom: return "bottom"
    case .bottomLeft: return "bottomLeft"
    case .left: return "left"
    case .center: return "center"
    }
}

public extension Popover {
    /// Updates the popover's frame using its size.
    @MainActor
    func updateFrame(with size: CGSize?) {
        let oldFrame = context.frame
        let oldStaticFrame = context.staticFrame
        let oldOffset = context.offset
        let frame = calculateFrame(from: size)
        let newOffset = CGSize(width: frame.origin.x, height: frame.origin.y)

        if context.size != size {
            context.size = size
        }
        if context.staticFrame != frame {
            context.staticFrame = frame
        }
        if context.frame != frame {
            context.frame = frame
        }
        if context.offset != newOffset {
            context.offset = newOffset
        }
        debugPrint(
            "# LOOKUPKEYBOARD",
            [
                "stage": "popover.updateFrame",
                "popoverID": id.uuidString,
                "result": "frameOld=\(NSCoder.string(for: oldFrame)); frameNew=\(NSCoder.string(for: context.frame)); frameDelta=\(lookupKeyboardRectDeltaDescriptionInCalculations(oldFrame, context.frame)); staticOld=\(NSCoder.string(for: oldStaticFrame)); staticNew=\(NSCoder.string(for: context.staticFrame)); staticDelta=\(lookupKeyboardRectDeltaDescriptionInCalculations(oldStaticFrame, context.staticFrame)); offsetOld={\(oldOffset.width), \(oldOffset.height)}; offsetNew={\(context.offset.width), \(context.offset.height)}; changed=\(oldFrame != context.frame || oldStaticFrame != context.staticFrame || oldOffset != context.offset)"
            ] as [String: Any]
        )
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
        let sourceFrame = attributes.sourceFrame().inset(by: attributes.sourceFrameInset())
        let popoverSize = size ?? .zero
        var popoverFrame = CGRect.zero
        let selectedAnchorDescription: String

        switch attributes.position {
        case let .absolute(originAnchor, popoverAnchor):
            selectedAnchorDescription = "absolute(origin=\(lookupKeyboardAnchorDescription(originAnchor)); popover=\(lookupKeyboardAnchorDescription(popoverAnchor)))"
            popoverFrame = attributes.position.absoluteFrame(
                originAnchor: originAnchor,
                popoverAnchor: popoverAnchor,
                originFrame: sourceFrame,
                popoverSize: popoverSize
            )
        case let .relative(popoverAnchors):

            /// Set the selected anchor to the first one.
            if context.selectedAnchor == nil {
                context.selectedAnchor = popoverAnchors.first
            }
            let selectedAnchor = context.selectedAnchor ?? popoverAnchors.first ?? .bottom
            let candidateAnchors = popoverAnchors
                .map(lookupKeyboardAnchorDescription)
                .joined(separator: ",")
            selectedAnchorDescription = "relative(selected=\(lookupKeyboardAnchorDescription(selectedAnchor)); candidates=\(candidateAnchors))"

            popoverFrame = attributes.position.relativeFrame(
                selectedAnchor: selectedAnchor,
                containerFrame: sourceFrame,
                popoverSize: popoverSize
            )
        }

        let clampedFrame = clamp(popoverFrame, to: safeWindowFrame, screenEdgePadding: screenEdgePadding)
        debugPrint(
            "# LOOKUPKEYBOARD",
            [
                "stage": "popover.calculateFrame",
                "popoverID": id.uuidString,
                "result": "sourceFrame=\(NSCoder.string(for: sourceFrame)); popoverSize={\(popoverSize.width), \(popoverSize.height)}; selectedAnchor=\(selectedAnchorDescription); availableFrame=\(NSCoder.string(for: safeWindowFrame)); unclampedFrame=\(NSCoder.string(for: popoverFrame)); clampedFrame=\(NSCoder.string(for: clampedFrame)); keyboardFrame=\(NSCoder.string(for: context.keyboardFrameInWindow)); screenEdgePadding={top=\(screenEdgePadding.top), left=\(screenEdgePadding.left), bottom=\(screenEdgePadding.bottom), right=\(screenEdgePadding.right)}"
            ] as [String: Any]
        )

        return clampedFrame
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
