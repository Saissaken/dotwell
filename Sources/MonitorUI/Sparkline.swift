import MonitorCore
import SwiftUI

private struct ChartMotionKey: EnvironmentKey {
    static let defaultValue: ChartMotion? = nil
}

extension EnvironmentValues {
    /// Set by the popover so every chart scrolls in step.
    var chartMotion: ChartMotion? {
        get { self[ChartMotionKey.self] }
        set { self[ChartMotionKey.self] = newValue }
    }
}

/// Minimal line chart. Negative values are gaps (e.g. lost pings) drawn as small red ticks.
///
/// With a `chartMotion` in the environment, the line scrolls continuously: each new point slides in from the
/// right edge over the time until the next one, redrawn up to 30 times a second. That only happens while the
/// popover is open (the views don't exist otherwise) and not with Reduce Motion.
struct Sparkline: View {
    var values: [Float]
    /// Fixed upper bound (e.g. 1 for fractions); nil = auto-scale to the window's max.
    var maxValue: Float? = nil
    var color: Color = .accentColor
    var capacity: Int? = nil

    @Environment(\.chartMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Smooth enough for a line that moves a few points a second, at a fraction of the display's refresh rate.
    static let frameInterval = 1.0 / 30

    var body: some View {
        if let motion, !reduceMotion {
            TimelineView(.animation(minimumInterval: Self.frameInterval)) { context in
                chart(slide: 1 - motion.progress(at: context.date))
            }
        } else {
            chart(slide: nil)
        }
    }

    /// `slide` is how far right of its resting place the line is, in steps (0...1); nil draws it still.
    /// While sliding, the oldest value is a lead-in kept just past the left edge, so no gap opens there.
    private func chart(slide: Double?) -> some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let slots = max(capacity ?? values.count, values.count)
            let lead = slide == nil || slots < 3 ? 0 : 1
            let step = size.width / CGFloat(max(1, slots - 1 - lead))
            let shift = CGFloat(slide ?? 0) - CGFloat(lead)
            let offset = CGFloat(slots - values.count) * step
            let peak = maxValue ?? max(values.max() ?? 1, 0.0001)
            let h = size.height - 2

            func x(_ i: Int) -> CGFloat { offset + (CGFloat(i) + shift) * step }
            func point(_ i: Int, _ v: Float) -> CGPoint {
                CGPoint(x: x(i), y: 1 + h - CGFloat(min(v, peak) / peak) * h)
            }

            var line = Path()
            var fill = Path()
            var started = false
            var segmentStartX: CGFloat = 0
            var lastX: CGFloat = 0
            func closeFill() {
                guard started else { return }
                fill.addLine(to: CGPoint(x: lastX, y: size.height))
                fill.addLine(to: CGPoint(x: segmentStartX, y: size.height))
                fill.closeSubpath()
            }
            for (i, v) in values.enumerated() {
                if v < 0 {
                    closeFill()
                    started = false
                    ctx.fill(
                        Path(CGRect(x: x(i) - 0.75, y: size.height - 4, width: 1.5, height: 4)), with: .color(.red))
                    continue
                }
                let p = point(i, v)
                if started {
                    line.addLine(to: p)
                    fill.addLine(to: p)
                } else {
                    line.move(to: p)
                    fill.move(to: CGPoint(x: p.x, y: size.height))
                    fill.addLine(to: p)
                    segmentStartX = p.x
                    started = true
                }
                lastX = p.x
            }
            closeFill()
            ctx.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.28), color.opacity(0.02)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(
                line, with: .color(color), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
