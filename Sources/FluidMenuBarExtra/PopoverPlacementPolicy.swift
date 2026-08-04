//
//  PopoverPlacementPolicy.swift
//  FluidMenuBarExtra
//
//  Pure placement policy for popover windows
//
#if canImport(AppKit)
import AppKit
#endif

/// Placement policy for popover windows.
///
/// Pure geometry, kept out of `FluidMenuBarExtraStatusItem`/`FluidMenuBarExtraWindow` so the
/// three failure modes below are testable without a real status item or window server.
public enum PopoverPlacementPolicy {
    /// Whether the status item's button window frame can be used as a placement anchor.
    ///
    /// `NSStatusItem.button?.window?.frame` is not valid immediately after the item is created
    /// or recreated: it reports a zero-height frame at the origin, then a frame with a negative
    /// `origin.y`, before settling. Anchoring to either strands the popover off screen, so the
    /// caller must fall back rather than trust it.
    public static func isUsableAnchor(_ frame: CGRect) -> Bool {
        frame.width > 0 && frame.height > 0 && frame.origin.y > 0
    }

    /// The top-left point the popover window should be moved to.
    ///
    /// - Parameters:
    ///   - statusItemFrame: The status item button window's frame, or `nil` if unavailable.
    ///   - popoverWidth: The popover window's current width.
    ///   - screenVisibleFrame: The anchoring screen's `visibleFrame`.
    ///   - borderSize: Offset that aligns the popover with the highlighted button.
    public static func popoverTopLeft(
        statusItemFrame: CGRect?,
        popoverWidth: CGFloat,
        screenVisibleFrame: CGRect,
        borderSize: CGFloat
    ) -> CGPoint {
        var x: CGFloat
        var y: CGFloat

        if let statusItemFrame, isUsableAnchor(statusItemFrame) {
            y = statusItemFrame.origin.y
            // Flip to right-align when the popover would overflow the screen's trailing edge.
            //
            // This compares against `maxX`, NOT `width`. They coincide only on a screen whose
            // `origin.x` is 0; on any other display in a multi-display arrangement comparing
            // against the width flips on the wrong side of the boundary — too eagerly when
            // `origin.x` is positive, and not at all when it is negative, which leaves the
            // popover hanging off the trailing edge.
            if statusItemFrame.origin.x + popoverWidth > screenVisibleFrame.maxX {
                x = statusItemFrame.maxX - popoverWidth + borderSize
            } else {
                x = statusItemFrame.origin.x - borderSize
            }
        } else {
            // No usable anchor yet. Sit just below the menu bar at the trailing edge, where
            // status items live, instead of centring the popover in the middle of the screen.
            y = screenVisibleFrame.maxY
            x = screenVisibleFrame.maxX - popoverWidth - borderSize
        }

        // Never place the popover off the trailing or leading edge.
        let maxX = screenVisibleFrame.maxX - popoverWidth
        if x > maxX { x = maxX }
        if x < screenVisibleFrame.minX { x = screenVisibleFrame.minX }

        return CGPoint(x: x, y: y)
    }

    /// Rebases a pending resize target onto the window's current frame.
    ///
    /// `contentSizeDidUpdate` computes its target from the frame as it stood when SwiftUI
    /// reported a new content size, but the target is applied a runloop turn later — and
    /// `setWindowPosition()` may have moved the window in between, on the open path. Applying
    /// the stale origin silently discards that move, so the popover is positioned correctly and
    /// then dragged back. Only the *size* of the pending target is still meaningful; the origin
    /// has to be re-derived from where the window actually is, keeping its top-left anchored.
    public static func rebase(pendingFrame: CGRect, onto current: CGRect) -> CGRect {
        CGRect(
            x: current.origin.x,
            y: current.maxY - pendingFrame.height,
            width: pendingFrame.width,
            height: pendingFrame.height
        )
    }

    /// Pulls a frame back inside the screen's trailing and leading edges.
    ///
    /// A resize keeps the window's left edge, so a window that was positioned while it was
    /// narrower than its final width — the popover is briefly zero-width right after the status
    /// item is created — grows straight off the trailing edge. Placement is only ever correct
    /// for the width the window had at the time, so the frame has to be re-clamped once the
    /// real width is known.
    public static func clampHorizontally(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        guard frame.width <= visibleFrame.width else { return frame }

        var clamped = frame
        if clamped.maxX > visibleFrame.maxX {
            clamped.origin.x = visibleFrame.maxX - clamped.width
        }
        if clamped.origin.x < visibleFrame.minX {
            clamped.origin.x = visibleFrame.minX
        }
        return clamped
    }
}
