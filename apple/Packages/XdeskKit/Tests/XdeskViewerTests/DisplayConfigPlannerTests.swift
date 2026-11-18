import Foundation
import Testing
import XdeskWire
@testable import XdeskViewer

@Suite struct DisplayConfigPlannerTests {
    @Test func iPhoneProMaxPortraitAndLandscape() throws {
        let portrait = try #require(DisplayConfigPlanner.config(pointsWidth: 430, pointsHeight: 932, scale: 3))
        #expect((portrait.w, portrait.h, portrait.scale) == (1290, 2796, 3))
        let landscape = try #require(DisplayConfigPlanner.config(pointsWidth: 932, pointsHeight: 430, scale: 3))
        #expect((landscape.w, landscape.h) == (2796, 1290))
        #expect(portrait != landscape)
    }

    @Test func mirrorModeIsSentAndExtendIsOmitted() throws {
        let mirror = try #require(DisplayConfigPlanner.config(pointsWidth: 430, pointsHeight: 932, scale: 3, mode: .mirror))
        #expect(mirror.mode == .mirror)
        let extend = try #require(DisplayConfigPlanner.config(pointsWidth: 430, pointsHeight: 932, scale: 3))
        #expect(extend.mode == nil && extend.screenMode == .extend)
        let json = String(decoding: try JSONEncoder().encode(mirror), as: UTF8.self)
        #expect(json.contains("\"mode\":\"mirror\""))
        let decoded = try JSONDecoder().decode(DisplayConfig.self, from: Data(#"{"codec":"h264","fps":60,"h":2,"scale":1,"w":2}"#.utf8))
        #expect(decoded.screenMode == .extend)
    }

    @Test func iPadPro13() throws {
        let config = try #require(DisplayConfigPlanner.config(pointsWidth: 1032, pointsHeight: 1376, scale: 2))
        #expect((config.w, config.h) == (2064, 2752))
    }

    @Test func oddPixelsRoundUpToEven() throws {
        let config = try #require(DisplayConfigPlanner.config(pointsWidth: 375.5, pointsHeight: 667, scale: 1))
        #expect((config.w, config.h) == (376, 668))
    }

    @Test func clampsToWireLimits() throws {
        let config = try #require(DisplayConfigPlanner.config(pointsWidth: 10000, pointsHeight: 10000, scale: 20))
        #expect(config.w == 16384 && config.h == 16384 && config.scale == 8)
    }

    @Test(arguments: [0.0, -1, .nan, .infinity])
    func rejectsInvalidInput(value: Double) {
        #expect(DisplayConfigPlanner.config(pointsWidth: value, pointsHeight: 100, scale: 2) == nil)
        #expect(DisplayConfigPlanner.config(pointsWidth: 100, pointsHeight: 100, scale: value) == nil)
    }

    @Test func producedConfigPassesWireValidation() throws {
        let config = try #require(DisplayConfigPlanner.config(pointsWidth: 430, pointsHeight: 932, scale: 3))
        let bytes = try ControlMessageCodec.encode(ControlEnvelope(id: 1, message: .displayConfig(config)))
        #expect(try ControlMessageCodec.decode(bytes).message == .displayConfig(config))
    }
}
