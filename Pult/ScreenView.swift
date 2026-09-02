import SwiftUI
import UIKit

enum ScreenMode: String, CaseIterable {
    case cursor, touch
    var title: String { self == .cursor ? "Курсор" : "Сенсор" }
}

struct ScreenView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ConnectionService.self) private var service
    @State private var mode: ScreenMode = .touch
    @State private var showKeyboard = false
    @State private var rightClick = false
    @State private var lastDrag: CGPoint?
    @State private var dragging = false
    @State private var cursorDot: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Режим", selection: $mode) {
                ForEach(ScreenMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            stage
            toolbar
        }
        .navigationTitle(session.selected?.name ?? "Экран")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 6) {
                    Circle().fill(session.frameJPEG == nil ? Color.orange : Color.green).frame(width: 7, height: 7)
                    Text(session.frameJPEG == nil ? "Нет кадра" : "\(mode.title) \(session.fps)")
                        .font(.caption.weight(.semibold))
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
            let canvas = geo.size
            ZStack {
                Color.black
                if let data = session.frameJPEG, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: canvas.width, height: canvas.height)
                } else {
                    ContentUnavailableView("Ждём экран ПК", systemImage: "wifi")
                        .foregroundStyle(.white)
                }
                if mode == .cursor, let dot = cursorDot {
                    Circle()
                        .stroke(.white, lineWidth: 1.5)
                        .background(Circle().fill(.white.opacity(0.25)))
                        .frame(width: 22, height: 22)
                        .position(dot)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(in: canvas))
            .simultaneousGesture(
                SpatialTapGesture().onEnded { event in
                    handleTap(event.location, in: canvas)
                }
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("Клавиатура") { showKeyboard = true }
            if mode == .cursor {
                Button("ЛКМ") { Task { try? await service.send(.click(button: "left")) } }
                Button(rightClick ? "ПКМ вкл" : "ПКМ") { rightClick.toggle() }
            } else {
                Button(rightClick ? "ПКМ вкл" : "ПКМ") { rightClick.toggle() }
            }
            Menu("Качество") {
                Button("Низкое") { setQuality("low") }
                Button("Среднее") { setQuality("medium") }
                Button("Высокое") { setQuality("high") }
            }
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func setQuality(_ q: String) {
        session.streamQuality = q
        Task { try? await service.send(.stream(on: true, quality: q)) }
    }

    private func imageRect(in canvas: CGSize) -> CGRect {
        let src = session.frameSize == .zero ? CGSize(width: 16, height: 9) : session.frameSize
        guard src.width > 0, src.height > 0 else { return CGRect(origin: .zero, size: canvas) }
        let scale = min(canvas.width / src.width, canvas.height / src.height)
        let w = src.width * scale
        let h = src.height * scale
        return CGRect(x: (canvas.width - w) / 2, y: (canvas.height - h) / 2, width: w, height: h)
    }

    private func normalized(_ point: CGPoint, in canvas: CGSize) -> (Double, Double)? {
        let rect = imageRect(in: canvas)
        guard rect.width > 1, rect.height > 1, rect.insetBy(dx: -2, dy: -2).contains(point) else { return nil }
        let x = min(max((point.x - rect.minX) / rect.width, 0), 1)
        let y = min(max((point.y - rect.minY) / rect.height, 0), 1)
        return (Double(x), Double(y))
    }

    private func handleTap(_ point: CGPoint, in canvas: CGSize) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if mode == .cursor {
            cursorDot = point
            Task { try? await service.send(.click(button: rightClick ? "right" : "left")) }
            return
        }
        guard let xy = normalized(point, in: canvas) else { return }
        Task { try? await service.send(.tap(x: xy.0, y: xy.1, button: rightClick ? "right" : "left")) }
    }

    private func dragGesture(in canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if mode == .cursor {
                    cursorDot = value.location
                    if let last = lastDrag {
                        service.sendMove(
                            dx: (value.location.x - last.x) * session.sensitivity * 2.2,
                            dy: (value.location.y - last.y) * session.sensitivity * 2.2
                        )
                    }
                    lastDrag = value.location
                    return
                }
                guard let xy = normalized(value.location, in: canvas) else { return }
                if !dragging {
                    dragging = true
                    Task {
                        try? await service.send(.pointer(x: xy.0, y: xy.1))
                        try? await service.send(.down(button: rightClick ? "right" : "left"))
                    }
                } else {
                    Task { try? await service.send(.pointer(x: xy.0, y: xy.1)) }
                }
            }
            .onEnded { value in
                lastDrag = nil
                if mode == .touch, dragging {
                    if let xy = normalized(value.location, in: canvas) {
                        Task {
                            try? await service.send(.pointer(x: xy.0, y: xy.1))
                            try? await service.send(.up(button: rightClick ? "right" : "left"))
                        }
                    } else {
                        Task { try? await service.send(.up(button: "left")) }
                    }
                }
                dragging = false
            }
    }
}
