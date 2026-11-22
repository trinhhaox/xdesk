import Observation
import SwiftUI
import XdeskInput
import XdeskWire

/// Vị trí con trỏ (0…1) dùng chung giữa chế độ Chuột và vùng di chuột của Bàn phím, để con trỏ không nhảy khi đổi chế độ.
@MainActor
@Observable
final class TrackpadCursor {
    var x: Float = 0.5
    var y: Float = 0.5
    var isLeftDown = false
    var isRightDown = false
}

/// Bề mặt bàn di chuột: 1 ngón di, chạm = click, 2 ngón cuộn / chuột phải, 3 ngón Mission Control. Dùng cho cả
/// chế độ Chuột và vùng di chuột phía trên bàn phím (màn dọc).
struct TrackpadPad: View {
    let model: StreamViewModel
    let cursor: TrackpadCursor
    var mods: InputModifiers = []
    var showsHint = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(BrandPalette.overlayCard)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.14), lineWidth: 1))

            VStack(spacing: 6) {
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.38))
                Text("Bàn di chuột cảm ứng")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                if showsHint {
                    Text("1 ngón: Di chuột · Chạm đúp giữ: Kéo thả\n2 ngón: Chuột phải / Cuộn · 3 ngón: Không gian & Cửa sổ")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.45))
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 16)
            .allowsHitTesting(false)

            TrackpadTouchSurface(
                onMove: { dx, dy in move(dx: dx, dy: dy) },
                onLeftClick: { click(InputButton.left) },
                onRightClick: { click(InputButton.right) },
                onScroll: { dx, dy in model.session.sendInput([.scroll(dx: dx, dy: dy, mods: mods)]) },
                onDragStateChange: { dragging in
                    cursor.isLeftDown = dragging
                    model.session.sendInput([.button(down: dragging, button: InputButton.left, x: cursor.x, y: cursor.y, mods: mods)])
                },
                onThreeFingerShortcut: { usage, mods in
                    Haptics.light()
                    model.session.sendInput([.key(usage: usage, down: true, mods: mods), .key(usage: usage, down: false, mods: mods)])
                }
            )
        }
    }

    private func move(dx: Float, dy: Float) {
        cursor.x = min(0.999, max(0.001, cursor.x + dx))
        cursor.y = min(0.999, max(0.001, cursor.y + dy))
        model.session.sendInput([.move(x: cursor.x, y: cursor.y, mods: mods)])
    }

    private func click(_ button: UInt8) {
        Haptics.light()
        model.session.sendInput([
            .button(down: true, button: button, x: cursor.x, y: cursor.y, mods: mods),
            .button(down: false, button: button, x: cursor.x, y: cursor.y, mods: mods),
        ])
    }
}

/// Chế độ "Chuột": bàn di chuột + hai nút Chuột Trái / Chuột Phải; nút thấp lại khi màn ngang.
struct TrackpadModeView: View {
    let model: StreamViewModel
    let cursor: TrackpadCursor
    let isLandscape: Bool

    var body: some View {
        VStack(spacing: 10) {
            TrackpadPad(model: model, cursor: cursor, showsHint: !isLandscape)
            HStack(spacing: 12) {
                clickButton("Chuột Trái", button: InputButton.left, isDown: cursor.isLeftDown)
                clickButton("Chuột Phải", button: InputButton.right, isDown: cursor.isRightDown)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func clickButton(_ title: String, button: UInt8, isDown: Bool) -> some View {
        Button {
            Haptics.light()
            model.session.sendInput([
                .button(down: true, button: button, x: cursor.x, y: cursor.y, mods: []),
                .button(down: false, button: button, x: cursor.x, y: cursor.y, mods: []),
            ])
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: isLandscape ? 44 : 56)
                .background(isDown ? BrandPalette.primaryFill : BrandPalette.overlayKey, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in setDown(button, true) }
                .onEnded { _ in setDown(button, false) }
        )
    }

    private func setDown(_ button: UInt8, _ down: Bool) {
        if button == InputButton.left { cursor.isLeftDown = down } else { cursor.isRightDown = down }
    }
}
