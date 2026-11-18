import Foundation

// Dùng: swift run gen-test-vectors [thư mục đầu ra]  (mặc định: protocol/test-vectors cạnh repo root)
let defaultOut = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("protocol/test-vectors", isDirectory: true)
let outDir = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true) : defaultOut

write(controlVectors(), to: outDir.appendingPathComponent("control-frames.json"))
write(mediaVectors(), to: outDir.appendingPathComponent("media-headers.json"))
write(inputVectors(), to: outDir.appendingPathComponent("input-events.json"))
