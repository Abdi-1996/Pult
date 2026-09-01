import SwiftUI

@main
struct PultApp: App {
    @State private var session = SessionStore()
    @State private var service = ConnectionService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(service)
                .onAppear { service.store = session }
        }
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            if session.connectionState.isLive || (session.previewMode && session.selected != nil) {
                SessionTabs()
            } else {
                NavigationStack {
                    DeviceListView()
                }
            }
        }
    }
}

struct SessionTabs: View {
    @Environment(SessionStore.self) private var session
    @Environment(ConnectionService.self) private var service

    var body: some View {
        TabView {
            NavigationStack { ScreenView() }
                .tabItem { Label("Экран", systemImage: "desktopcomputer") }

            NavigationStack { FilesView() }
                .tabItem { Label("Файлы", systemImage: "folder") }

            NavigationStack { AppsView() }
                .tabItem { Label("Приложения", systemImage: "square.grid.2x2") }

            NavigationStack {
                TrackpadView(
                    host: session.selected ?? DiscoveredHost(id: "x", name: "ПК", os: .windows, host: "", port: 17420, isOnline: true, link: .lan),
                    service: service
                )
            }
            .tabItem { Label("Пульт", systemImage: "hand.draw") }

            NavigationStack { MoreView() }
                .tabItem { Label("Ещё", systemImage: "ellipsis") }
        }
    }
}
