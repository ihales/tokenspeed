import SwiftUI

struct LocalThroughputSection: View {
    let store: MonitorStore
    let source: LocalRequestThroughput.Source

    var body: some View {
        let activity = store.localActivity[source]
        let models = activity?.snapshot?.models ?? []
        let pinned = store.localHeadline.flatMap { pin in
            pin.source == source && store.localReading(for: pin) == nil ? pin : nil
        }
        VStack(alignment: .leading, spacing: 2) {
            ProviderHeading(title: source.title)

            ForEach(models) { model in
                ForEach(model.readings) { reading in
                    LocalModelRow(store: store, pin: .init(source: source, modelID: model.id, tier: reading.tier),
                                  reading: reading)
                }
            }
            if let pinned {
                LocalModelRow(store: store, pin: pinned, reading: nil)
            } else if models.isEmpty {
                Text(activity?.snapshot != nil ? "No recent completed requests"
                     : activity == nil ? "Reading local activity…" : "Timing logs unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 32)
                    .padding(.trailing, 8)
                    .padding(.vertical, 6)
            }
        }
        .task {
            await store.pollVisibleLocal(source)
        }
    }
}

private struct LocalModelRow: View {
    let store: MonitorStore
    let pin: LocalRequestThroughput.Pin
    let reading: LocalRequestThroughput.Reading?
    @ViewState private var isHovered = false

    private var isPinned: Bool { store.localHeadline == pin }
    private var modelName: String { store.localModelName(for: pin.modelID) }
    private var actionTitle: String { isPinned ? "Remove from Menu Bar" : "Show in Menu Bar" }

    var body: some View {
        let points = reading?.points ?? []
        let count = points.count
        let sampleCount = count == 1 ? "1 timed request" : "\(count.formatted()) timed requests"
        return HStack(spacing: 10) {
            Color.clear
                .frame(width: 14, height: 14)
                .overlay {
                    if isPinned || isHovered {
                        Button(action: togglePin) {
                            Image(systemName: isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(actionTitle)
                        .accessibilityLabel("\(actionTitle): \(modelName), \(pin.tier.rawValue)")
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(modelName)
                    .fontWeight(isPinned ? .semibold : .regular)
                    .lineLimit(1)
                Text(pin.tier.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if count == 1 {
                    Circle().fill(.tint).frame(width: 4.5, height: 4.5)
                        .accessibilityHidden(true)
                } else if count > 1 {
                    ThroughputSparkline(points: points, seriesTitle: "\(pin.source.title) request TPS")
                }
            }
            .frame(width: 60, height: 26)

            VStack(alignment: .trailing, spacing: 1) {
                Text(reading?.average?.tpsText ?? "–")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("tok/s · 1h")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 66, alignment: .trailing)
            .help("\(sampleCount) in the last hour. Includes the wait for first output and excludes tool execution between requests.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading?.average.map {
                "\($0.tpsText) average request tokens per second over the last hour, \(sampleCount)"
            } ?? "TPS unavailable, \(sampleCount)")

            VStack(alignment: .trailing, spacing: 1) {
                Text(count.formatted())
                    .font(.callout)
                Text(count == 1 ? "sample" : "samples")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(width: 50, alignment: .trailing)
            .help("Completed requests with matched start and completion times")
            .accessibilityHidden(true)
        }
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isPinned ? AnyShapeStyle(.tint.opacity(0.1))
                      : isHovered ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear))
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(actionTitle, systemImage: isPinned ? "pin.slash" : "pin", action: togglePin)
        }
    }

    private func togglePin() {
        store.localHeadline = isPinned ? nil : pin
    }
}
