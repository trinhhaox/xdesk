import SwiftUI
import UIKit
import XdeskCrypto
import XdeskInput
import XdeskTransport
import XdeskViewer
import XdeskWire

/// Màn chính: Mac đã ghép (mọi máy trong kho tin cậy), Mac khác trên LAN chưa ghép, máy nhập tay/Tailscale.
struct HostListView: View {
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
                if pairedRows.isEmpty { EmptyPairingState { showScanner = true } } else { ScanQrRow { showScanner = true } }
                if !pairedRows.isEmpty { pairedSection }
                unpairedSection
                savedSection
                Section { SettingsSummaryRow(model: model, pointer: pointer) }
                OtherConnectionsSection(model: model, manualText: $manualText, onConnect: connectManual)
            }
            .scrollContentBackground(.hidden)
            .background(BrandPalette.background)
            .navigationTitle("Xdesk")
            .refreshable { model.stopBrowsing(); model.startBrowsing() }
            .toolbar {
                ToolbarItemGroup {
                    Button("Tìm lại", systemImage: "arrow.clockwise") { model.stopBrowsing(); model.startBrowsing() }
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
        }
        .onAppear {
            model.startBrowsing()
            Task {
                await model.loadManualHosts()
                await model.refreshTrust()
            }
        }
        .onDisappear { model.stopBrowsing() }
    }
}
