# Unisoc c2.unisoc.avc.decoder "holds 6-12 frames": root cause and fix (2026-11-19)

## Verdict
The decoder does NOT hold 6-12 frames. It holds exactly 1 (as `max_dec_frame_buffering=1` in the SPS says). The 6-12 was a
measurement bug in `FrameLagMeter` (`held = inCount - outCount`), with two independent inflations:

1. **Skipped frames leak forever.** The decoder never outputs a few % of the inputs (live1 recording: 9 of 1078). The old meter
   only incremented `outCount` for matched outputs, so every skipped frame stayed "held" permanently and the number only grew.
2. **Input backlog read as buffering.** A bursty network delivers several frames at once; `inCount-outCount` at output time
   is the queue of inputs waiting to be decoded, not buffered output.

Neither exists in the synthetic bench stream (no skips, even pacing) which is why it showed held<=1.

## Evidence
Same recording (`live1`: 1078 AUs captured from a live Tailscale session, replayed in DecoderBenchActivity at real arrival timing):
- Old accounting: inflight 7.3 -> 10.7 and growing, `heldAfterIdle=10`.
- Fixed accounting (skipped frames retired when a newer pts exits): inflight ~1.5, `heldAfterIdle=1`.
Nothing but the meter changed between the two runs.

Replay of live recordings (c2.unisoc, fixed meter; stuck = frames still inside after >=100 ms of total silence):

| recording / timing | p50 | p95 | max (non-stuck) | inflight avg | stuck depth | skipped |
|---|---|---|---|---|---|---|
| live1 arrival (real jitter) | 27.9 | 44 | 223 | 1.5 | 1.21 avg (19 events), max 5 | 9 |
| live1 even (decoder only) | 49.2 | 51 | 132 | 1.0 | 0 | 9 |
| live1 pts | 27.6 | 37 | 130 | 1.0 | 1.00 (16 events) | 9 |
| live2 arrival | 28.5 | 43 | 136 | 1.7 | 1.00 (2) | 2 |
| live2 even | 27.6 | 29 | 121 | 1.0 | 0 | 2 |

`even` p50 = 49 ms on live1 (39 ms spacing + ~10 ms decode) = exactly one frame held. Arrival p50 is lower (28) because
frames arrive faster than that average spacing.

Live (phone <-> Mac over Tailscale relay, final build, 8 pauses of 1.2 s): `p50=28.1 p95=48 max=117 inflight=1.4/4-5 stuck=8 events, depth 1.00`.
Before (lead, old meter): `p50 29-44 p95 108-142 max 2.0-5.2s held 3.1/6 .. 7.7/12`.
The multi-second max was the idle-stuck duplicate waiting for the next frame (stuck lag 400-1200 ms in the logs); it is now
reported separately (`stuck ... lag=`) instead of polluting max.

### Hypotheses
1. Meter misleading: CONFIRMED (above). Pts matching is fine (host pts strictly increasing via `nextPtsMs`, `unknown=0` outputs); the
   max outliers are idle-stuck frames, not pts collisions.
2. Live stream differs from bench: bitstream is NOT the cause. `ffprobe`/`trace_headers` on live1: High L4.2 720x1600, 1 slice/AU,
   no SEI/AUD, NAL pattern = 1071 non-IDR slices + 7x (SPS,PPS,IDR), `max_num_ref_frames=1 num_reorder_frames=0 max_dec_frame_buffering=1`,
   POC type 0. Differences that DO exist: keyframes mid-stream (7-9 per 40 s), skipped frames, and 3 (live1) / 1 (live2) AUs delivered
   out of pts order (see Concerns).
3. IdleFrameRepeater fires live: 19 idle gaps >=120 ms in live1; 16 end with a repeat frame arriving 54-60 ms after its predecessor
   (size ~1.1 KB, not tiny; 3 are tiny, 81-300 B); the other 3 are a keyframe reordered behind the repeat. So VT does not drop it and ABR/pacing
   do not skip it. Live idle now leaves exactly 1 stuck frame = the duplicate (live final run: depth 1.00 on all 8 pauses), so the screen shows current content.
4. Decoder mitigations: not needed (decoder holds the minimum). Swept on live1 `even`: scene-mode 0/1/2 -> p50 49.0/49.1/49.1 (no effect); c2.android SW
   -> p50 98.6, 2 held (worse). KEY_LOW_LATENCY/PRIORITY/OPERATING_RATE left as is. Not tried: ImageReader output, sync mode (no signal that they would help).

## Fix (right layer = measurement, plus tooling)
- `android/media/.../FrameLagMeter.kt`: `held` no longer leaks (skipped frames retired in output order); new `stuck` metric (depth when decoder silent >=100 ms,
  ignored until first output), stuck lag excluded from p50/p95/max, counters `skipped`, `skippedWhileStuck`, `unknown`.
- `VideoDecoder.kt`: log line now `inflight=avg/max stuck=Nx avg max lag skipped=N(stuck M) unknown=N`; optional `recorder`.
- New `FrameRecorder.kt` (+ `AppContainer.streamRecorder()`, `ViewerController`): debug-only live capture of the AUs fed to MediaCodec with arrival times.
  Enable: `adb shell run-as vn.xox.xdesk touch files/record-stream`; connect; leave stream (Back) to flush; `adb exec-out run-as vn.xox.xdesk cat files/live.bin` (+ `.arr`). Inert in release builds.
- `DecoderBenchActivity` (debug): `--es timing arrival|even|pts`, reads `files/` then external dir, writes full results to `files/bench.out`
  (logcat overflowed and silently dropped early windows), `setShowWhenLocked/TurnScreenOn`.
- Debug manifest: MainActivity `showWhenLocked/turnScreenOn` (phone is PIN-locked and sleeps in seconds; only debug).
- No host (Swift) change: host side is behaving as designed.
- Tests: `MediaLogicTest` (+4: burst is in-flight not stuck, quiet-gap stuck, skipped not held, existing updated), `FrameRecorderTest`.
  `./gradlew :wire:test :crypto:test :transport:test :media:test :app:testDebugUnitTest :app:assembleDebug -q` green.

## Concerns / follow-ups
- Reordered delivery (real bug, not fixed): Reassembler returns frames as completed, so a 65 KB keyframe (~50 packets) finishes after later P-frames
  (pts goes backwards 122/174/193 ms in live1; 1 case in live2). P-frames decoded before their IDR glitch until the next frame. Replay with pts forced
  monotonic still shows 9 skipped, so skips are bitstream-related, probably the reordered AUs (unproven). Suggest an in-order release gate in ViewerSession/Reassembler with a short timeout.
- Decoder skipping frames (0.2-0.8%) is unexplained; harmless for holding.
- Not re-verified with the LAN path (broken). Host Mac app was restarted without flags. Phone: record flag and recordings removed. 
- Other uncommitted android/apple changes in the tree (pointer/trackpad work) are not mine; my files: media/FrameLagMeter, VideoDecoder, FrameRecorder, MediaLogicTest, FrameRecorderTest,
  app AppContainer, ViewerController (4 lines), debug manifest, DecoderBenchActivity.
