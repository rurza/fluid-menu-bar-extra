//
//  PopoverSizingPolicyTests.swift
//  FluidMenuBarExtraTests
//
//  Unit tests for PopoverSizingPolicy
//
import XCTest
@testable import FluidMenuBarExtra

#if canImport(AppKit)
import AppKit
#endif

final class PopoverSizingPolicyTests: XCTestCase {
    // MARK: - Reject degenerate sizes

    func testRejectsNearZeroHeight() {
        // Reject a near-zero height (e.g., 3pt) even if width is valid
        let result = PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: CGSize(width: 300, height: 3),
            minimumHeight: 80
        )
        XCTAssertFalse(result, "Should reject near-zero height (3pt)")
    }

    func testRejectsZeroWidth() {
        // Reject zero width even if height is large
        let result = PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: CGSize(width: 0, height: 400),
            minimumHeight: 80
        )
        XCTAssertFalse(result, "Should reject zero width")
    }

    func testRejectsNegativeHeight() {
        // Reject negative height
        let result = PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: CGSize(width: 300, height: -10),
            minimumHeight: 80
        )
        XCTAssertFalse(result, "Should reject negative height")
    }

    func testRejectsLiteralZeroHeight() {
        // Reject literal zero height
        let result = PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: CGSize(width: 300, height: 0),
            minimumHeight: 80
        )
        XCTAssertFalse(result, "Should reject literal zero height")
    }

    func testRejectsNegativeWidth() {
        // Reject negative width even if height is valid
        let result = PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: CGSize(width: -5, height: 400),
            minimumHeight: 80
        )
        XCTAssertFalse(result, "Should reject negative width")
    }

    // MARK: - Accept valid sizes

    func testAcceptsHeightEqualToFloor() {
        // Accept height exactly equal to minimumHeight (boundary case)
        let result = PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: CGSize(width: 300, height: 80),
            minimumHeight: 80
        )
        XCTAssertTrue(result, "Should accept height equal to minimum floor")
    }

    func testAcceptsLegitimateSmallHeightAboveFloor() {
        // Accept a small-but-real height above the floor
        let result = PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: CGSize(width: 300, height: 100),
            minimumHeight: 80
        )
        XCTAssertTrue(result, "Should accept legitimate small height above floor")
    }

    func testAcceptsLargeHeight() {
        // Accept a large height
        let result = PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: CGSize(width: 300, height: 700),
            minimumHeight: 80
        )
        XCTAssertTrue(result, "Should accept large height")
    }

    // MARK: - Critical case: legitimate large shrink

    func testAcceptsLegitimateLargeShrink_From700To220() {
        // The critical case: hiding panels (700pt → 220pt) is a valid large shrink
        // and must NOT be rejected. This is why we use an absolute floor, not relative.
        let result1 = PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: CGSize(width: 300, height: 700),
            minimumHeight: 80
        )
        let result2 = PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: CGSize(width: 300, height: 220),
            minimumHeight: 80
        )
        XCTAssertTrue(result1, "Should accept large height (700pt)")
        XCTAssertTrue(result2, "Should accept legitimate large shrink to 220pt")
    }

    func testAcceptsLegitimateLargeShrink_From500To100() {
        // Another large shrink that should be accepted
        let result1 = PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: CGSize(width: 300, height: 500),
            minimumHeight: 80
        )
        let result2 = PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: CGSize(width: 300, height: 100),
            minimumHeight: 80
        )
        XCTAssertTrue(result1, "Should accept large height (500pt)")
        XCTAssertTrue(result2, "Should accept legitimate large shrink to 100pt")
    }

    // MARK: - Edge cases

    func testAcceptsWidthExactlyOne() {
        // Accept width of exactly 1 with valid height
        let result = PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: CGSize(width: 1, height: 200),
            minimumHeight: 80
        )
        XCTAssertTrue(result, "Should accept width of exactly 1")
    }

    func testAcceptsHeightJustAboveFloor() {
        // Accept height just above the floor
        let result = PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: CGSize(width: 300, height: 80.1),
            minimumHeight: 80
        )
        XCTAssertTrue(result, "Should accept height just above floor (80.1pt)")
    }

    func testRejectsHeightJustBelowFloor() {
        // Reject height just below the floor
        let result = PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: CGSize(width: 300, height: 79.9),
            minimumHeight: 80
        )
        XCTAssertFalse(result, "Should reject height just below floor (79.9pt)")
    }
}