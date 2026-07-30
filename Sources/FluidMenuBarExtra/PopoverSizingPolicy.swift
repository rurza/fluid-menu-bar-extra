//
//  PopoverSizingPolicy.swift
//  FluidMenuBarExtra
//
//  Pure sizing policy for popover content size validation
//
#if canImport(AppKit)
import AppKit
#endif

/// Sizing policy for popover windows.
///
/// Decides whether a content size reported by SwiftUI should be applied to the popover window.
///
/// Degenerate transient heights (produced mid-animation) must be rejected so the reused
/// borderless window is never stranded at a collapsed frame. `minimumHeight` is an absolute
/// floor supplied by the caller (e.g. the hosting view's intrinsic content size height, or a
/// small absolute backstop). NOTE: do NOT use a relative-to-last-height heuristic here —
/// legitimate large shrinks (e.g. hiding panels 700pt→220pt) must still be accepted.
public enum PopoverSizingPolicy {
    /// Decides whether a content size reported by SwiftUI should be applied to the popover window.
    ///
    /// - Parameters:
    ///   - proposed: The content size reported by SwiftUI
    ///   - minimumHeight: The absolute minimum acceptable height
    /// - Returns: `true` if the size should be applied, `false` if it should be rejected
    public static func shouldAcceptContentSize(
        proposed: CGSize,
        minimumHeight: CGFloat
    ) -> Bool {
        proposed.width > 0 && proposed.height >= minimumHeight
    }
}