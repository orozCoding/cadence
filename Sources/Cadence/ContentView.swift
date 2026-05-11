import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            TimerView()
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

struct SidebarView: View {
    var body: some View {
        List {
            Label("Today", systemImage: "sun.max")
            Label("This Week", systemImage: "calendar")
            Label("This Month", systemImage: "calendar.badge.clock")
        }
        .listStyle(.sidebar)
        .navigationTitle("Cadence")
    }
}

#Preview {
    ContentView()
}
