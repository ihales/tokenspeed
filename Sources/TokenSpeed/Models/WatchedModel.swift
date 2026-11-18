import Foundation

struct ProviderEndpoint: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let providerID: String
    let providerName: String
    let tier: String?

    var detail: String {
        let suffix = id.split(separator: "/").dropFirst().joined(separator: "/")
        let tierName = tier?.capitalized ?? "Standard"
        switch suffix {
        case "", "ultrafast": return tierName
        case "fast": return "Priority (Fast)"
        default: return "\(tierName) · \(suffix)"
        }
    }

    var title: String { "\(providerName) · \(detail)" }

    static let vertexGlobal = Self(id: "google-vertex/global", providerID: "google-vertex",
                                   providerName: "Google Vertex", tier: nil)
}

struct WatchedModel: Identifiable, Codable, Sendable {
    let id: String
    let model: OpenRouterModel
    var endpoint: ProviderEndpoint?

    var providerID: String { endpoint?.providerID ?? "" }
    var providerName: String { endpoint?.providerName ?? "Automatic" }

    var title: String {
        endpoint.map { "\(model.shortName) · \($0.title)" } ?? "\(model.shortName) · Automatic"
    }

    static func migrating(_ model: OpenRouterModel) -> Self {
        .init(id: model.id, model: model, endpoint: model.id == "meta/muse-ember" ? .vertexGlobal : nil)
    }
}

struct ProviderGroup: Identifiable {
    let id: String
    let title: String
    var models: [WatchedModel]

    var isAutomatic: Bool { id.isEmpty }

    static func grouped(_ watched: [WatchedModel]) -> [Self] {
        var groups: [Self] = []
        for item in watched {
            if let index = groups.firstIndex(where: { $0.id == item.providerID }) {
                groups[index].models.append(item)
            } else {
                groups.append(.init(id: item.providerID, title: item.providerName, models: [item]))
            }
        }
        return groups
    }
}

struct EndpointReading: Sendable {
    let endpoint: ProviderEndpoint
    let tps: Double?
    let throughputWindowMinutes: Int?
    let uptime: Double?

    init(endpoint: ProviderEndpoint, tps: Double? = nil, throughputWindowMinutes: Int? = nil, uptime: Double? = nil) {
        self.endpoint = endpoint
        self.tps = tps
        self.throughputWindowMinutes = throughputWindowMinutes
        self.uptime = uptime
    }

    var windowDescription: String? {
        guard let minutes = throughputWindowMinutes, tps != nil else { return nil }
        if minutes.isMultiple(of: 60) {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return "\(minutes) minutes"
    }

    var windowTitle: String? {
        guard let minutes = throughputWindowMinutes, tps != nil else { return nil }
        return minutes.isMultiple(of: 60) ? "\(minutes / 60)h" : "\(minutes)m"
    }
}

/// One locally recorded TPS reading for an endpoint.
struct ThroughputPoint: Codable, Sendable {
    let date: Date
    let tps: Double
}

struct ModelReadings: Sendable {
    let endpoints: [EndpointReading]
    let tpsAvailable: Bool
    let uptimeAvailable: Bool

    func reading(for watch: WatchedModel) -> EndpointReading? {
        if let endpoint = watch.endpoint {
            return endpoints.first { $0.endpoint.id == endpoint.id }
        }
        if let window = endpoints.compactMap(\.throughputWindowMinutes).min() {
            return endpoints.filter { $0.throughputWindowMinutes == window }
                .max { ($0.tps ?? 0) < ($1.tps ?? 0) }
        }
        return endpoints.first { $0.uptime != nil } ?? endpoints.first
    }

}
