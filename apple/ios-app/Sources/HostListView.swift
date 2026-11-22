import SwiftUI
import UIKit
import XdeskCrypto
import XdeskInput
import XdeskTransport
import XdeskViewer
import XdeskWire

/// Màn chính: Mac đã ghép (mọi máy trong kho tin cậy), Mac khác trên LAN chưa ghép, máy nhập tay/Tailscale.
struct HostListView: View {
    @Environment(\.scenePhase) private var scenePhase
    let model: StreamViewModel
    @AppStorage("xdesk.lastManualHost") var manualText = ""
    /// Đích chưa ghép đôi đang chờ người dùng chọn cách ghép.
    @State var choosing: ViewerTarget?
    @State var changedKey: KeyChange?
    @State var showScanner = false
    @State var forgetting: PairedDevice?
    /// Mac đã ghép nhưng không có đường kết nối nào (không thấy trên LAN, chưa có địa chỉ): hiện thẻ lỗi thay vì im lặng.
    @State var unreachable: PairedHostRow?
    @State var pointer = PointerSettingsStore()
    @State var tailscaleState = TailscaleSupport.detect()
    @State var pendingTailscale: PendingTailscale?

    struct PendingTailscale {
        let address: String
        let state: TailscaleState
        let proceed: () -> Void
    }

    struct KeyChange: Identifiable {
        let host: DiscoveredHost
        let expected: PairedDevice
        var id: String { host.id }
    }

    var pairedRows: [PairedHostRow] {
        PairedHostListing.rows(paired: model.knownHosts, discoveredIds: Set(model.hosts.map(\.id)), manual: model.manualHosts)
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.localNetworkDenied { localNetworkGuidance }
                if let failure = currentFailure { errorSection(failure) }
                tailscaleBanner
                if pairedRows.isEmpty {
                    EmptyPairingState { showScanner = true }
                } else {
                    pairedSection
                }
                unpairedSection
                savedSection
                OtherConnectionsSection(
                    model: model,
                    manualText: $manualText,
                    onScanQr: pairedRows.isEmpty ? nil : { showScanner = true },
                    tailscaleState: tailscaleState,
                    onTailscaleAction: { TailscaleSupport.openOrInstall(for: tailscaleState) },
                    onConnect: connectManual
                )
            }
            .scrollContentBackground(.hidden)
            .background(BrandPalette.background)
            .navigationTitle("Xdesk")
            .refreshable {
                tailscaleState = TailscaleSupport.detect()
                model.stopBrowsing()
                model.startBrowsing()
            }
            .toolbar {
                ToolbarItemGroup {
                    Button("Tìm lại", systemImage: "arrow.clockwise") {
                        tailscaleState = TailscaleSupport.detect()
                        model.stopBrowsing()
                        model.startBrowsing()
                    }
                    if !pairedRows.isEmpty {
                        Button("Thêm máy Mac", systemImage: "plus") { showScanner = true }
                    }
                    NavigationLink {
                        SettingsView(model: model, pointer: pointer)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Cài đặt")
                }
            }
            .sheet(isPresented: $showScanner) { PairWithMacView(model: model) }
            .forgetHostDialog($forgetting, model: model)
            .confirmationDialog("Chưa ghép đôi với máy này", isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }),
                                titleVisibility: .visible, presenting: choosing) { target in
                Button("Quét mã QR trên Mac") { showScanner = true }
                Button("So mã 6 số") { Task { await model.pairWithCode(to: target) } }
            } message: { _ in
                Text("Ghép đôi một lần, những lần sau Xdesk tự kết nối.")
            }
            .alert("Khoá của máy này đã đổi", isPresented: Binding(get: { changedKey != nil }, set: { if !$0 { changedKey = nil } }), presenting: changedKey) { change in
                Button("Quên khoá cũ", role: .destructive) { Task { await model.forgetHost(id: change.expected.id) } }
                Button("Đóng", role: .cancel) {}
            } message: { change in
                Text("\"\(change.host.name)\" có khoá khác lần ghép trước: máy được cài lại hoặc có thiết bị khác đang mạo danh. Xdesk không kết nối. Chỉ chọn \"Quên khoá cũ\" nếu bạn biết máy đó vừa được cài lại.")
            }
            .alert("Mac từ chối kết nối", isPresented: Binding(get: { model.refusedHost != nil }, set: { if !$0 { model.refusedHost = nil } }),
                   presenting: model.refusedHost) { refused in
                Button("Ghép đôi lại") {
                    Task {
                        await model.forgetHost(id: refused.hostId)
                        choosing = refused.target
                    }
                }
                Button("Đóng", role: .cancel) {}
            } message: { _ in
                Text("Máy Mac không còn nhận thiết bị này, thường là do đã bấm \"Thu hồi\" trên Mac. Chọn \"Ghép đôi lại\" để quét mã QR hoặc so mã 6 số.")
            }
            .alert(
                pendingTailscale?.state == .installedInactive ? "Tailscale đang tắt" : "Chưa cài đặt Tailscale",
                isPresented: Binding(get: { pendingTailscale != nil }, set: { if !$0 { pendingTailscale = nil } }),
                presenting: pendingTailscale
            ) { pending in
                Button(pending.state == .installedInactive ? "Mở Tailscale" : "Cài đặt Tailscale") {
                    if pending.state == .installedInactive { TailscaleSupport.openApp() } else { TailscaleSupport.openInstall() }
                }
                Button("Vẫn thử kết nối") { pending.proceed() }
                Button("Đóng", role: .cancel) {}
            } message: { pending in
                Text(
                    pending.state == .installedInactive
                        ? "Kết nối tới \(pending.address) cần bật Tailscale trên điện thoại trước."
                        : "Địa chỉ \(pending.address) là địa chỉ Tailscale. Cài đặt và bật Tailscale để kết nối từ xa."
                )
            }
        }
        .onAppear {
            tailscaleState = TailscaleSupport.detect()
            model.startBrowsing()
            Task {
                await model.loadManualHosts()
                await model.refreshTrust()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                tailscaleState = TailscaleSupport.detect()
            }
        }
        .onDisappear { model.stopBrowsing() }
    }
}
