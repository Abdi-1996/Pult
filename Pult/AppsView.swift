import SwiftUI

struct AppsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ConnectionService.self) private var service
    @State private var query = ""
    @State private var launched: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        ScrollView {
            if session.appsLoading {
                ProgressView("Список с ПК…").padding(.top, 40)
            }
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(filtered) { app in
                    Button {
                        launched = app.name
                        Task { try? await service.send(.launch(id: app.id)) }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: symbol(for: app.name))
                                .font(.title)
                                .frame(width: 64, height: 64)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Text(app.name)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("Приложения")
        .searchable(text: $query, prompt: "Chrome, Word, Steam…")
        .overlay {
            if filtered.isEmpty && !session.appsLoading {
                ContentUnavailableView("Нет приложений", systemImage: "square.grid.2x2")
            }
        }
        .onAppear {
            if session.apps.isEmpty {
                session.appsLoading = true
                Task { try? await service.send(.apps) }
            }
        }
        .refreshable { try? await service.send(.apps) }
        .alert("Запускаем на ПК", isPresented: Binding(
            get: { launched != nil },
            set: { if !$0 { launched = nil } }
        )) {
            Button("Ок", role: .cancel) { launched = nil }
        } message: {
            Text(launched ?? "")
        }
    }

    private var filtered: [RemoteApp] {
        if query.isEmpty { return session.apps }
        return session.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("chrome") || n.contains("edge") || n.contains("firefox") || n.contains("safari") { return "globe" }
        if n.contains("word") { return "doc.text" }
        if n.contains("excel") { return "tablecells" }
        if n.contains("power") { return "slider.horizontal.below.rectangle" }
        if n.contains("code") || n.contains("xcode") { return "chevron.left.forwardslash.chevron.right" }
        if n.contains("steam") || n.contains("game") { return "gamecontroller" }
        if n.contains("spot") || n.contains("music") { return "music.note" }
        if n.contains("telegram") || n.contains("whats") { return "paperplane" }
        if n.contains("photo") { return "photo" }
        if n.contains("setting") { return "gearshape" }
        if n.contains("explorer") || n.contains("finder") { return "folder" }
        return "app"
    }
}
