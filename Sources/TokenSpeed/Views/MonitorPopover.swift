import AppKit
import SwiftUI

struct MonitorPopover: View {
    private enum Source: String {
        case local
        case openRouter
    }

    let store: MonitorStore
    let showSettings: () -> Void
    @AppStorage("PopoverThroughputSource") private var selectedSource: Source = .local
    @AppStorage(LocalRequestThroughput.codexPreferenceKey) private var showCodexThroughput = true
    @AppStorage(LocalRequestThroughput.claudePreferenceKey) private var showClaudeThroughput = true

    private static let maxListHeight: CGFloat = 420

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            // Grows with its content up to a cap, then scrolls.
            ScrollView {
                Group {
                    switch selectedSource {
                    case .local: localList
                    case .openRouter: openRouterList
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .id(selectedSource)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: Self.maxListHeight)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            footer
        }
        .frame(width: 440)
    }

    // MARK: Header

    private var header: some View {
        let badges = store.matchingRules
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("TokenSpeed")
                    .font(.headline)
                Spacer(minLength: 8)
                sourceSwitcher
            }
            .frame(height: 42)

            if !badges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(badges) { rule in
                        BadgeChip(rule: rule)
                            .frame(maxWidth: 124)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 16)
    }

    private var sourceSwitcher: some View {
        HStack(spacing: 2) {
            sourceButton(.local, title: "Local", symbol: "laptopcomputer")
            sourceButton(.openRouter, title: "OpenRouter", symbol: "globe")
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.primary.opacity(0.08)) }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Throughput source")
    }

    private func sourceButton(_ source: Source, title: String, symbol: String) -> some View {
        let isSelected = selectedSource == source
        return Button {
            selectedSource = source
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: List

    private var localList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showCodexThroughput {
                LocalThroughputSection(store: store, source: .codex)
            }
            if showClaudeThroughput {
                LocalThroughputSection(store: store, source: .claudeCode)
            }
            if !showCodexThroughput && !showClaudeThroughput {
                ContentUnavailableView {
                    Label("Local Tracking Is Off", systemImage: "gauge.with.dots.needle.33percent")
                } actions: {
                    Button("Settings…", action: showSettings)
                }
                .padding(.vertical, 12)
            }
        }
    }

    private var openRouterList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if store.watched.isEmpty {
                ContentUnavailableView {
                    Label("No Models Yet", systemImage: "gauge.with.dots.needle.33percent")
                } description: {
                    Text("Add OpenRouter models to track their output speed.")
                } actions: {
                    Button("Add Models…", action: showSettings)
                }
                .padding(.vertical, 12)
            }
            ForEach(store.providerGroups) { group in
                ProviderHeading(title: group.isAutomatic ? "Automatic · Fastest Endpoint" : group.title,
                                symbol: group.isAutomatic ? "bolt.fill" : nil)
                ForEach(group.models) { model in
                    ModelRow(store: store, model: model)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if selectedSource == .openRouter { status }
            Spacer(minLength: 8)
            Button {
                switch selectedSource {
                case .local:
                    if showCodexThroughput { Task { await store.refreshLocal(.codex) } }
                    if showClaudeThroughput { Task { await store.refreshLocal(.claudeCode) } }
                case .openRouter: Task { await store.refresh() }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(selectedSource == .openRouter && store.isRefreshing)
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
    private var isPinned: Bool { store.isHeadline(model) }
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
