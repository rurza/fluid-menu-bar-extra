//
//  FluidMenuBarExtraWindow.swift
//  FluidMenuBarExtra
//
//  Created by Lukas Romsicki on 2022-12-16.
//  Copyright © 2022 Lukas Romsicki.
//

import AppKit
import SwiftUI

/// A custom window configured to behave as closely to an `NSMenu` as possible.
///
/// `FluidMenuBarExtraWindow` listens for changes to the size of its content and
/// automatically adjusts its frame to match.
final class FluidMenuBarExtraWindow<Content: View>: NSPanel {
    private let content: () -> Content

    private lazy var visualEffectView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.wantsLayer = true
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .underWindowBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer?.cornerRadius = 8
        view.layer?.cornerCurve = .continuous
        return view
    }()

    // without it NSWindow/NSPanel will draw gross border around window, that will ignore visualEffectView's corner radius
    private lazy var backgroundView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = true
        return view
    }()

    private var rootView: some View {
        content()
            .modifier(RootViewModifier(windowTitle: title))
            .onPreferenceChange(ContentSize.self, perform: { [weak self] size in
                self?.contentSizeDidUpdate(to: size)
            })
    }

    private lazy var hostingView: NSHostingView<some View> = {
        let view = NSHostingView(rootView: rootView)

        view.sizingOptions = [.preferredContentSize]
//        view.isVerticalContentSizeConstraintActive = false
//        view.isHorizontalContentSizeConstraintActive = false
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
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        hasShadow = true

        animationBehavior = .none
        if #available(macOS 13, *) {
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
        backgroundView.addSubview(visualEffectView)
        visualEffectView.addSubview(hostingView)
        setContentSize(hostingView.intrinsicContentSize)

        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            hostingView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
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
