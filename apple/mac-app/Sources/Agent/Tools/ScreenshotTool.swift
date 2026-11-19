import Foundation
import XdeskAgent

struct ScreenshotTool: ToolHandler {
    let runtime: AgentRuntime

    func call(arguments: JsonValue) async -> ToolResult {
        guard case .success(let context) = await runtime.requireDisplay() else { return .error("Chưa có màn hình agent.") }
        do {
            let png = try await ScreenshotService.capture(displayID: context.id, geometry: context.geometry)
            return .ok(context.geometry.coordinateNote, images: [ToolImage(mimeType: "image/png", base64: png.base64EncodedString())], audit: "png=\(png.count)B")
        } catch { return .error("Chụp màn hình thất bại: \(error.localizedDescription)") }
    }
}
