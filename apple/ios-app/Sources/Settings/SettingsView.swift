import SwiftUI
import XdeskViewer
import XdeskWire

/// Màn Cài đặt (mở từ nút bánh răng trên thanh công cụ): chế độ làm việc mặc định, kiểu chiếu màn hình, bộ mã hoá, giao diện, chuột và bảo mật.
struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    let model: StreamViewModel
    let pointer: PointerSettingsStore
    @State private var tailscaleState = TailscaleSupport.detect()

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                ForEach(WorkMode.allCases) { workMode in
                    Button {
                        Haptics.light()
                        model.defaultWorkMode = workMode
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: workMode.symbol)
                                .font(.title3)
                                .foregroundStyle(BrandPalette.primary)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workMode.title)
                                    .foregroundStyle(.primary)
                                Text(workMode.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if model.defaultWorkMode == workMode {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(BrandPalette.primary)
                            }
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.defaultWorkMode == workMode ? .isSelected : [])
                }
            } header: {
                Text("Chế độ làm việc mặc định")
            } footer: {
                Text("Chế độ sẽ tự mở khi bạn chạm vào máy Mac. Bạn vẫn có thể đổi nhanh giữa 5 chế độ ngay khi đang kết nối.")
            }
            if model.defaultWorkMode == .mirror { MirrorFitPicker(fit: $model.mirrorFit, pointer: pointer) }
            Section("Kết nối từ xa") {
                Button {
                    Haptics.light()
                    TailscaleSupport.openOrInstall(for: tailscaleState)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "network.badge.shield.half.filled")
                            .font(.title3)
                            .foregroundStyle(tailscaleState == .active ? BrandPalette.accent : BrandPalette.warning)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tailscale")
                                .foregroundStyle(.primary)
                            Text(tailscaleState.settingsSubtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(tailscaleState.statusBadge)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tailscaleState == .active ? BrandPalette.accent : BrandPalette.warning)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Section {
                Picker("Bộ mã hoá", selection: $model.videoCodec) {
                    Text("HEVC (H.265)").tag(VideoCodec.hevc)
                    Text("H.264").tag(VideoCodec.h264)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Bộ mã hoá video")
            } footer: {
                Text(model.videoCodec == .hevc
                     ? "HEVC nén tốt hơn ~40%, giảm độ trễ trên Wi-Fi/Tailscale và tiết kiệm pin."
                     : "H.264 tương thích rộng nhất với mọi thiết bị.")
            }
            AppearancePicker()
            Section("Điều khiển") {
                NavigationLink {
                    PointerSettingsForm(store: pointer)
                } label: {
                    LabeledContent("Chuột và con trỏ", value: pointer.settings.mode.title)
                }
            }
            Section("Bảo mật") {
                NavigationLink {
                    SecuritySettingsView(model: model)
                } label: {
                    LabeledContent("Thiết bị và máy đã ghép", value: "\(model.knownHosts.count) máy")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BrandPalette.background)
        .navigationTitle("Cài đặt")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            tailscaleState = TailscaleSupport.detect()
            await model.refreshTrust()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                tailscaleState = TailscaleSupport.detect()
            }
        }
    }
}
