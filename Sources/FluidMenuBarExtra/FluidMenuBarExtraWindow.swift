//
//  FluidMenuBarExtraWindow.swift
//  FluidMenuBarExtra
//
//  Created by Lukas Romsicki on 2022-12-16.
//  Copyright © 2022 Lukas Romsicki.
//
#if canImport(AppKit)
import AppKit
import SwiftUI

/// Internal protocol for window recovery without generic type constraints.
protocol PopoverWindowRecovery: AnyObject {
    func recoverIfDegenerate()
}

/// A custom window configured to behave as closely to an `NSMenu` as possible.
///
/// `FluidMenuBarExtraWindow` listens for changes to the size of its content and
/// automatically adjusts its frame to match.
final class FluidMenuBarExtraWindow<Content: View>: NSWindow, PopoverWindowRecovery {
    private let content: () -> Content

    /// The minimum acceptable height for the popover window (absolute floor).
    /// Degenerate transient heights (produced mid-animation) below this are rejected.
    private let minimumHeight: CGFloat = 80

    /// Tracks the last accepted content size for diagnostic purposes.
    private var lastAcceptedSize: CGSize

    /// The pending frame to apply during coalescing.
    private var pendingFrame: CGRect?

    /// Flag indicating whether a resize dispatch is pending.
    private var hasPendingResize = false

    /// On macOS 26+, we skip vibrancy views entirely to let SwiftUI's .glassEffect() work.
    /// On older versions, we use NSVisualEffectView for the classic popover appearance.
    private lazy var backgroundView: NSView = {
        let view: NSView
        if #available(macOS 26.0, *) {
            // Plain view - SwiftUI content handles its own glass effects
            view = NSView()
        } else {
            let visualView = NSVisualEffectView()
            visualView.blendingMode = .behindWindow
            visualView.state = .active
            visualView.material = .popover
            view = visualView
        }
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = true
        view.layer?.cornerRadius = 12
        view.layer?.cornerCurve = .continuous
        return view
    }()

    private var rootView: some View {
        content()
            .modifier(RootViewModifier(windowTitle: title))
            .onPreferenceChange(ContentSize.self) { [weak self] size in
                self?.contentSizeDidUpdate(to: size)
            }
    }

    private lazy var hostingView: NSHostingView<some View> = {
        let view = NSHostingView(rootView: rootView)
        // Disable NSHostingView's default automatic sizing behavior.
        if #available(macOS 13.0, *) {
            view.sizingOptions = []
        }
        view.isVerticalContentSizeConstraintActive = false
        view.isHorizontalContentSizeConstraintActive = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    init(title: String, content: @escaping () -> Content) {
        self.content = content
        self.lastAcceptedSize = .zero

        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.title = title

        isMovable = false
        isMovableByWindowBackground = false
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hasShadow = true

        animationBehavior = .none
        if #available(macOS 13.0, *) {
            collectionBehavior = [.auxiliary, .transient, .moveToActiveSpace, .fullScreenAuxiliary]
        } else {
            collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        }
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        contentView = backgroundView
        backgroundView.addSubview(hostingView)
        let intrinsicSize = hostingView.intrinsicContentSize
        setContentSize(intrinsicSize)
        lastAcceptedSize = intrinsicSize

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            hostingView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
        ])
    }

    private func contentSizeDidUpdate(to size: CGSize) {
        // (a) Absolute floor guard - reject degenerate transient heights
        guard PopoverSizingPolicy.shouldAcceptContentSize(
            proposed: size,
            minimumHeight: minimumHeight
        ) else {
            #if DEBUG
            print("[FluidMenuBarExtra] rejected degenerate content size: \(size) (minimum: \(minimumHeight))")
            #endif
            return
        }

        // Update last accepted size for diagnostics
        lastAcceptedSize = size

        // Compute next frame
        var nextFrame = frame
        let previousContentSize = contentRect(forFrameRect: frame).size

        let deltaX = size.width - previousContentSize.width
        let deltaY = size.height - previousContentSize.height

        nextFrame.origin.y -= deltaY
        nextFrame.size.width += deltaX
        nextFrame.size.height += deltaY

        // (b) Same-tick coalescing - store the latest target and dispatch once
        guard frame != nextFrame else {
            return
        }

        pendingFrame = nextFrame

        guard !hasPendingResize else {
            return
        }

        hasPendingResize = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasPendingResize = false

            if let pending = self.pendingFrame {
                self.pendingFrame = nil

                // `pending` was computed from the frame as it stood when SwiftUI reported the new
                // content size — a runloop turn ago. On the open path `setWindowPosition()` runs
                // in exactly that gap, so applying `pending`'s origin verbatim silently undoes the
                // move: the popover is positioned correctly and then dragged back to wherever it
                // happened to be sitting, which on the first open after launch is off screen.
                // Only the size is still meaningful; re-derive the origin from where the window
                // actually is now, keeping its top-left anchored.
                var targetFrame = PopoverPlacementPolicy.rebase(pendingFrame: pending, onto: self.frame)

                // A resize keeps the left edge, so a window positioned while it was narrower than
                // its final width grows off the trailing edge. Pull it back.
                if let visibleFrame = (self.screen ?? NSScreen.main)?.visibleFrame {
                    targetFrame = PopoverPlacementPolicy.clampHorizontally(targetFrame, to: visibleFrame)
                }

                guard targetFrame != self.frame else { return }

                // Off screen there is nothing to animate, and an in-flight animation is precisely
                // what outlives `setWindowPosition()` and overrides it. Land it synchronously.
                guard self.isVisible else {
                    self.setFrame(targetFrame, display: false)
                    return
                }

                // `setFrame(_:display:animate:)` animates in *blocking* mode: it spins a private
                // run loop in `NSEventTrackingRunLoopMode` and force-displays every step, holding
                // the main thread for the entire resize — measured at ~310ms while the window is
                // visible, and ~0.1ms while ordered out, which is why this only bites on screen.
                // Anything else animating at that moment freezes for the duration: a settings
                // toggle that changed a section, an AppKit switch knob mid-travel, motion artwork
                // playing in the popover, any concurrent SwiftUI transition.
                //
                // The animator proxy runs the same duration and ease-in-ease-out curve off the
                // run loop, so it looks identical without blocking.
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = self.animationResizeTime(targetFrame)
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.animator().setFrame(targetFrame, display: true)
                }
            }
        }
    }

    // Allow borderless window to become key so SwiftUI controls render in active state
    override var canBecomeKey: Bool {
        true
    }

    // MARK: - PopoverWindowRecovery

    /// If the window has been stranded at a degenerate (collapsed) frame, re-measure from the
    /// hosting view and snap to a correct size. Called on the open path so reopening always recovers.
    func recoverIfDegenerate() {
        let currentHeight = contentRect(forFrameRect: frame).height
        guard currentHeight < minimumHeight else { return }

        hostingView.invalidateIntrinsicContentSize()
        let corrected = hostingView.intrinsicContentSize

        // Only snap if the corrected size itself passes the floor; otherwise leave it to the next layout.
        if PopoverSizingPolicy.shouldAcceptContentSize(proposed: corrected, minimumHeight: minimumHeight) {
            setContentSize(corrected)
            #if DEBUG
            print("[FluidMenuBarExtra] recovered degenerate window frame to \(corrected)")
            #endif
        }
    }
}

#endif
