import SwiftUI

struct MediaView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ConnectionService.self) private var service
    @State private var confirmShutdown = false

    var body: some View {
        List {
            Section("Воспроизведение") {
                HStack(spacing: 16) {
                    media("backward.end", "prev")
                    media("playpause", "playPause")
                    media("forward.end", "next")
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            Section("Громкость") {
                HStack(spacing: 16) {
                    media("speaker.minus", "volumeDown")
                    media("speaker.slash", "mute")
                    media("speaker.plus", "volumeUp")
                }
                .buttonStyle(.plain)
            }
            Section("Презентация") {
                HStack {
                    Button("Слайд −") { send(.key(code: "left", modifiers: [])) }
                    Spacer()
                    Button("F5") { send(.key(code: "f5", modifiers: [])) }
                    Spacer()
                    Button("Слайд +") { send(.key(code: "right", modifiers: [])) }
                }
            }
            Section("Система") {
                Button("Заблокировать") { send(.system(action: "lock")) }
                Button("Сон") { send(.system(action: "sleep")) }
                Button("Выключить…", role: .destructive) { confirmShutdown = true }
            }
        }
        .navigationTitle("Медиа")
        .disabled(!session.connectionState.isLive && !session.previewMode)
        .confirmationDialog("Выключить компьютер?", isPresented: $confirmShutdown, titleVisibility: .visible) {
            Button("Выключить", role: .destructive) { send(.system(action: "shutdown")) }
            Button("Отмена", role: .cancel) {}
        }
        .overlay {
            if !session.connectionState.isLive && !session.previewMode {
                ContentUnavailableView("Сначала подключитесь", systemImage: "wifi.slash")
            }
        }
    }

    private func media(_ symbol: String, _ action: String) -> some View {
        Button { send(.media(action: action)) } label: {
            Image(systemName: symbol)
                .font(.title2)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func send(_ command: ControlCommand) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { try? await service.send(command) }
    }
}

struct MoreView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ConnectionService.self) private var service

    var body: some View {
        List {
            Section("Сеанс") {
                if let host = session.selected {
                    Label(host.name, systemImage: host.os.symbol)
                    Label(host.os.title, systemImage: "cpu")
                }
                Button("Отключить", role: .destructive) { service.disconnect() }
            }
            Section("Как это работает") {
                Label("Экран ПК идёт по Wi‑Fi, без облака", systemImage: "wifi")
                Label("Палец по кадру = клик", systemImage: "hand.tap")
                Label("Файлы качаются через Поделиться", systemImage: "arrow.down.doc")
            }
            Section {
                NavigationLink("Медиа и выключение") { MediaView() }
            }
        }
        .navigationTitle("Ещё")
    }
}
