import SwiftUI
import XdeskInput
import XdeskWire

/// Chế độ "Slide & Số": Trình chiếu, Media, Bàn phím số. Vị trí từng nút do `SlideNumpadPlan` tính từ kích thước
/// thật (dọc xếp chồng, ngang 3 cột) nên không cuộn và không chồng nhau.
struct SlideNumpadView: View {
    let model: StreamViewModel

    var body: some View {
        GeometryReader { proxy in
            let plan = SlideNumpadPlan(size: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(plan.items, id: \.control) { item in
                    controlButton(item.control, frame: item.frame)
                        .frame(width: item.frame.width, height: item.frame.height)
                        .position(x: item.frame.midX, y: item.frame.midY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private func controlButton(_ control: SlideNumpadControl, frame: CGRect) -> some View {
        let spec = Self.spec(for: control)
        let highlighted = control == .nextSlide
        return Button {
            Haptics.light()
            perform(spec.action)
        } label: {
            VStack(spacing: 3) {
                if let symbol = spec.symbol {
                    Image(systemName: symbol).font(.system(size: frame.height >= 64 ? 24 : 18, weight: .semibold))
                }
                if spec.symbol == nil || frame.height >= 48 {
                    Text(spec.title)
                        .font(.system(size: spec.symbol == nil ? 22 : 13, weight: spec.symbol == nil ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(highlighted ? BrandPalette.primaryFill : BrandPalette.overlayKey, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spec.title)
    }

    private func perform(_ action: Action) {
        switch action {
        case let .key(usage, mods):
            model.session.sendInput([.key(usage: usage, down: true, mods: mods), .key(usage: usage, down: false, mods: mods)])
        case let .media(kind):
            Task { await model.session.sendMediaKey(kind) }
        }
    }

    // MARK: Bảng nút

    private enum Action {
        case key(UInt16, InputModifiers)
        case media(MediaKeyKind)
    }

    private struct Spec {
        let title: String
        let symbol: String?
        let action: Action
    }

    private static func spec(for control: SlideNumpadControl) -> Spec {
        switch control {
        case .start: Spec(title: "Bắt đầu", symbol: "play.rectangle.fill", action: .key(0x3E, []))
        case .end: Spec(title: "Kết thúc", symbol: "xmark.rectangle", action: .key(0x29, []))
        case .previousSlide: Spec(title: "Trước", symbol: "chevron.left", action: .key(0x4B, []))
        case .nextSlide: Spec(title: "Sau", symbol: "chevron.right", action: .key(0x4E, []))
        case .space: Spec(title: "Space", symbol: "space", action: .key(0x2C, []))
        case .undo: Spec(title: "Hoàn tác", symbol: "arrow.uturn.backward", action: .key(0x1D, .command))
        case .mediaPrevious: Spec(title: "Bài trước", symbol: "backward.fill", action: .media(.previous))
        case .playPause: Spec(title: "Phát / Dừng", symbol: "playpause.fill", action: .media(.playPause))
        case .mediaNext: Spec(title: "Bài kế", symbol: "forward.fill", action: .media(.next))
        case .mute: Spec(title: "Tắt tiếng", symbol: "speaker.slash.fill", action: .media(.mute))
        case .volumeDown: Spec(title: "Giảm âm", symbol: "speaker.wave.1.fill", action: .media(.volumeDown))
        case .volumeUp: Spec(title: "Tăng âm", symbol: "speaker.wave.3.fill", action: .media(.volumeUp))
        case let .key(usage, label): Spec(title: label, symbol: nil, action: .key(usage, []))
        }
    }
}
