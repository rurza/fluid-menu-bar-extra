//
//  PopoverPlacementPolicyTests.swift
//  FluidMenuBarExtraTests
//
//  Unit tests for PopoverPlacementPolicy
//
import XCTest
@testable import FluidMenuBarExtra

#if canImport(AppKit)
import AppKit
#endif

final class PopoverPlacementPolicyTests: XCTestCase {
    private let border: CGFloat = 2

    /// Built-in display, menu bar bottom at y=949. Measured on macOS 27.0 (26A5388g).
    private let builtIn = CGRect(x: 0, y: 87, width: 1512, height: 862)

    // MARK: - isUsableAnchor

    // The status item's button window reports these before it settles; both were measured
    // on macOS 27 within ~48ms of creating (or recreating) the item.

    func testRejectsZeroHeightAnchorAtOrigin() {
        XCTAssertFalse(
            PopoverPlacementPolicy.isUsableAnchor(CGRect(x: 0, y: 0, width: 27, height: 0)),
            "A zero-height frame at the origin is the pre-layout state, not a real anchor"
        )
    }

    func testRejectsNegativeOriginYAnchor() {
        XCTAssertFalse(
            PopoverPlacementPolicy.isUsableAnchor(CGRect(x: 0, y: -33, width: 27, height: 33)),
            "A negative origin.y is the intermediate pre-layout state, not a real anchor"
        )
    }

    func testAcceptsSettledAnchor() {
        XCTAssertTrue(
            PopoverPlacementPolicy.isUsableAnchor(CGRect(x: 1272, y: 949, width: 27, height: 33))
        )
    }

    // MARK: - Placement against a settled anchor (regression guard)

    func testAnchorsTopEdgeToStatusItemOriginY() {
        let p = PopoverPlacementPolicy.popoverTopLeft(
            statusItemFrame: CGRect(x: 1272, y: 949, width: 27, height: 33),
            popoverWidth: 300,
            screenVisibleFrame: builtIn,
            borderSize: border
        )
        XCTAssertEqual(p.y, 949, "Popover top must sit on the menu bar's bottom edge")
        // Right-aligned to the item because 1272 + 300 overflows maxX (1512).
        XCTAssertEqual(p.x, 1001, "Matches the placement measured in the running app")
    }

    func testDoesNotFlipWhenPopoverFitsToTheRight() {
        let p = PopoverPlacementPolicy.popoverTopLeft(
            statusItemFrame: CGRect(x: 400, y: 949, width: 27, height: 33),
            popoverWidth: 300,
            screenVisibleFrame: builtIn,
            borderSize: border
        )
        XCTAssertEqual(p.x, 398, "Should left-align to the item when there is room")
    }

    // MARK: - Multi-display: compare against maxX, not width

    func testDisplayWithNegativeOriginDoesNotOverflowTrailingEdge() {
        // External display to the LEFT of the built-in: visibleFrame.origin.x is negative, so
        // `visibleFrame.width` (1512) is far larger than `maxX` (0). Comparing against the
        // width fails to flip and leaves the popover hanging off the trailing edge.
        let screen = CGRect(x: -1512, y: 0, width: 1512, height: 862)
        let p = PopoverPlacementPolicy.popoverTopLeft(
            statusItemFrame: CGRect(x: -300, y: 862, width: 27, height: 33),
            popoverWidth: 380,
            screenVisibleFrame: screen,
            borderSize: border
        )
        XCTAssertLessThanOrEqual(
            p.x + 380, screen.maxX,
            "Popover must not extend past the trailing edge of a negative-origin display"
        )
    }

    func testDisplayWithPositiveOriginDoesNotFlipOffLeadingEdge() {
        // Built-in to the RIGHT of an external: origin.x 1512, maxX 3024. An item at x=1600 has
        // ample room to its right, but comparing against `width` (1512) flips it anyway and
        // pushes the popover off the leading edge of that display.
        let screen = CGRect(x: 1512, y: 0, width: 1512, height: 862)
        let p = PopoverPlacementPolicy.popoverTopLeft(
            statusItemFrame: CGRect(x: 1600, y: 862, width: 27, height: 33),
            popoverWidth: 380,
            screenVisibleFrame: screen,
            borderSize: border
        )
        XCTAssertGreaterThanOrEqual(
            p.x, screen.minX,
            "Popover must not be pushed off the leading edge of a positive-origin display"
        )
        XCTAssertEqual(p.x, 1598, "Should left-align to the item — there is room to its right")
    }

    // MARK: - Fallback when the anchor is not usable yet

