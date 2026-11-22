import Testing
import XdeskWire
@testable import Xdesk

@Suite struct XdeskIOSTests {
    @Test func workModesCoverAllFiveModesWithAccurateMetadata() {
        #expect(WorkMode.allCases.count == 5)
        #expect(WorkMode.mirror.isVideoMode && WorkMode.mirror.screenMode == .mirror)
        #expect(WorkMode.extend.isVideoMode && WorkMode.extend.screenMode == .extend)
        for control in [WorkMode.trackpad, .keyboard, .numpadMedia] {
            #expect(control.isControlMode)
            #expect(!control.isVideoMode)
            #expect(control.screenMode == nil)
        }
    }

    @Test func tailscaleHostDetectionMatchesCgnatUlaAndMagicDns() {
        #expect(TailscaleSupport.isTailscaleHost("100.64.0.1"))
        #expect(TailscaleSupport.isTailscaleHost("100.76.38.107:47800"))
        #expect(TailscaleSupport.isTailscaleHost("fd7a:115c:a1e0::1"))
        #expect(TailscaleSupport.isTailscaleHost("macbook.tail1234.ts.net"))
        #expect(!TailscaleSupport.isTailscaleHost("192.168.1.5"))
        #expect(!TailscaleSupport.isTailscaleHost("100.63.255.255"))
        #expect(!TailscaleSupport.isTailscaleHost("100.128.0.1"))
    }

    @Test func streamQualityPresetRespectsHardwareRefreshRateCap() {
        #expect(StreamQualityPreset.saver30.effectiveFps(maxDeviceFps: 120) == 30)
        #expect(StreamQualityPreset.standard60.effectiveFps(maxDeviceFps: 120) == 60)
        #expect(StreamQualityPreset.high120.effectiveFps(maxDeviceFps: 120) == 120)
        #expect(StreamQualityPreset.high120.effectiveFps(maxDeviceFps: 60) == 60)
        #expect(StreamQualityPreset.saver30.effectiveFps(maxDeviceFps: 24) == 30)
    }

    @Test func screenMetricsStoresExplicitMaxFps() {
        let metrics = ScreenMetrics(size: .init(width: 430, height: 932), scale: 3, maxFps: 120)
        #expect(metrics.maxFps == 120)
    }
}
