import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

// The v3 look (the app's mono palette, `OmiColors`): paper and ink, one grey for secondary words,
// the warm tone behind secondary buttons. Text and controls keep one size on every iPhone; only the
// pendant (hero art) scales with the device, as Your Omi does in the app.

/// v3 tokens. The Lock Screen card follows the phone's light or dark look; the island is always
/// black, so it keeps the dark set.
enum CapturePalette {
    private static func rgb(_ hex: Int) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    private static func uiRGB(_ hex: Int, alpha: CGFloat) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static let led = Color(red: 0x4C / 255, green: 0x9B / 255, blue: 0xFF / 255)
    /// The Lock Screen card: paper (white, or #0A0A0A in dark), a touch translucent like the system's.
    static let card = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? CapturePalette.uiRGB(0x0A0A0A, alpha: 0.92) : CapturePalette.uiRGB(0xFFFFFF, alpha: 0.94)
    })

    static func ink(for scheme: ColorScheme) -> CaptureInk {
        scheme == .dark ? island : CaptureInk(
            primary: rgb(0x0A0A0A), secondary: rgb(0x656565), tone: rgb(0xF1EFEA),
            fill: rgb(0x0A0A0A), onFill: .white)
    }

    static let island = CaptureInk(
        primary: .white, secondary: rgb(0xABABAB), tone: Color.white.opacity(0.14),
        fill: .white, onFill: rgb(0x0A0A0A))
}

/// The colours one presentation draws with: words, secondary words, the Pause pill (tone) and the
/// Stop pill (fill, with its words in onFill).
struct CaptureInk {
    let primary: Color
    let secondary: Color
    let tone: Color
    let fill: Color
    let onFill: Color
}

/// `omi-liquid-dock2.html`: 1.6 s, CSS ease-in-out, scaleY(.45) at the midpoint,
/// and a negative 130 ms delay per neighbouring bar (repeating every 13 bars).
/// ActivityKit samples this curve when content updates arrive; it does not run
/// the HTML's continuous animation clock between updates.
enum CaptureRipple {
    static let period = 1.6
    static let stagger = 0.13
    static let levels: [Double] = [
        0.22, 0.35, 0.5, 0.3, 0.62, 0.8, 0.45, 0.28, 0.55, 0.9, 0.7, 0.38, 0.25, 0.42, 0.66, 0.52, 0.3, 0.2, 0.35, 0.58,
        0.76, 0.6, 0.4, 0.33, 0.48, 0.7, 0.85, 0.5, 0.3, 0.24, 0.4, 0.62, 0.45, 0.3, 0.52, 0.72, 0.56, 0.36, 0.28, 0.44,
        0.6, 0.8, 0.64, 0.4, 0.3, 0.5, 0.66, 0.42, 0.3, 0.26,
    ]

    static func pulse(_ index: Int, seconds: Double) -> Double {
        let phase = ((seconds + Double(index % 13) * stagger) / period)
            .truncatingRemainder(dividingBy: 1)
        let progress = phase <= 0.5 ? phase * 2 : (1 - phase) * 2
        return 1 - 0.55 * easeInOut(progress)
    }

    /// CSS ease-in-out is cubic-bezier(.42, 0, .58, 1), not a cosine.
    private static func easeInOut(_ progress: Double) -> Double {
        if progress <= 0 { return 0 }
        if progress >= 1 { return 1 }
        var low = 0.0
        var high = 1.0
        for _ in 0..<24 {
            let t = (low + high) / 2
            let u = 1 - t
            let x = 3 * u * u * t * 0.42 + 3 * u * t * t * 0.58 + t * t * t
            if x < progress { low = t } else { high = t }
        }
        let t = (low + high) / 2
        return 3 * (1 - t) * t * t + t * t * t
    }
}

/// Device scaling from tokens.json `layout.KH`.
enum CaptureLayout {
    /// clamp((height − safeTop − safeBottom) / 764, 0.8, 1.1). The extension has
    /// no window insets, so they come from the design's device profiles.
    static var heroScale: CGFloat {
        let height = UIScreen.main.bounds.height
        let safeTop: CGFloat = height >= 874 ? 62 : height >= 852 ? 54 : height >= 812 ? 48 : 20
        let safeBottom: CGFloat = height >= 812 ? 34 : 0
        return min(1.1, max(0.8, (height - safeTop - safeBottom) / 764))
    }
}

