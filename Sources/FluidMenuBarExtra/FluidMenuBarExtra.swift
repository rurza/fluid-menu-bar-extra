//
//  FluidMenuBarExtra.swift
//  FluidMenuBarExtra
//
//  Created by Lukas Romsicki on 2022-12-17.
//  Copyright © 2022 Lukas Romsicki.
//
#if canImport(AppKit)
import SwiftUI

/// A class you use to create a SwiftUI menu bar extra in both SwiftUI and non-SwiftUI
/// applications.
///
/// A fluid menu bar extra is configured by initializing it once during the lifecycle of your
/// app, most commonly in your application delegate. In SwiftUI apps, use
/// `NSApplicationDelegateAdaptor` to create an application delegate in which
/// a ``FluidMenuBarExtra`` can be created:
///
/// ```swift
/// class AppDelegate: NSObject, NSApplicationDelegate {
///     private var menuBarExtra: FluidMenuBarExtra?
///
///     func applicationDidFinishLaunching(_ notification: Notification) {
///         menuBarExtra = FluidMenuBarExtra(title: "My Menu", systemImage: "cloud.fill") {
///             Text("My SwiftUI View")
///         }
///     }
/// }
/// ```
///
/// Because an application delegate is a plain object, not a `View` or `Scene`, you
/// can't pass state properties to views in the closure of `FluidMenuBarExtra` directly.
/// Instead, define state properties inside child views, or pass published properties from
/// your application delegate to the child views using the `environmentObject`
/// modifier.
public final class FluidMenuBarExtra {
    public let statusItem: FluidMenuBarExtraStatusItem
    private var task: Task<Void, Never>?

    public init(
        title: String,
        menuBarExtraDelegate: FluidMenuBarExtraDelegate? = nil,
        @ViewBuilder content: @escaping () -> some View
    ) {
        let window = FluidMenuBarExtraWindow(title: title, content: content)
        statusItem = FluidMenuBarExtraStatusItem(title: title, window: window)
        statusItem.menuBarExtraDelegate = menuBarExtraDelegate
        setUpObserving()
    }

    public init(
        title: String,
        image: String,
        menuBarExtraDelegate: FluidMenuBarExtraDelegate? = nil,
        @ViewBuilder content: @escaping () -> some View
    ) {
        let window = FluidMenuBarExtraWindow(title: title, content: content)
        statusItem = FluidMenuBarExtraStatusItem(title: title, image: image, window: window)
        statusItem.menuBarExtraDelegate = menuBarExtraDelegate
        setUpObserving()
    }

    public init(
        title: String,
        systemImage: String,
        menuBarExtraDelegate: FluidMenuBarExtraDelegate? = nil,
        @ViewBuilder content: @escaping () -> some View
    ) {
        let window = FluidMenuBarExtraWindow(title: title, content: content)
        statusItem = FluidMenuBarExtraStatusItem(title: title, systemImage: systemImage, window: window)
        statusItem.menuBarExtraDelegate = menuBarExtraDelegate
        setUpObserving()
    }

    public init(title: String, image: NSImage, menuBarExtraDelegate: FluidMenuBarExtraDelegate? = nil,
                @ViewBuilder content: @escaping () -> some View) {
        let window = FluidMenuBarExtraWindow(title: title, content: content)
        statusItem = FluidMenuBarExtraStatusItem(title: title, image: image, window: window)
        statusItem.menuBarExtraDelegate = menuBarExtraDelegate
        setUpObserving()
    }

    public func toggleMenuBarExtra() {
        statusItem.toggleWindow()
    }

    private func setUpObserving() {
        task = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .fluidMenuBarExtraToggle) {
                self?.toggleMenuBarExtra()
            }
        }
    }

    deinit {
        task?.cancel()
    }
}
#endif
