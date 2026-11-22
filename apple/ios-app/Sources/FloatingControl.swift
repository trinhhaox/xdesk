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

/// Một nút nổi 44 pt thay cho thanh công cụ cố định (thanh cũ che menu bar Mac): đĩa đặc tối, glyph trắng, viền sáng và bóng nên đọc được
/// trên mọi nền Mac. Chạm mở menu đặc; kéo rồi thả thì dính mép trái/phải gần nhất; sau 3 s không chạm chỉ nhạt còn 70%.
/// Vẽ TRÊN video trong ZStack nên nhận chạm trước lớp cảm ứng ở mọi chế độ chuột, khi zoom và cả khi bàn phím mở (`container` đã trừ bàn phím).
/// Chỉ nút và menu nhận chạm, mọi nơi khác chạm xuyên xuống Mac.
struct FloatingControl<Menu: View>: View {
    static var buttonSize: CGFloat { 44 }
    static var idleOpacity: Double { 0.7 }
    static var surface: Color { BrandPalette.overlaySurface }
    let store: FloatingControlStore
    let container: CGSize
    var onCollapse: () -> Void = {}
    @ViewBuilder let menu: (_ close: @escaping () -> Void, _ keepAlive: @escaping () -> Void) -> Menu
    @State private var expanded = false
    @State private var dragCenter: CGPoint?
    @State private var idle = false
    @State private var activity = 0

    var body: some View {
        let center = dragCenter ?? restingCenter
        FloatingOverlayLayout(
            buttonCenter: center,
            leftOfButton: store.placement.side == .trailing,
            buttonSize: Self.buttonSize,
            gap: 8,
            edgePadding: 8
        ) {
            if expanded { panelContent }
            button
        }
        .frame(width: container.width, height: container.height)
        .coordinateSpace(name: "floating")
        .onChange(of: expanded) { _, isExpanded in
            if !isExpanded { onCollapse() }
        }
        .task(id: ActivityKey(activity: activity, expanded: expanded, dragging: dragCenter != nil)) {
            idle = false
            guard dragCenter == nil else { return }
            do {
                try await Task.sleep(for: .seconds(expanded ? 10 : 3))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            if expanded { expanded = false } else { idle = true }
        }
    }

    private var restingCenter: CGPoint {
        let c = store.placement.center(containerWidth: Float(container.width), containerHeight: Float(container.height), size: Float(Self.buttonSize))
        return CGPoint(x: CGFloat(c.x), y: CGFloat(c.y))
    }

    private var button: some View {
        Image(systemName: expanded ? "xmark" : "ellipsis")
            .font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            .frame(width: Self.buttonSize, height: Self.buttonSize)
            .background(Circle().fill(Self.surface))
            .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
            .opacity(idle && !expanded ? Self.idleOpacity : 1)
            .animation(.easeInOut(duration: 0.3), value: idle)
            .contentShape(Circle())
            .onTapGesture { Haptics.light(); expanded.toggle(); activity += 1 }
            .gesture(DragGesture(minimumDistance: 12, coordinateSpace: .named("floating"))
                .onChanged { value in
                    dragCenter = value.location
                    if expanded { expanded = false }
                }
                .onEnded { value in
                    store.placement = .snapped(
                        centerX: Float(value.location.x), centerY: Float(value.location.y),
                        containerWidth: Float(container.width), containerHeight: Float(container.height), size: Float(Self.buttonSize))
                    dragCenter = nil
                    activity += 1
                })
            .accessibilityElement()
            .accessibilityLabel("Điều khiển Xdesk")
            .accessibilityHint(expanded ? "Đóng menu" : "Mở menu: chọn chế độ, bàn phím, chuột, ngắt kết nối")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { expanded.toggle(); activity += 1 }
    }

    private var panelContent: some View {
        let content = menu({ expanded = false; activity += 1 }, { activity += 1 })
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        return ViewThatFits(in: .vertical) {
            content
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.vertical) {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Self.surface))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
        .foregroundStyle(.white)
    }
}

private struct ActivityKey: Equatable {
    let activity: Int
    let expanded: Bool
    let dragging: Bool
}

/// Bố trí panel menu cạnh nút nổi trong một pass layout duy nhất (không lặp `@State` chiều cao qua `GeometryReader`).
private struct FloatingOverlayLayout: Layout {
    let buttonCenter: CGPoint
    let leftOfButton: Bool
    let buttonSize: CGFloat
    let gap: CGFloat
    let edgePadding: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let button = subviews.last else { return }
        if subviews.count >= 2 {
            let panel = subviews[0]
            let availableWidth = max(0, bounds.width - buttonSize - edgePadding * 3)
            let minWidth = min(220, max(0, bounds.width - edgePadding * 2))
            let panelWidth = min(276, max(minWidth, availableWidth))
            let maxPanelHeight = max(120, bounds.height - edgePadding * 2)
            let measured = panel.sizeThatFits(ProposedViewSize(width: panelWidth, height: maxPanelHeight))
            let panelHeight = min(max(44, measured.height), maxPanelHeight)
            let rawX = leftOfButton
                ? buttonCenter.x - buttonSize / 2 - gap - panelWidth / 2
                : buttonCenter.x + buttonSize / 2 + gap + panelWidth / 2
            let minX = panelWidth / 2 + edgePadding
            let maxX = max(minX, bounds.width - panelWidth / 2 - edgePadding)
            let x = min(max(rawX, minX), maxX)
            let minY = panelHeight / 2 + edgePadding
            let maxY = max(minY, bounds.height - panelHeight / 2 - edgePadding)
            let y = min(max(buttonCenter.y, minY), maxY)
            panel.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                anchor: .center,
                proposal: ProposedViewSize(width: panelWidth, height: panelHeight)
            )
        }
        button.place(
            at: CGPoint(x: bounds.minX + buttonCenter.x, y: bounds.minY + buttonCenter.y),
            anchor: .center,
            proposal: ProposedViewSize(width: buttonSize, height: buttonSize)
        )
    }
}
