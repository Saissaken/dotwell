import SwiftUI

/// Minimal line chart. Negative values are gaps (e.g. lost pings) drawn as small red ticks.
struct Sparkline: View {
    var values: [Float]
    /// Fixed upper bound (e.g. 1 for fractions); nil = auto-scale to the window's max.
    var maxValue: Float? = nil
    var color: Color = .accentColor
    var capacity: Int? = nil

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let slots = max(capacity ?? values.count, values.count)
            let step = size.width / CGFloat(max(1, slots - 1))
            let offset = CGFloat(slots - values.count) * step
            let peak = maxValue ?? max(values.max() ?? 1, 0.0001)
            let h = size.height - 2

            func point(_ i: Int, _ v: Float) -> CGPoint {
                CGPoint(x: offset + CGFloat(i) * step, y: 1 + h - CGFloat(min(v, peak) / peak) * h)
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
                    let x = offset + CGFloat(i) * step
                    ctx.fill(Path(CGRect(x: x - 0.75, y: size.height - 4, width: 1.5, height: 4)), with: .color(.red))
                    continue
                }
                let p = point(i, v)
                if started {
                    line.addLine(to: p); fill.addLine(to: p)
                } else {
                    line.move(to: p)
                    fill.move(to: CGPoint(x: p.x, y: size.height)); fill.addLine(to: p)
                    segmentStartX = p.x
                    started = true
                }
                lastX = p.x
            }
            closeFill()
            ctx.fill(fill, with: .linearGradient(
                Gradient(colors: [color.opacity(0.28), color.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
