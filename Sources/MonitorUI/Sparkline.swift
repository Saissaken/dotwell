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

    /// Set by the popover: how many points a full chart of the range on screen holds.
    var chartPoints: Int? {
        get { self[ChartPointsKey.self] }
        set { self[ChartPointsKey.self] = newValue }
    }
}

private struct ChartPointsKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

/// Where a sparkline's points go across its width.
///
/// The spacing comes from how many points the chart holds when full, not from how many it has, so a chart whose
/// history is still filling draws its line at the final spacing, ending at the right edge, and new points push
/// it left. Spreading the few points over the whole width instead would stretch the line and make every point
/// jump sideways each time one is added.
struct SparklineLayout: Equatable {
    /// Points across the chart: its capacity, or the values it has if that is more.
    var slots: Int
    /// While sliding, the oldest slot is a lead-in kept just past the left edge, so no gap opens there.
    var lead: Int
    var step: CGFloat
    /// Where value 0 sits, in steps from the left edge.
    var origin: CGFloat

    /// `slide` is how far right of its resting place the line is, in steps (0...1); nil draws it still.
    init(count: Int, capacity: Int?, slide: Double?, width: CGFloat) {
        slots = max(capacity ?? count, count)
        lead = slide == nil || slots < 3 ? 0 : 1
        step = width / CGFloat(max(1, slots - 1 - lead))
        origin = CGFloat(slots - count) + CGFloat(slide ?? 0) - CGFloat(lead)
    }

    func x(_ i: Int) -> CGFloat { (origin + CGFloat(i)) * step }
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
    @Environment(\.chartPoints) private var chartPoints
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
    private func chart(slide: Double?) -> some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let layout = SparklineLayout(
                count: values.count, capacity: capacity ?? chartPoints, slide: slide, width: size.width)
            let peak = maxValue ?? max(values.max() ?? 1, 0.0001)
            let h = size.height - 2

            func x(_ i: Int) -> CGFloat { layout.x(i) }
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