/// Everything a capture presentation draws, independent of ActivityKit so the
/// same views can be rendered for layout verification.
@available(iOS 16.1, *)
struct CaptureSnapshot {
    let recordingId: String
    let state: OmiCaptureAttributes.ContentState
    let isStale: Bool

    var isReceivingAudio: Bool {
        !isStale && !state.paused && (state.status == "listening" || state.status == "recording")
    }

    /// This phone's microphone is recording, not the pendant.
    var isPhone: Bool { state.source == "phone" }

    /// While the mic is on, the second this update carries: the orb breathes on it (the app's orb
    /// breathes too). Nil when nothing is captured, so everything holds still.
    var breath: Int? { isReceivingAudio ? state.elapsed : nil }

    /// Where the ripple is: measured audio moves it by its own bins; otherwise, while the mic is
    /// on, it moves eight bins a second like the app's wave.
    var rippleTick: Int {
        if !state.levels.isEmpty { return state.levelsEnd }
        return isReceivingAudio ? state.elapsed * 8 : 0
    }

    /// A live timer's ideal width is unbounded, so the clock always gets a
    /// fixed slot, in ems of its font size: the design's 30 pt "02:16" is
    /// 95.5 pt wide (3.2 em); h:mm:ss after the first hour needs 4.3 em.
    var clockEms: CGFloat {
        let elapsed = state.paused || state.status == "ended"
            ? Double(state.elapsed) : Date().timeIntervalSince1970 - state.startedAt
        return elapsed >= 3600 ? 4.3 : 3.2
    }
}

@available(iOS 16.1, *)
extension ActivityViewContext where Attributes == OmiCaptureAttributes {
    var omiSnapshot: CaptureSnapshot {
        var stale = false
        if #available(iOS 16.2, *) { stale = isStale }
        return CaptureSnapshot(recordingId: attributes.recordingId, state: state, isStale: stale)
    }
}

@available(iOS 16.1, *)
struct OmiCaptureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OmiCaptureAttributes.self) { context in
            CaptureLockScreenView(snapshot: context.omiSnapshot)
                .activityBackgroundTint(CapturePalette.card)
                .widgetURL(captureURL(context.attributes.recordingId))
        } dynamicIsland: { context in
            let snapshot = context.omiSnapshot
            let ink = CapturePalette.island
            let island = DynamicIsland {
                // One row beside the camera (pendant and word | clock), then the wave and the two
                // buttons. iOS caps the expanded island near 160 pt and puts the camera between the
                // leading and trailing regions, so the row is split around it and the second line
                // (no room beside the camera on any iPhone) is left to the Lock Screen card.
                DynamicIslandExpandedRegion(.leading) {
                    CaptureIslandLeading(snapshot: snapshot, ink: ink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CaptureClock(snapshot: snapshot, ink: ink, size: 30)
                        .frame(maxHeight: .infinity, alignment: .center)
                        // Clear of the island's ~44 pt top corner curve.
                        .padding(.top, 6)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // Measured on a 402 pt iPhone: the bottom region starts ~78 pt
                    // into a 160 pt island, which leaves exactly 22 + 10 + 38.
                    VStack(spacing: 10) {
                        CaptureWaveform(snapshot: snapshot, ink: ink, height: 22)
                        CaptureActions(snapshot: snapshot, ink: ink, height: 38)
                    }
                }
            } compactLeading: {
                // Restore the early v2 live mark: five blue bars beside the camera.
                CaptureMiniWave(snapshot: snapshot)
                    .padding(.leading, 4)
            } compactTrailing: {
                CaptureCompactClock(snapshot: snapshot)
            } minimal: {
                CaptureMiniWave(snapshot: snapshot)
            }
            .widgetURL(captureURL(context.attributes.recordingId))
            .keylineTint(CapturePalette.led)
            // Default side margins leave ~100 pt beside the camera; 12 pt gives
            // the pendant and a short word room without shrinking text.
            if #available(iOS 17.0, *) {
                return island.contentMargins(.horizontal, 12, for: .expanded)
            }
            return island
        }
    }
}

private func captureURL(_ id: String) -> URL? {
    // The callback scheme is supplied by the embedding app's configuration.
    var components = URLComponents()
    components.scheme = Bundle.main.object(forInfoDictionaryKey: "OmiCaptureURLScheme") as? String ?? "omi"
    components.host = "app"
    components.path = "/capture"
    components.queryItems = [URLQueryItem(name: "recording", value: id)]
    return components.url
}

