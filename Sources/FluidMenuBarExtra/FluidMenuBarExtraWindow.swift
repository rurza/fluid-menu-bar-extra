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

            if let targetFrame = self.pendingFrame {
                self.pendingFrame = nil
                self.setFrame(targetFrame, display: true, animate: true)
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