    func testFallsBackBelowMenuBarWhenAnchorIsDegenerate() {
        let p = PopoverPlacementPolicy.popoverTopLeft(
            statusItemFrame: CGRect(x: 0, y: 0, width: 27, height: 0),
            popoverWidth: 300,
            screenVisibleFrame: builtIn,
            borderSize: border
        )
        XCTAssertEqual(p.y, builtIn.maxY, "Fallback must still hang below the menu bar")
        XCTAssertLessThanOrEqual(p.x + 300, builtIn.maxX)
        XCTAssertGreaterThanOrEqual(p.x, builtIn.minX)
    }

    func testFallsBackBelowMenuBarWhenAnchorIsMissing() {
        let p = PopoverPlacementPolicy.popoverTopLeft(
            statusItemFrame: nil,
            popoverWidth: 300,
            screenVisibleFrame: builtIn,
            borderSize: border
        )
        XCTAssertEqual(p.y, builtIn.maxY)
        XCTAssertLessThanOrEqual(p.x + 300, builtIn.maxX)
    }

    // MARK: - rebase: the pending-resize race

    func testRebaseKeepsTheWindowWhereItWasJustMoved() {
        // Real values traced on macOS 27: the pending target was computed while the window was
        // still unpositioned near the origin; setWindowPosition() then moved it to (1014, 624).
        // Applying the pending frame as-is put it back at (0, -340) — off screen.
        let pending = CGRect(x: 0, y: -340, width: 300, height: 340)
        let current = CGRect(x: 1014, y: 624, width: 287, height: 325)

        let rebased = PopoverPlacementPolicy.rebase(pendingFrame: pending, onto: current)

        XCTAssertEqual(rebased.origin.x, 1014, "Must keep the position setWindowPosition() applied")
        XCTAssertEqual(rebased.maxY, current.maxY, "Must keep the top edge anchored")
        XCTAssertEqual(rebased.width, 300, "Must still apply the pending size")
        XCTAssertEqual(rebased.height, 340)
    }

    func testRebaseGrowsDownwardFromAFixedTop() {
        let current = CGRect(x: 100, y: 600, width: 300, height: 349)
        let pending = CGRect(x: 100, y: 560, width: 300, height: 389)

        let rebased = PopoverPlacementPolicy.rebase(pendingFrame: pending, onto: current)

        XCTAssertEqual(rebased.maxY, 949, "Top stays put while the window grows downward")
        XCTAssertEqual(rebased.origin.y, 560)
    }

    // MARK: - clampHorizontally

    func testClampPullsBackAWindowThatGrewOffTheTrailingEdge() {
        // Positioned while still zero-width (right after the status item was created), then
        // resized to its real width — which pushes it straight off the trailing edge.
        let grown = CGRect(x: 2558, y: 1070, width: 300, height: 340)
        let screen = CGRect(x: 0, y: 87, width: 2560, height: 1323)

        let clamped = PopoverPlacementPolicy.clampHorizontally(grown, to: screen)

        XCTAssertEqual(clamped.maxX, screen.maxX, "Must be pulled flush with the trailing edge")
        XCTAssertEqual(clamped.origin.y, grown.origin.y, "Vertical placement must be untouched")
        XCTAssertEqual(clamped.size, grown.size, "Size must be untouched")
    }

    func testClampLeavesAnOnScreenFrameAlone() {
        let onScreen = CGRect(x: 1001, y: 609, width: 300, height: 340)
        XCTAssertEqual(
            PopoverPlacementPolicy.clampHorizontally(onScreen, to: builtIn), onScreen
        )
    }

    func testClampRespectsALeadingEdgeOffset() {
        // Display whose origin.x is not 0 — clamping must use its edges, not 0.
        let screen = CGRect(x: 1512, y: 0, width: 1512, height: 862)
        let offLeading = CGRect(x: 1400, y: 800, width: 300, height: 340)

        let clamped = PopoverPlacementPolicy.clampHorizontally(offLeading, to: screen)

        XCTAssertEqual(clamped.origin.x, 1512, "Must clamp to that display's leading edge, not 0")
    }

    func testClampLeavesAFrameWiderThanTheScreenAlone() {
        let tooWide = CGRect(x: -50, y: 0, width: 2000, height: 340)
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 862)
        XCTAssertEqual(
            PopoverPlacementPolicy.clampHorizontally(tooWide, to: screen), tooWide,
            "Nothing sensible to clamp to — leave it rather than shunting it around"
        )
    }

    func testRebaseIsIdentityWhenTheWindowHasNotMoved() {
        let current = CGRect(x: 1001, y: 609, width: 300, height: 340)
        let pending = CGRect(x: 1001, y: 589, width: 300, height: 360)

        let rebased = PopoverPlacementPolicy.rebase(pendingFrame: pending, onto: current)

        XCTAssertEqual(rebased, pending, "No move in between means the target is already correct")
    }
}
