// Phát N tiếng bíp 1 kHz (150 ms) vào loa mặc định đúng vào mốc đã hẹn để đo độ trễ audio của Xdesk.
// Chạy: swiftc -O beep.swift -o /tmp/xdesk-beep && /tmp/xdesk-beep [số_lần=5] [khoảng_cách_giây=2]
// In ra stdout `xdesk-beep wallMs=<unix ms lúc bíp rời mixer> outputLatencyMs=<trễ thiết bị>`; app Xdesk (Debug, --audio-report)
// in `xdesk-audio-onset wallMs=` khi viewer nhận được bíp. Hiệu hai mốc + trễ jitter buffer + trễ thiết bị phát = trễ miệng-tai.
import AVFoundation
import Foundation

let count = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 5
let gap = CommandLine.arguments.dropFirst(2).first.flatMap(Double.init) ?? 2

let engine = AVAudioEngine()
let player = AVAudioPlayerNode()
let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
let frames = AVAudioFrameCount(48_000 * 0.15)
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
buffer.frameLength = frames
for channel in 0..<2 {
    let data = buffer.floatChannelData![channel]
    for i in 0..<Int(frames) { data[i] = Float(sin(2 * Double.pi * 1000 * Double(i) / 48_000)) * 0.25 }
}
engine.attach(player)
engine.connect(player, to: engine.mainMixerNode, format: format)
try engine.start()
player.play()
let latencyMs = Int(engine.outputNode.presentationLatency * 1000)

func hostTime(afterSeconds seconds: Double) -> UInt64 {
    mach_absolute_time() + AVAudioTime.hostTime(forSeconds: seconds)
}

for _ in 0..<count {
    let lead = 0.3
    let when = hostTime(afterSeconds: lead)
    let wallMs = Int64((Date().timeIntervalSince1970 + lead) * 1000)
    player.scheduleBuffer(buffer, at: AVAudioTime(hostTime: when), options: [], completionHandler: nil)
    print("xdesk-beep wallMs=\(wallMs) outputLatencyMs=\(latencyMs)")
    fflush(stdout)
    Thread.sleep(forTimeInterval: gap)
}
engine.stop()
