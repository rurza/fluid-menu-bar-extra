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

/// A custom window configured to behave as closely to an `NSMenu` as possible.
///
/// `FluidMenuBarExtraWindow` listens for changes to the size of its content and
/// automatically adjusts its frame to match.
final class FluidMenuBarExtraWindow<Content: View>: NSPanel {
    private let content: () -> Content

    /// On macOS 26+, we skip vibrancy views entirely to let SwiftUI's .glassEffect() work.
    /// On older versions, we use NSVisualEffectView for the classic popover appearance.
    private lazy var backgroundView: NSView = {
        if #available(macOS 26.0, *) {
            // Plain view - SwiftUI content handles its own glass effects
            let view = NSView()
            view.wantsLayer = true
            view.translatesAutoresizingMaskIntoConstraints = true
            return view
        } else {
            let view = NSVisualEffectView()
            view.wantsLayer = true
            view.blendingMode = .behindWindow
            view.state = .active
            view.material = .popover
            view.translatesAutoresizingMaskIntoConstraints = true
            view.layer?.cornerRadius = 12
            view.layer?.cornerCurve = .continuous
            return view
        }
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

        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.title = title

        isMovable = false
        isMovableByWindowBackground = false
        isFloatingPanel = true
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
        setContentSize(hostingView.intrinsicContentSize)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            hostingView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
        ])
    }

    private func contentSizeDidUpdate(to size: CGSize) {
        var nextFrame = frame
        let previousContentSize = contentRect(forFrameRect: frame).size

        let deltaX = size.width - previousContentSize.width
        let deltaY = size.height - previousContentSize.height

        nextFrame.origin.y -= deltaY
        nextFrame.size.width += deltaX
        nextFrame.size.height += deltaY

        guard frame != nextFrame else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.setFrame(nextFrame, display: true, animate: true)
        }
    }
}

#endif
