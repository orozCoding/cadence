import SwiftUI
import AppKit
import UserNotifications

// MARK: - App delegate (keyboard + click monitors)

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        // Space bar → toggle timer (only when no text field is focused)
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handleKeyDown) {
            monitors.append(m)
        }
        // Click anywhere → resign text-field focus
        if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: handleMouseDown) {
            monitors.append(m)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        FocusTimeStore.shared.flushIfNeeded()
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 49, !event.isARepeat else { return event }  // 49 = space; ignore key-repeat
        // Pass through to any focused interactive control (text fields, buttons, pickers, scroll views, etc.)
        let fr = NSApp.keyWindow?.firstResponder
        guard !(fr is NSText), !(fr is NSControl), !(fr is NSScrollView) else { return event }
        // Call synchronously — we're already on the main thread inside an NSEvent monitor.
        // Using Task { @MainActor in ... } would defer to the next actor turn, letting two
        // rapid presses both enqueue before either fires, causing a double-toggle.
        MainActor.assumeIsolated { PomodoroTimer.shared.toggle() }
        return nil  // consume the event so it doesn't insert a space
    }

    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        // If a text input is focused and the click lands outside a text control, defocus.
        guard let window = event.window,
              window.firstResponder is NSText else { return event }
        let hitView = window.contentView?.hitTest(event.locationInWindow)
        if !(hitView is NSText) && !(hitView is NSTextField) {
            window.makeFirstResponder(nil)
        }
        return event
    }
}

// MARK: - Foreground notification presentation

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - App entry point

@main
struct CadenceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TaskStore.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var folderStore = FolderStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(folderStore)
                .preferredColorScheme(.light)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1100, height: 700)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .preferredColorScheme(.light)
        }
    }
}
