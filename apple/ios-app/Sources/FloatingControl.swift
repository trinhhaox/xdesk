import Observation
import SwiftUI
import XdeskInput

/// Vị trí nút nổi, nhớ trong UserDefaults.
@MainActor
@Observable
final class FloatingControlStore {
    private static let sideKey = "xdesk.floating.side", fractionKey = "xdesk.floating.fraction"
    var placement: FloatingControlPlacement { didSet { save() } }

    init() {
        let defaults = UserDefaults.standard
        placement = FloatingControlPlacement(
            side: defaults.string(forKey: Self.sideKey).flatMap(FloatingControlPlacement.Side.init(rawValue:)) ?? .trailing,
            verticalFraction: (defaults.object(forKey: Self.fractionKey) as? Double).map(Float.init) ?? 0.5
        )
    }

    private func save() {
        UserDefaults.standard.set(placement.side.rawValue, forKey: Self.sideKey)
        UserDefaults.standard.set(Double(placement.verticalFraction), forKey: Self.fractionKey)
    }
}

/// Một nút nổi 44 pt thay cho thanh công cụ cố định (thanh cũ che menu bar Mac). Chạm mở menu gọn; kéo rồi thả thì dính mép
/// trái/phải gần nhất; mờ còn 35% sau 3 s không chạm. Chỉ nút và menu nhận chạm, mọi nơi khác chạm xuyên xuống Mac.
struct FloatingControl<Menu: View>: View {
    static var buttonSize: CGFloat { 44 }
    let store: FloatingControlStore
    let container: CGSize
    @ViewBuilder let menu: (_ close: @escaping () -> Void) -> Menu
    @State private var expanded = false
    @State private var dragCenter: CGPoint?
    @State private var idle = false
    @State private var activity = 0
    @State private var menuSize = CGSize.zero

    var body: some View {
        let center = dragCenter ?? restingCenter
        ZStack {
            if expanded { panel(near: center) }
            button.position(center)
        }
        .frame(width: container.width, height: container.height)
        .coordinateSpace(name: "floating")
        .task(id: activity) {
            idle = false
            try? await Task.sleep(for: .seconds(expanded ? 8 : 3))
            if expanded { expanded = false } else { idle = true }
        }
    }

    private var restingCenter: CGPoint {
        let c = store.placement.center(containerWidth: Float(container.width), containerHeight: Float(container.height), size: Float(Self.buttonSize))
        return CGPoint(x: CGFloat(c.x), y: CGFloat(c.y))
    }

    private var button: some View {
        Image(systemName: expanded ? "xmark" : "ellipsis")
            .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            .frame(width: Self.buttonSize, height: Self.buttonSize)
            .background(Circle().fill(.black.opacity(0.6)))
            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
            .opacity(idle ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.3), value: idle)
            .contentShape(Circle())
            .onTapGesture { expanded.toggle(); activity += 1 }
            .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("floating"))
                .onChanged { dragCenter = $0.location; expanded = false; activity += 1 }
                .onEnded { value in
                    store.placement = .snapped(
                        centerX: Float(value.location.x), centerY: Float(value.location.y),
                        containerWidth: Float(container.width), containerHeight: Float(container.height), size: Float(Self.buttonSize))
                    dragCenter = nil
                    activity += 1
                })
            .accessibilityElement()
            .accessibilityLabel("Điều khiển Xdesk")
            .accessibilityHint(expanded ? "Đóng menu" : "Mở menu: ngắt kết nối, bàn phím, chuột")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { expanded.toggle(); activity += 1 }
    }

    private func panel(near center: CGPoint) -> some View {
        let leftOfButton = store.placement.side == .trailing
        let x = leftOfButton ? center.x - Self.buttonSize / 2 - 8 - menuSize.width / 2 : center.x + Self.buttonSize / 2 + 8 + menuSize.width / 2
        let y = min(max(center.y, menuSize.height / 2 + 8), container.height - menuSize.height / 2 - 8)
        return menu { expanded = false; activity += 1 }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.78)))
            .foregroundStyle(.white)
            .fixedSize()
            .background(GeometryReader { proxy in Color.clear.onAppear { menuSize = proxy.size }.onChange(of: proxy.size) { _, new in menuSize = new } })
            .position(x: x, y: y)
    }
}
