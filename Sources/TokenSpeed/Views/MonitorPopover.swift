import AppKit
import SwiftUI

struct MonitorPopover: View {
    let store: MonitorStore
    let showSettings: () -> Void

    private static let maxListHeight: CGFloat = 420

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.watched.isEmpty {
                ContentUnavailableView {
                    Label("No Models Yet", systemImage: "gauge.with.dots.needle.33percent")
                } description: {
                    Text("Add OpenRouter models to track their output speed.")
                } actions: {
                    Button("Add Models…", action: showSettings)
                }
                .padding(.vertical, 12)
            } else {
                // Grows with its content up to a cap, then scrolls.
                ScrollView {
                    list
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: Self.maxListHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .frame(width: 440)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("TokenSpeed")
                .font(.headline)
            Spacer(minLength: 8)
            ForEach(store.matchingRules) { rule in
                BadgeChip(rule: rule)
                    .frame(maxWidth: 110)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.providerGroups) { group in
                HStack(spacing: 4) {
                    if group.isAutomatic {
                        Image(systemName: "bolt.fill").imageScale(.small)
                    }
                    Text(group.isAutomatic ? "Automatic · Fastest Endpoint" : group.title)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
                ForEach(group.models) { model in
                    ModelRow(store: store, model: model)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            status
            Spacer(minLength: 8)
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)
            .help("Refresh Now")
            .accessibilityLabel("Refresh now")
            .keyboardShortcut("r")
            Button(action: showSettings) {
                Image(systemName: "gearshape")
            }
            .help("Settings… (⌘,)")
            .accessibilityLabel("Settings")
            .keyboardShortcut(",")
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .help("Quit TokenSpeed (⌘Q)")
            .accessibilityLabel("Quit TokenSpeed")
            .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 36)
    }

    @ViewBuilder private var status: some View {
        if store.isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(store.hasLoaded ? "Refreshing…" : "Loading…")
            }
            .font(.caption)
        } else if store.failedCount > 0 {
            Label("\(store.failedCount) of \(store.watched.count) didn’t refresh", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .help("Hover a row to see its error. Stale rows keep their last readings and are ignored by badge rules.")
        } else if let updated = store.updatedAt {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(updatedText(updated, now: context.date))
                    .font(.caption)
                    .help("Fetched at \(updated.formatted(date: .omitted, time: .shortened)). Refreshes every minute.")
            }
        }
    }

    private func updatedText(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 30 { return "Updated just now" }
        return "Updated " + date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}

private struct ModelRow: View {
    let store: MonitorStore
    let model: WatchedModel
    @ViewState private var isHovered = false

    private var reading: EndpointReading? { store.reading(for: model) }
    private var isPinned: Bool { model.id == store.headlineID }
    private var isStale: Bool { store.isStale(model) }

    var body: some View {
        let reading = reading
        let error = store.refreshError(for: model)

        HStack(spacing: 10) {
            Color.clear
                .frame(width: 14, height: 14)
                .overlay { leadingIndicator(error: error) }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.model.shortName)
                    .fontWeight(isPinned ? .semibold : .regular)
                    .lineLimit(1)
                if let endpoint = model.endpoint?.detail ?? reading?.endpoint.title {
                    Text(isStale ? "Stale · \(endpoint)" : endpoint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(error ?? reading?.endpoint.title ?? model.title)

            Group {
                let history = store.history(for: model)
                if history.count >= 2 {
                    ThroughputSparkline(points: history, tint: isStale ? .secondary : .accentColor)
                } else {
                    Text("Collecting…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("TokenSpeed records this endpoint’s speed every 5 minutes to draw a 24-hour trend.")
                }
            }
            .frame(width: 60, height: 26)

            VStack(alignment: .trailing, spacing: 1) {
                Text(reading?.tps?.tpsText ?? "–")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(reading?.windowTitle.map { "tok/s · \($0)" } ?? "tok/s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 66, alignment: .trailing)
            .help(reading?.windowDescription.map { "Median output tokens per second over the last \($0)" }
                  ?? "No recent throughput reading")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading?.tps.map { "\($0.tpsText) tokens per second" } ?? "TPS unavailable")

            VStack(alignment: .trailing, spacing: 1) {
                Text(reading?.uptime?.uptimeText ?? "–")
                    .font(.callout)
                    .foregroundStyle(reading?.uptime.map { UptimeHealth($0).style } ?? AnyShapeStyle(.secondary))
                Text("uptime")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50, alignment: .trailing)
            .help("Uptime over the last 24 hours")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading?.uptime.map { "\($0.uptimeText) 24-hour uptime" } ?? "Uptime unavailable")
        }
        .monospacedDigit()
        .opacity(isStale ? 0.55 : 1)
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
            Button("Show in Menu Bar", systemImage: "pin") { store.headlineID = model.id }
                .disabled(isPinned)
            if let url = model.model.providersURL {
                Button("Open on OpenRouter", systemImage: "safari") { NSWorkspace.shared.open(url) }
            }
        }
    }

    @ViewBuilder
    private func leadingIndicator(error: String?) -> some View {
        if isStale {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .help(error ?? "Couldn’t refresh")
                .accessibilityLabel("Stale: \(error ?? "couldn’t refresh")")
        } else if isPinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tint)
                .help("Shown in the menu bar")
                .accessibilityLabel("Menu bar model")
        } else if isHovered {
            Button {
                store.headlineID = model.id
            } label: {
                Image(systemName: "pin")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Show in Menu Bar")
            .accessibilityLabel("Show \(model.model.shortName) in menu bar")
        }
    }
}
