//
//  FluidMenuBarExtraStatusItem.swift
//  FluidMenuBarExtra
//
//  Created by Lukas Romsicki on 2022-12-17.
//  Copyright © 2022 Lukas Romsicki.
//
#if canImport(AppKit)
import AppKit
import SwiftUI

/// An individual element displayed in the system menu bar that displays a window
/// when triggered.
public final class FluidMenuBarExtraStatusItem: NSObject {
    private let window: NSWindow
    public let statusItem: NSStatusItem
    weak var menuBarExtraDelegate: FluidMenuBarExtraDelegate?

    private var localEventMonitor: EventMonitor?
    private var globalEventMonitor: EventMonitor?

    /// Closure that determines whether a click event should toggle the popover.
    /// Return `true` to handle the click (toggle popover), `false` to let it pass through.
    /// If not set, all clicks toggle the popover.
    public var shouldHandleClick: ((NSEvent) -> Bool)?

    private init(window: NSWindow) {
        self.window = window

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true

        super.init()

        localEventMonitor = LocalEventMonitor(mask: [.leftMouseDown]) { [weak self] event in
            if let button = self?.statusItem.button,
               event.window == button.window,
               !event.modifierFlags.contains(.command)
            {
                // Check if we should handle this click
                if let shouldHandle = self?.shouldHandleClick, !shouldHandle(event) {
                    // Let the event pass through to subviews
                    return event
                }
                self?.didPressStatusBarButton(button)
                // Stop propagating the event so that the button remains highlighted.
                return nil
            }
            return event
        }

        globalEventMonitor = GlobalEventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return }
            // Don't dismiss if clicking inside the popover window
            if event.window == self.window {
                return
            }
            self.dismissWindow()
        }

        localEventMonitor?.start()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func toggleWindow() {
        if window.isVisible {
            dismissWindow()
            return
        }
        setWindowPosition()
        setButtonHighlighted(to: true)
        // Tells the system to persist the menu bar in full screen mode.
        DistributedNotificationCenter.default().post(name: .beginMenuTracking, object: nil)
        window.makeKeyAndOrderFront(nil)
        // Activate the app using the modern API
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        globalEventMonitor?.start()
        NSWorkspace.shared
            .notificationCenter
            .addObserver(
                self,
                selector: #selector(spaceDidChange(_:)),
                name: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil
            )
        menuBarExtraDelegate?.menuBarExtraBecomeActive()
    }

    func dismissIfVisible() {
        if window.isVisible {
            dismissWindow()
        }
    }

    private func didPressStatusBarButton(_: NSStatusBarButton) {
        toggleWindow()
    }

    private func dismissWindow() {
        setButtonHighlighted(to: false)
        // Tells the system to cancel persisting the menu bar in full screen mode.
        DistributedNotificationCenter.default().post(name: .endMenuTracking, object: nil)
        globalEventMonitor?.stop()
        NSWorkspace.shared
            .notificationCenter
            .removeObserver(
                self,
                name: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil
            )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.window.orderOut(nil)
            self?.window.alphaValue = 1
        }
        menuBarExtraDelegate?.menuBarExtraWasDeactivated()
    }

    private func setButtonHighlighted(to highlight: Bool) {
        statusItem.button?.highlight(highlight)
    }

    private func setWindowPosition() {
        guard let statusItemWindow = statusItem.button?.window else {
            // If we don't know where the status item is, just place the window in the center.
            window.center()
            return
        }

        var targetRect = statusItemWindow.frame

        if let screen = statusItemWindow.screen {
            let windowWidth = window.frame.width

            if statusItemWindow.frame.origin.x + windowWidth > screen.visibleFrame.width {
                targetRect.origin.x += statusItemWindow.frame.width
                targetRect.origin.x -= windowWidth

                // Offset by window border size to align with highlighted button.
                targetRect.origin.x += Metrics.windowBorderSize
            } else {
                // Offset by window border size to align with highlighted button.
                targetRect.origin.x -= Metrics.windowBorderSize
            }
        } else {
            // If there's no screen, assume default positioning.
            targetRect.origin.x -= Metrics.windowBorderSize
        }

        window.setFrameTopLeftPoint(targetRect.origin)
    }

    @objc
    func spaceDidChange(_: Notification) {
        if window.isVisible {
            dismissWindow()
        }
    }
}

extension FluidMenuBarExtraStatusItem {
    convenience init(title: String, image: NSImage?, window: NSWindow) {
        self.init(window: window)

        statusItem.button?.setAccessibilityTitle(title)
        statusItem.button?.image = image
    }

    convenience init(title: String, window: NSWindow) {
        self.init(title: title, image: nil, window: window)
    }

    convenience init(title: String, image: String, window: NSWindow) {
        self.init(title: title, image: NSImage(named: image), window: window)
    }

    convenience init(title: String, systemImage: String, window: NSWindow) {
       self.init(title: title, image: NSImage(systemSymbolName: systemImage, accessibilityDescription: title), window: window)
    }

    /// Creates a status item with a custom view as the button content.
    /// - Parameters:
    ///   - title: The accessibility title for the status item.
    ///   - buttonView: A custom NSView to display in the status item button.
    ///   - window: The window to display when the status item is clicked.
    convenience init(title: String, buttonView: NSView, window: NSWindow) {
        self.init(window: window)

        statusItem.button?.setAccessibilityTitle(title)
        if let button = statusItem.button {
            buttonView.frame = button.bounds
            buttonView.autoresizingMask = [.width, .height]
            button.addSubview(buttonView)
        }
    }
}

private extension Notification.Name {
    static let beginMenuTracking = Notification.Name("com.apple.HIToolbox.beginMenuTrackingNotification")
    static let endMenuTracking = Notification.Name("com.apple.HIToolbox.endMenuTrackingNotification")
}

private enum Metrics {
    static let windowBorderSize: CGFloat = 2
}

#endif
