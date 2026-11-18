import SwiftUI

/// Plots locally recorded TPS over the span collected so far, up to 24 hours.
struct ThroughputSparkline: View {
    let points: [ThroughputPoint]
    var tint: Color = .accentColor
    var seriesTitle = "Median TPS"

    var body: some View {
        Canvas { context, size in
            guard let start = points.first?.date, let end = points.last?.date, end > start,
                  let low = points.map(\.tps).min(), let high = points.map(\.tps).max() else { return }
            let inset: CGFloat = 3
            let width = size.width - 2 * inset
            let height = size.height - 2 * inset
            let span = end.timeIntervalSince(start)

            // Contiguous runs of readings; a long silence breaks the line.
            var runs: [[CGPoint]] = []
            var previous: Date?
            for point in points {
                if previous.map({ point.date.timeIntervalSince($0) > ThroughputHistory.maxGap }) ?? true {
                    runs.append([])
                }
                previous = point.date
                let fraction = high > low ? (point.tps - low) / (high - low) : 0.5
                let x = inset + width * CGFloat(point.date.timeIntervalSince(start) / span)
                runs[runs.count - 1].append(CGPoint(x: x, y: inset + height * (1 - fraction)))
            }

            let fill = Gradient(colors: [tint.opacity(0.28), tint.opacity(0)])
            for run in runs where run.count > 1 {
                var line = Path()
                line.addLines(run)
                var area = line
                area.addLine(to: CGPoint(x: run[run.count - 1].x, y: size.height))
                area.addLine(to: CGPoint(x: run[0].x, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(fill, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                context.stroke(line, with: .color(tint),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }

            // A smaller dot marks the first reading, a larger one the latest.
            func dot(_ point: CGPoint, diameter: CGFloat) {
                context.fill(Path(ellipseIn: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                                                    width: diameter, height: diameter)), with: .color(tint))
            }
            if let first = runs.first?.first { dot(first, diameter: 3.5) }
            if let last = runs.last?.last { dot(last, diameter: 4.5) }
        }
        .accessibilityLabel("TPS trend")
        .accessibilityValue(description)
        .help(description)
    }

    private var description: String {
        guard let first = points.first, let last = points.last, last.date > first.date else { return "TPS trend" }
        let span = Duration.seconds(last.date.timeIntervalSince(first.date))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
        let low = points.map(\.tps).min() ?? first.tps
        let high = points.map(\.tps).max() ?? last.tps
        return "\(seriesTitle) over \(span): \(first.tps.tpsText) at "
            + "\(first.date.formatted(date: .omitted, time: .shortened)) → \(last.tps.tpsText) at "
            + "\(last.date.formatted(date: .omitted, time: .shortened)) "
            + "(range \(low.tpsText)–\(high.tpsText))"
    }
}
