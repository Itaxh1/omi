# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class CaptureLiveActivityWaveTest < Minitest::Test
  def test_liquid_dock_reference_ripple_and_live_state_from_the_actual_widget_source
    source = File.read(File.expand_path('../BatteryWidget/OmiCaptureLiveActivity.swift', __dir__))
    attributes = File.read(File.expand_path('../LiveActivity/OmiCaptureAttributes.swift', __dir__))
    ripple = source[/enum CaptureRipple \{.*?(?=\/\/\/ Device scaling)/m]
    snapshot = source[/struct CaptureSnapshot \{.*?(?=@available\(iOS 16\.1, \*\)\s*extension)/m]
    attributes = attributes[/struct OmiCaptureAttributes: ActivityAttributes \{.*?(?=\/\/\/ Lives in both targets)/m]
      .sub(': ActivityAttributes', '')
    refute_nil ripple
    refute_nil snapshot

    Dir.mktmpdir('omi-wave-test') do |dir|
      path = File.join(dir, 'main.swift')
      binary = File.join(dir, 'wave-test')
      File.write(path, <<~SWIFT)
        import Foundation
        #{attributes}
        #{ripple}
        #{snapshot}

        for tick in 0..<640 {
            let seconds = Double(tick) / 100
            for bar in 0..<50 {
                let value = CaptureRipple.pulse(bar, seconds: seconds)
                precondition(value >= 0.45 - 0.000001 && value <= 1 + 0.000001)
                precondition(abs(value - CaptureRipple.pulse(bar, seconds: seconds + 1.6)) < 0.000001)
                precondition(abs(value - CaptureRipple.pulse(bar + 13, seconds: seconds)) < 0.000001)
            }
        }
        // Independent reference samples: CSS lvl 1.6s ease-in-out, 50% scaleY(.45).
        let reference: [(Double, Double)] = [
            (0, 1), (0.2, 0.928960955), (0.4, 0.725), (0.6, 0.521039045),
            (0.8, 0.45), (1.2, 0.725), (1.6, 1)]
        for (seconds, expected) in reference {
            precondition(abs(CaptureRipple.pulse(0, seconds: seconds) - expected) < 0.000001)
        }
        precondition(abs(CaptureRipple.pulse(1, seconds: 0) - CaptureRipple.pulse(0, seconds: 0.13)) < 0.000001)
        var state = OmiCaptureAttributes.ContentState(
            conversationRevision: 1, status: "listening", source: "phone", batch: false,
            startedAt: Date().timeIntervalSince1970 - 6, elapsed: 6, paused: false,
            canPause: true, canFinish: true, busy: false, metered: true,
            voice: true, levels: [10, 80, 35], levelsEnd: 48)
        func frame(_ stale: Bool = false) -> CaptureSnapshot {
            CaptureSnapshot(recordingId: "first", state: state, isStale: stale)
        }
        precondition(frame().isReceivingAudio && frame().rippleTick == 48)
        precondition(!frame(true).isReceivingAudio)
        for status in ["paused", "interrupted", "reconnecting", "ended"] {
            state.status = status
            precondition(!frame().isReceivingAudio, "retained meter samples must not imply live audio")
        }
        state.status = "recording"
        state.paused = true
        precondition(!frame().isReceivingAudio)
        state.paused = false
        state.metered = false
        state.levels = []
        precondition(frame().isReceivingAudio && frame().rippleTick == 48)
        state.elapsed = 7
        precondition(frame().rippleTick == 56)
      SWIFT
      output, status = Open3.capture2e('swiftc', path, '-o', binary)
      assert status.success?, output
      output, status = Open3.capture2e(binary)
      assert status.success?, output
    end
  end
end
