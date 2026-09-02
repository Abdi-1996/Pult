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
    @State private var cursorDot: CGPoint?
    @State private var hint = "1 палец · 2 пальца скролл · щипок масштаб"

    var body: some View {
        VStack(spacing: 0) {
            Picker("Режим", selection: $mode) {
                ForEach(ScreenMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            stage
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
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
                GestureCatcher { event in
                    handle(event, canvas: canvas)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("Клавиатура") { showKeyboard = true }
            Button("ЛКМ") { Task { try? await service.send(.click(button: "left")) } }
            Button("ПКМ") { Task { try? await service.send(.click(button: "right")) } }
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
        guard rect.width > 1, rect.height > 1 else { return nil }
        let x = min(max((point.x - rect.minX) / rect.width, 0), 1)
        let y = min(max((point.y - rect.minY) / rect.height, 0), 1)
        return (Double(x), Double(y))
    }

    private func handle(_ event: RemoteGesture, canvas: CGSize) {
        switch event {
        case .tap(let point, let clicks, let right):
            cursorDot = point
            UIImpactFeedbackGenerator(style: clicks > 1 ? .medium : .light).impactOccurred()
            let button = right ? "right" : "left"
            if mode == .cursor {
                Task {
                    for _ in 0..<clicks { try? await service.send(.click(button: button)) }
                }
            } else if let xy = normalized(point, in: canvas) {
                Task {
                    for _ in 0..<clicks { try? await service.send(.tap(x: xy.0, y: xy.1, button: button)) }
                }
            }
            hint = right ? "ПКМ" : (clicks > 1 ? "Двойной клик" : "Клик")

        case .oneFinger(let point, let delta, let phase):
            cursorDot = point
            if mode == .cursor {
                if phase != .ended {
                    service.sendMove(dx: delta.x * session.sensitivity * 2.2, dy: delta.y * session.sensitivity * 2.2)
                }
            } else if let xy = normalized(point, in: canvas) {
                Task {
                    if phase == .began {
                        try? await service.send(.pointer(x: xy.0, y: xy.1))
                        try? await service.send(.down(button: "left"))
                    } else if phase == .changed {
                        try? await service.send(.pointer(x: xy.0, y: xy.1))
                    } else {
                        try? await service.send(.pointer(x: xy.0, y: xy.1))
                        try? await service.send(.up(button: "left"))
                    }
                }
            }

        case .scroll(let dx, let dy):
            let sx = Double((-dx / 28).rounded())
            let sy = Double((dy / 28).rounded())
            if sx != 0 || sy != 0 {
                Task { try? await service.send(.scroll(dx: sx, dy: sy)) }
                hint = "Скролл"
            }

        case .pinch(let scale, let phase):
            if phase == .changed {
                let delta = scale > 1 ? 2.0 : -2.0
                Task { try? await service.send(.zoom(delta: delta)) }
                hint = scale > 1 ? "Масштаб +" : "Масштаб −"
            }

        case .threeSwipe(let dx, let dy):
            if abs(dx) > abs(dy) {
                Task {
                    if dx < 0 {
                        try? await service.send(.key(code: "tab", modifiers: ["alt"]))
                    } else {
                        try? await service.send(.key(code: "tab", modifiers: ["alt", "shift"]))
                    }
                }
                hint = "Переключение окон"
            } else {
                Task { try? await service.send(.key(code: "d", modifiers: ["win"])) }
                hint = "Рабочий стол"
            }
        }
    }
}

enum GesturePhase { case began, changed, ended }

enum RemoteGesture {
    case tap(CGPoint, clicks: Int, right: Bool)
    case oneFinger(CGPoint, delta: CGPoint, phase: GesturePhase)
    case scroll(dx: CGFloat, dy: CGFloat)
    case pinch(CGFloat, GesturePhase)
    case threeSwipe(dx: CGFloat, dy: CGFloat)
}

struct GestureCatcher: UIViewRepresentable {
    var onEvent: (RemoteGesture) -> Void

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onEvent = onEvent
        return view
    }

    func updateUIView(_ uiView: CatcherView, context: Context) {
        uiView.onEvent = onEvent
    }
}

final class CatcherView: UIView, UIGestureRecognizerDelegate {
    var onEvent: ((RemoteGesture) -> Void)?
    private var lastPan = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap))
        tap.numberOfTapsRequired = 1
        tap.numberOfTouchesRequired = 1

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(onDouble))
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)

        let press = UILongPressGestureRecognizer(target: self, action: #selector(onPress))
        press.minimumPressDuration = 0.45

        let pan1 = UIPanGestureRecognizer(target: self, action: #selector(onPan1))
        pan1.minimumNumberOfTouches = 1
        pan1.maximumNumberOfTouches = 1
        pan1.delegate = self

        let pan2 = UIPanGestureRecognizer(target: self, action: #selector(onPan2))
        pan2.minimumNumberOfTouches = 2
        pan2.maximumNumberOfTouches = 2
        pan2.delegate = self

        let pan3 = UIPanGestureRecognizer(target: self, action: #selector(onPan3))
        pan3.minimumNumberOfTouches = 3
        pan3.maximumNumberOfTouches = 3

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch))
        pinch.delegate = self

        [tap, doubleTap, press, pan1, pan2, pan3, pinch].forEach { addGestureRecognizer($0) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        (gestureRecognizer is UIPinchGestureRecognizer) || (other is UIPinchGestureRecognizer)
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        onEvent?(.tap(g.location(in: self), clicks: 1, right: false))
    }

    @objc private func onDouble(_ g: UITapGestureRecognizer) {
        onEvent?(.tap(g.location(in: self), clicks: 2, right: false))
    }

    @objc private func onPress(_ g: UILongPressGestureRecognizer) {
        if g.state == .began {
            onEvent?(.tap(g.location(in: self), clicks: 1, right: true))
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }

    @objc private func onPan1(_ g: UIPanGestureRecognizer) {
        let point = g.location(in: self)
        let t = g.translation(in: self)
        let phase: GesturePhase = g.state == .began ? .began : (g.state == .ended || g.state == .cancelled ? .ended : .changed)
        let delta = CGPoint(x: t.x - lastPan.x, y: t.y - lastPan.y)
        lastPan = (phase == .ended) ? .zero : t
        onEvent?(.oneFinger(point, delta: delta, phase: phase))
    }

    @objc private func onPan2(_ g: UIPanGestureRecognizer) {
        if g.state == .changed {
            let t = g.translation(in: self)
            onEvent?(.scroll(dx: t.x, dy: t.y))
            g.setTranslation(.zero, in: self)
        }
    }

    @objc private func onPan3(_ g: UIPanGestureRecognizer) {
        if g.state == .ended {
            let t = g.translation(in: self)
            onEvent?(.threeSwipe(dx: t.x, dy: t.y))
        }
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        let phase: GesturePhase = g.state == .began ? .began : (g.state == .ended || g.state == .cancelled ? .ended : .changed)
        onEvent?(.pinch(g.scale, phase))
        if g.state == .changed { g.scale = 1 }
    }
}
