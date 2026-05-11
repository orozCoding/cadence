import SwiftUI

@main
struct CadenceApp: App {
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
