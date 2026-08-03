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

    /// True from the start of a dismissal until its fade-out completes. `window.isVisible`
    /// stays true for the whole 0.3s fade, so it cannot serve as the re-entrancy guard.
    private var isDismissing = false

    private init(window: NSWindow) {
        self.window = window

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true

        super.init()

        localEventMonitor = LocalEventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }

            // (1) Our own status item's button window. This branch owns the click completely:
            // both of its escapes — cmd-click (rearranging the item) and `shouldHandleClick`
            // returning false (a custom button view that toggles via its own callback) — hand
            // the event to AppKit *without* falling into (2). That is what keeps a single click
            // on the icon to exactly one toggle instead of dismiss-then-reopen.
            if let button = self.statusItem.button, event.window === button.window {
                guard event.type == .leftMouseDown,
                      !event.modifierFlags.contains(.command)
                else { return event }

                // Check if we should handle this click
                if let shouldHandle = self.shouldHandleClick, !shouldHandle(event) {
                    // Let the event pass through to subviews
                    return event
                }
                self.didPressStatusBarButton(button)
                // Stop propagating the event so that the button remains highlighted.
                return nil
            }

            // (2) Any other click landing in this app dismisses the popover — the same thing the
            // global monitor already does for other applications, and the same thing a real
            // NSMenu does.
            //
            // The global monitor alone cannot cover this: `addGlobalMonitorForEvents` is only
            // delivered clicks destined for OTHER applications, which arrive with a nil
            // `event.window`. Clicks in one of our own windows never reach it — except for one
            // case that made the old behaviour look intermittent rather than simply missing.
            // `makeKeyAndOrderFront` on this borderless `.statusBar`-level window does not make
            // the app frontmost to the window server, so the app is left "pending activation",
            // and the next mouse-down on one of our normal-level windows is an *activating*
            // click that IS delivered to the global monitor — carrying a non-nil `event.window`
            // the old `event.window == self.window` guard did not catch. Result: the popover was
            // dismissed by the first click in another of our windows after being reopened, but
            // not if something had already activated the app (e.g. opening a window
            // programmatically with `NSApp.activate`). Handling it here makes it consistent.
            //
            // No carve-out is needed for menus opened from the popover. NSMenu tracking runs a
            // nested event loop that consumes every mouse-down itself: between
            // `didBeginTracking` and `didEndTracking` this monitor receives nothing at all.
            // Verified on macOS 26 for clicking a menu item, clicking the popover, and clicking
            // another of our windows while a menu is up — all three produce zero local-monitor
            // events, so an open submenu can never dismiss the popover out from under itself.
            if event.window !== self.window {
                self.dismissWindow()
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

        // Recover from degenerate (collapsed) frame before opening
        (window as? PopoverWindowRecovery)?.recoverIfDegenerate()

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
        // Idempotent. Several dismissals can now race for a single open: with two status items
        // both local monitors see the same click (monitors run in registration order, and only a
        // `nil` return stops later ones), and `dismissIfVisible()` can arrive from the sibling
        // item while this one is still fading. A second pass would restart the 0.3s fade and
        // post a second `menuBarExtraWasDeactivated()`, so a host counting open/close pairs
        // would be decremented for an open it never saw.
        guard window.isVisible, !isDismissing else { return }
        isDismissing = true

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
            self?.isDismissing = false
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
