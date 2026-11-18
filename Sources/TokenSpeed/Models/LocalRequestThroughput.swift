import Foundation

struct LocalRequestThroughput: Sendable {
    static let codexPreferenceKey = "ShowCodexThroughput"
    static let claudePreferenceKey = "ShowClaudeThroughput"
    static let window: TimeInterval = 60 * 60

    enum Source: String, Codable, Sendable {
        case codex
        case claudeCode

        var title: String {
            switch self {
            case .codex: "Codex"
            case .claudeCode: "Claude Code"
            }
        }
    }

    enum Tier: String, Codable, Sendable {
        case standard = "Default"
        case fast = "Fast"
        case ultrafast = "Ultrafast"
        case flex = "Flex"
        case unknown = "Tier unknown"

        init(_ value: String?) {
            switch value?.lowercased() {
            case "default", "standard", "normal": self = .standard
            case "priority", "fast": self = .fast
            case "ultrafast": self = .ultrafast
            case "flex": self = .flex
            default: self = .unknown
            }
        }
    }

    struct Pin: Codable, Equatable, Sendable {
        let source: Source
        let modelID: String
        let tier: Tier
    }

    struct Request: Sendable {
        let model: String
        let tier: Tier
        let startedAt: Date
        let completedAt: Date?
        let reading: ThroughputPoint?
    }

    struct Reading: Identifiable, Sendable {
        let tier: Tier
        let points: [ThroughputPoint]
        var id: Tier { tier }
        var average: Double? {
            guard !points.isEmpty else { return nil }
            return points.reduce(0) { $0 + $1.tps } / Double(points.count)
        }
    }

    struct Model: Identifiable, Sendable {
        let id: String
        let readings: [Reading]
    }

    let models: [Model]

    init(requests: [Request], now: Date) {
        let cutoff = now.addingTimeInterval(-Self.window)
        let recent = requests.filter { request in
            let date = request.completedAt ?? request.startedAt
            return date >= cutoff && date <= now
        }.sorted {
            if $0.startedAt == $1.startedAt { return $0.model < $1.model }
            return $0.startedAt > $1.startedAt
        }
        let requestsByModel = Dictionary(grouping: recent, by: \.model)
        var included: Set<String> = []
        models = recent.compactMap { request in
            guard included.insert(request.model).inserted,
                  let modelRequests = requestsByModel[request.model] else { return nil }
            return Model(id: request.model, readings: Self.readings(for: modelRequests))
        }
    }

    private static func readings(for requests: [Request]) -> [Reading] {
        var tiers: [Tier] = []
        var points: [Tier: [ThroughputPoint]] = [:]
        for request in requests {
            if points[request.tier] == nil {
                tiers.append(request.tier)
                points[request.tier] = []
            }
            if let reading = request.reading { points[request.tier]?.append(reading) }
        }
        return tiers.map { tier in
            Reading(tier: tier, points: (points[tier] ?? []).sorted { $0.date < $1.date })
        }
    }
}
