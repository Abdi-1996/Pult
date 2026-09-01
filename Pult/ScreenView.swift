import SwiftUI
import UIKit

struct ScreenView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ConnectionService.self) private var service
    @State private var showKeyboard = false
    @State private var rightClick = false
    @State private var lastDrag: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            stage
            toolbar
        }
        .navigationTitle(session.selected?.name ?? "Экран")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 6) {
                    Circle().fill(session.frameJPEG == nil ? Color.orange : Color.green).frame(width: 7, height: 7)
                    Text(session.frameJPEG == nil ? "Нет кадра" : "LIVE \(session.fps) fps")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(session.frameJPEG == nil ? .orange : .green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
            }
        }
        .sheet(isPresented: $showKeyboard) {
            KeyboardSheet(service: service)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            Task { try? await service.send(.stream(on: true, quality: session.streamQuality)) }
        }
    }

    private var stage: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let data = session.frameJPEG, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else if session.previewMode {
                    LinearGradient(colors: [.blue.opacity(0.35), .indigo], startPoint: .top, endPoint: .bottom)
                } else {
                    ContentUnavailableView("Ждём экран ПК", systemImage: "wifi")
                        .foregroundStyle(.white)
                }
            }
            .contentShape(Rectangle())
            .gesture(touch(in: geo.size))
            .simultaneousGesture(
                SpatialTapGesture().onEnded { event in
                    sendTap(event.location, in: geo.size, button: rightClick ? "right" : "left")
                }
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("Клавиатура") { showKeyboard = true }
            Button(rightClick ? "ПКМ вкл" : "ПКМ") { rightClick.toggle() }
            Menu("Качество") {
                Button("Низкое") { setQuality("low") }
                Button("Среднее") { setQuality("medium") }
                Button("Высокое") { setQuality("high") }
            }
            Button("Откл.") { service.disconnect() }.foregroundStyle(.red)
        }
        .font(.caption)
        .padding()
        .background(.bar)
    }

    private func setQuality(_ q: String) {
        session.streamQuality = q
        Task { try? await service.send(.stream(on: true, quality: q)) }
    }

    private func touch(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if let last = lastDrag {
                    service.sendMove(
                        dx: (value.location.x - last.x) * session.sensitivity * 2,
                        dy: (value.location.y - last.y) * session.sensitivity * 2
                    )
                }
                lastDrag = value.location
            }
            .onEnded { _ in lastDrag = nil }
    }

    private func sendTap(_ point: CGPoint, in size: CGSize, button: String) {
        guard size.width > 0, size.height > 0 else { return }
        let x = min(max(point.x / size.width, 0), 1)
        let y = min(max(point.y / size.height, 0), 1)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { try? await service.send(.tap(x: x, y: y, button: button)) }
    }
}
