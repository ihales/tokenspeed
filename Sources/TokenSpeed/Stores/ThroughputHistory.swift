import Foundation

/// TPS readings TokenSpeed records itself, since OpenRouter only publishes daily history.
/// Every endpoint of a watched model is recorded, so switching endpoints keeps its trend.
struct ThroughputHistory: Codable {
    static let window: TimeInterval = 24 * 60 * 60
    /// Minimum spacing between recorded points. Polling runs every minute.
    static let interval: TimeInterval = 5 * 60
    /// A longer silence (sleep, app not running) breaks the sparkline instead of bridging it.
    static let maxGap: TimeInterval = 15 * 60

    private var series: [String: [ThroughputPoint]] = [:]

    private static func key(modelID: String, endpointID: String) -> String { "\(modelID)|\(endpointID)" }

    func points(modelID: String, endpointID: String) -> [ThroughputPoint] {
        series[Self.key(modelID: modelID, endpointID: endpointID)] ?? []
    }

    /// Returns whether any point was added.
    mutating func record(modelID: String, readings: [EndpointReading], at date: Date) -> Bool {
        var changed = false
        for reading in readings {
            guard let tps = reading.tps else { continue }
            let key = Self.key(modelID: modelID, endpointID: reading.endpoint.id)
            // Allow some slack so a 60-second poll lands on every fifth tick.
            if let last = series[key]?.last, date.timeIntervalSince(last.date) < Self.interval - 15 { continue }
            series[key, default: []].append(ThroughputPoint(date: date, tps: tps))
            changed = true
        }
        return changed
    }

    /// Drops points older than the window and series for models no longer watched.
    mutating func prune(keepingModels modelIDs: Set<String>, now: Date) {
        let cutoff = now.addingTimeInterval(-Self.window)
        series = series.reduce(into: [:]) { result, entry in
            guard let modelID = entry.key.split(separator: "|", maxSplits: 1).first,
                  modelIDs.contains(String(modelID)) else { return }
            let recent = entry.value.drop { $0.date < cutoff }
            if !recent.isEmpty { result[entry.key] = Array(recent) }
        }
    }

    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TokenSpeed", isDirectory: true)
            .appendingPathComponent("throughput-history.json")
    }

    static func load(from url: URL?) -> Self {
        guard let url, let data = try? Data(contentsOf: url) else { return Self() }
        return (try? JSONDecoder().decode(Self.self, from: data)) ?? Self()
    }

    func save(to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