/// The Lock Screen card, as Your Omi opens in the app: the pendant, what it is doing ("Listening")
/// over where the sound comes from ("Omi · Transcribing live"), the clock on the right; the wave;
/// then Pause (the tone pill) and Stop (the ink pill). Paper and ink, following light and dark.
@available(iOS 16.1, *)
struct CaptureLockScreenView: View {
    let snapshot: CaptureSnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = CapturePalette.ink(for: scheme)
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                CapturePendant(active: snapshot.isReceivingAudio, size: 40 * CaptureLayout.heroScale, breath: snapshot.breath, phone: snapshot.isPhone)
                CaptureStatus(snapshot: snapshot, ink: ink, showSource: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CaptureClock(snapshot: snapshot, ink: ink, size: 30)
            }
            .frame(minHeight: 48)
            CaptureWaveform(snapshot: snapshot, ink: ink, height: 26)
            CaptureActions(snapshot: snapshot, ink: ink, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .foregroundStyle(ink.primary)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// Pendant and word beside the camera. Where the word does not fit next to
/// the pendant it is dropped rather than shrunk; text never scales down.
@available(iOS 16.1, *)
private struct CaptureIslandLeading: View {
    let snapshot: CaptureSnapshot
    let ink: CaptureInk

    var body: some View {
        // The pendant, "Listening" and "Transcribing live" beside the camera. Where the second line or
        // then the word does not fit (~111 pt on most iPhones) it is dropped, never shrunk.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                CapturePendant(active: snapshot.isReceivingAudio, size: 32, breath: snapshot.breath, phone: snapshot.isPhone)
                CaptureStatus(snapshot: snapshot, ink: ink, showSource: false)
                    .fixedSize()
            }
            HStack(spacing: 6) {
                CapturePendant(active: snapshot.isReceivingAudio, size: 32, breath: snapshot.breath, phone: snapshot.isPhone)
                CaptureStatus(snapshot: snapshot, ink: ink, showSource: false, titleOnly: true)
                    .fixedSize()
            }
            CapturePendant(active: snapshot.isReceivingAudio, size: 32, breath: snapshot.breath, phone: snapshot.isPhone)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // Clear of the island's ~44 pt top corner curve.
        .padding(.top, 6)
        .padding(.leading, 4)
        // The island is height-capped; keep its text inside the budget.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }
}

@available(iOS 16.1, *)
private struct CaptureStatus: View {
    let snapshot: CaptureSnapshot
    let ink: CaptureInk
    let showSource: Bool
    var titleOnly = false

    private var state: OmiCaptureAttributes.ContentState { snapshot.state }

    /// The app's words for what Omi is doing (the Listening label's).
    private var title: LocalizedStringKey {
        if snapshot.isStale { return "Open Omi to reconnect" }
        if state.actionFailed { return "Open Omi to continue" }
        switch state.status {
        case "ended": return "Finished"
        // The reader's Pause, and the OS holding the microphone (which resumes by itself).
        case "paused", "interrupted": return "Paused"
        case "connecting": return "Connecting…"
        case "recording": return "Recording"
        case "reconnecting": return "Reconnecting…"
        default: return "Listening"
        }
    }

    /// Where the sound comes from, as Devices names it: "This iPhone", or the pendant, "Omi".
    private var source: Text {
        state.source == "phone" ? Text("This iPhone") : Text(verbatim: "Omi")
    }

    /// What is happening to the audio right now; nil falls back to the source.
    private var detail: LocalizedStringKey? {
        if state.busy { return "Updating…" }
        switch state.status {
        case "listening": return "Transcribing live"
        case "recording": return "Transcribe Later"
        case "interrupted": return "Resumes automatically"
        default: return nil
        }
    }

    /// "Omi · Transcribing live" when it fits on one line, else just where the sound comes from, so
    /// the card keeps one height. The island shows only what is happening.
    @ViewBuilder
    private var subtitle: some View {
        if let detail {
            if showSource {
                ViewThatFits(in: .horizontal) {
                    (source + Text(verbatim: " · ") + Text(detail)).lineLimit(1)
                    source.lineLimit(1)
                }
            } else {
                Text(detail).lineLimit(2)
            }
        } else {
            source.lineLimit(1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // The app's type: the word at 17/600, the line under it at 13.
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ink.primary)
                .lineLimit(1)
            if !titleOnly {
                subtitle
                    .font(.system(size: 13))
                    .foregroundStyle(ink.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The clock (the app's live clock: medium weight, tabular), flush right in a slot sized for its
/// longest value.
@available(iOS 16.1, *)
private struct CaptureClock: View {
    let snapshot: CaptureSnapshot
    let ink: CaptureInk
    @ScaledMetric private var size: CGFloat

    init(snapshot: CaptureSnapshot, ink: CaptureInk, size: CGFloat) {
        self.snapshot = snapshot
        self.ink = ink
        _size = ScaledMetric(wrappedValue: size, relativeTo: .title)
    }

    var body: some View {
        CaptureClockText(snapshot: snapshot, color: ink.primary)
            .font(.system(size: size, weight: .medium))
            .frame(width: size * snapshot.clockEms, alignment: .trailing)
    }
}

/// The compact island's clock: 15 pt, 14 pt from the island's trailing edge.
@available(iOS 16.1, *)
private struct CaptureCompactClock: View {
    let snapshot: CaptureSnapshot

    var body: some View {
        CaptureClockText(snapshot: snapshot, color: CapturePalette.island.primary)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 15 * snapshot.clockEms, alignment: .trailing)
            .padding(.trailing, 4)
    }
}

@available(iOS 16.1, *)
private struct CaptureClockText: View {
    let snapshot: CaptureSnapshot
    let color: Color

    var body: some View {
        let state = snapshot.state
        Group {
            if snapshot.isStale {
                Text(verbatim: "—")
            } else if state.paused || state.status == "ended" {
                // Frozen value in the same format the live timer uses.
                let seconds = max(0, state.elapsed)
                Text(verbatim: seconds >= 3600
                    ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                    : String(format: "%d:%02d", seconds / 60, seconds % 60))
            } else {
                // A live timer reserves width for its range's longest value, so
                // the range ends at the next hour; periodic updates extend it.
                let start = Date(timeIntervalSince1970: state.startedAt)
                let hours = (max(0, Date().timeIntervalSince(start)) / 3600).rounded(.down) + 1
                Text(timerInterval: start...start.addingTimeInterval(hours * 3600), countsDown: false)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .foregroundStyle(color)
        .lineLimit(1)
        .accessibilityLabel(Text("Recording duration"))
    }
}

/// The Omi pendant, as the app shows it: its photo with the light on while audio is captured, its
/// lights-off photo otherwise. While the mic is on a soft blue halo breathes behind it on alternate
/// seconds (the pendant's own light).
struct CapturePendant: View {
    let active: Bool
    let size: CGFloat
    /// While the mic is on, the second of the latest update: the halo is soft on odd seconds.
    var breath: Int? = nil
    /// The recording is this phone's: its glyph in a tone circle instead of the pendant's photo.
    var phone = false

    var body: some View {
        if phone {
            Image(systemName: "iphone")
                .font(.system(size: size * 0.5, weight: .regular))
                .foregroundStyle(.primary.opacity(active ? 1 : 0.6))
                .frame(width: size, height: size)
                .background(Circle().fill(.primary.opacity(0.1)))
                .accessibilityHidden(true)
        } else {
            pendantPhoto
        }
    }

    private var pendantPhoto: some View {
        let soft = active && (breath ?? 0) % 2 == 1
        return Image(active ? "device-omi" : "device-omi-off")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: CapturePalette.led.opacity(active ? (soft ? 0.25 : 0.5) : 0), radius: size * 0.18)
            .animation(.easeInOut(duration: 1.0), value: breath)
            .accessibilityHidden(true)
    }
}

/// Early v2's five blue bars, with the taller centre and a soft ripple on each live update.
/// Paused, disconnected and stale recordings keep five quiet grey marks.
@available(iOS 16.1, *)
private struct CaptureMiniWave: View {
    let snapshot: CaptureSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let arch: [CGFloat] = [0.62, 0.86, 1, 0.86, 0.62]

    var body: some View {
        let live = snapshot.isReceivingAudio
        let tick = reduceMotion ? 0 : snapshot.rippleTick
        HStack(alignment: .center, spacing: 2.2) {
            ForEach(0..<5, id: \.self) { index in
                let amplitude: CGFloat = snapshot.state.voice ? 1 : 0.7
                Capsule()
                    .fill(live ? CapturePalette.led : CapturePalette.island.secondary.opacity(0.55))
                    .frame(width: 2.6, height: live
                        ? max(3, 18 * Self.arch[index] * amplitude) * CGFloat(CaptureRipple.pulse(index, seconds: Double(tick) / 8))
                        : 3)
            }
        }
        .frame(width: 22, height: 18)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: tick)
        .accessibilityHidden(true)
    }
}

/// The listening wave on the Lock Screen and in the expanded island, in ink: bars 2 pt wide,
/// 2.2 pt apart. While audio flows each update eases the ripple on across the second; heard voice
/// lifts it to full height, a quiet room keeps it softer. Paused, it settles to a hairline; a
/// source that cannot be metered ripples at the same pace while the mic is on.
@available(iOS 16.1, *)
private struct CaptureWaveform: View {
    let snapshot: CaptureSnapshot
    let ink: CaptureInk
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let barWidth: CGFloat = 2
    private static let gap: CGFloat = 2.2

    var body: some View {
        let state = snapshot.state
        GeometryReader { geometry in
            // Never derive layout from an unbounded proposal; it cannot be placed.
            let width = geometry.size.width.isFinite ? max(0, geometry.size.width) : 0
            let count = max(1, Int((width + Self.gap) / (Self.barWidth + Self.gap)))
            if !snapshot.isReceivingAudio || (state.metered && state.levels.isEmpty) {
                // Retained meter samples must never make a paused/stale source look live.
                Capsule()
                    .fill(ink.primary.opacity(0.24))
                    .frame(width: width, height: 1.5)
                    .frame(width: width, height: height)
            } else if !state.levels.isEmpty {
                let amplitude = state.voice ? 1.0 : 0.62
                HStack(alignment: .center, spacing: Self.gap) {
                    ForEach(0..<count, id: \.self) { index in
                        Capsule()
                            .fill(ink.primary.opacity(0.92))
                            .frame(
                                width: Self.barWidth,
                                height: barHeight(index, amplitude: amplitude, tick: reduceMotion ? 0 : state.levelsEnd)
                            )
                    }
                }
                .frame(width: width, height: height, alignment: .leading)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.0), value: state.levelsEnd)
            } else {
                // Audio that cannot be measured still ripples while the mic is on (the app's wave does),
                // one step a second; with the mic off it holds still and dim.
                HStack(alignment: .center, spacing: Self.gap) {
                    ForEach(0..<count, id: \.self) { index in
                        Capsule()
                            .fill(ink.primary.opacity(0.55))
                            .frame(width: Self.barWidth,
                                   height: barHeight(index, amplitude: 0.8, tick: reduceMotion ? 0 : snapshot.rippleTick))
                    }
                }
                .frame(width: width, height: height, alignment: .leading)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.0), value: snapshot.rippleTick)
            }
        }
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }

    private func barHeight(_ index: Int, amplitude: Double, tick: Int) -> CGFloat {
        let base = CaptureRipple.levels[index % CaptureRipple.levels.count]
        // The prototype clamps the unscaled bar first, then scales the entire
        // shape. Clamping again afterwards makes short bars stop pulsing early.
        return max(3, height * CGFloat(base * amplitude)) * CGFloat(CaptureRipple.pulse(index, seconds: Double(tick) / 8))
    }
}

/// Your Omi's two buttons, 8 pt apart: Pause (or Resume) on the tone, Stop in ink, 15 pt words.
@available(iOS 16.1, *)
private struct CaptureActions: View {
    let snapshot: CaptureSnapshot
    let ink: CaptureInk
    let height: CGFloat

    private var state: OmiCaptureAttributes.ContentState { snapshot.state }

    var body: some View {
        if #available(iOS 17.0, *), !snapshot.isStale, state.status != "ended" {
            HStack(spacing: 8) {
                // Resume only after the reader paused; recovery states keep Pause.
                if state.canPause {
                    let paused = state.status == "paused"
                    action(paused ? "Resume" : "Pause", value: paused ? "resume" : "pause", enabled: true)
                }
                // Stop saves this conversation and stops listening until Start in Omi, so the
                // activity closes.
                action("Stop", value: "finish", enabled: state.canFinish, primary: true)
            }
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
    }

    @available(iOS 17.0, *)
    private func action(_ label: LocalizedStringKey, value: String, enabled: Bool, primary: Bool = false) -> some View {
        // An unavailable primary action drops to the tone pill so its label stays legible.
        let available = enabled && !state.busy
        let filled = primary && available
        return Button(intent: OmiCaptureIntent(recordingId: snapshot.recordingId,
                                               revision: state.conversationRevision, action: value)) {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                // Long translations shrink a little rather than cut off.
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: height)
                .foregroundStyle(filled ? ink.onFill : ink.primary.opacity(available ? 1 : 0.5))
                .background(filled ? ink.fill : ink.tone, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!available)
    }
}
