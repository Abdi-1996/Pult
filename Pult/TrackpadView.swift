import SwiftUI

struct TrackpadView: View {
    let host: DiscoveredHost
    let service: ConnectionService
    @Environment(SessionStore.self) private var session
    @State private var showKeyboard = false
    @State private var lastPoint: CGPoint?
    @State private var showMedia = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Circle().fill(session.connectionState.isLive ? Color.green : Color.orange).frame(width: 8, height: 8)
                Text(session.connectionState.isLive ? "Подключено" : "Нет связи").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay { Text("Проведи пальцем").foregroundStyle(.tertiary) }
                .gesture(drag)
                .onTapGesture { click("left") }
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in click("right") })
            HStack {
                Button("Левый") { click("left") }
                Button("Правый") { click("right") }
                Button("Клавиатура") { showKeyboard = true }
                Button("Медиа") { showMedia = true }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle(host.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Отключить", role: .destructive) { service.disconnect() }
            }
        }
        .sheet(isPresented: $showKeyboard) { KeyboardSheet(service: service).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showMedia) { MediaView().presentationDetents([.medium]) }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if let last = lastPoint {
                    service.sendMove(dx: (value.location.x - last.x) * session.sensitivity, dy: (value.location.y - last.y) * session.sensitivity)
                }
                lastPoint = value.location
            }
            .onEnded { _ in lastPoint = nil }
    }

    private func click(_ button: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { try? await service.send(.click(button: button)) }
    }
}
