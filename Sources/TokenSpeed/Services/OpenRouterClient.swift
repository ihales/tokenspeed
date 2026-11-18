import Foundation

struct OpenRouterClient: Sendable {
    private struct Envelope<Value: Decodable>: Decodable {
        let data: Value
    }

    private struct PerformanceEndpoint: Decodable, Sendable {
        struct Stats: Decodable, Sendable {
            let p50Throughput: Double?
            let throughputWindowMinutes: Int?

            enum CodingKeys: String, CodingKey {
                case p50Throughput = "p50_throughput"
                case throughputWindowMinutes = "throughput_window_minutes"
            }
        }

        let id: String
        let providerSlug: String
        let providerPermaslug: String
        let providerDisplayName: String
        let serviceTier: String?
        let stats: Stats?

        enum CodingKeys: String, CodingKey {
            case id
            case providerSlug = "provider_slug"
            case providerPermaslug = "provider_permaslug"
            case providerDisplayName = "provider_display_name"
            case serviceTier = "service_tier"
            case stats
        }
    }

    private struct PublicEndpoints: Decodable, Sendable {
        struct Endpoint: Decodable, Sendable {
            let tag: String
            let providerName: String
            let serviceTier: String?
            let uptimeLastDay: Double?

            enum CodingKeys: String, CodingKey {
                case tag
                case providerName = "provider_name"
                case serviceTier = "service_tier"
                case uptimeLastDay = "uptime_last_1d"
            }
        }

        let endpoints: [Endpoint]
    }

    private static let modelsURL = URL(string: "https://openrouter.ai/api/v1/models")!
    // This public feed supplies OpenRouter's provider table.
    private static let statsURL = URL(string: "https://openrouter.ai/api/frontend/v1/stats/endpoint")!

    func models() async throws -> [OpenRouterModel] {
        try await fetch(Self.modelsURL, as: [OpenRouterModel].self)
    }

    func readings(for model: OpenRouterModel) async throws -> ModelReadings {
        let query: [URLQueryItem] = [
            .init(name: "permaslug", value: model.canonicalSlug ?? model.id),
            .init(name: "variant", value: model.variant)
        ]
        let publicURL = model.id.split(separator: "/").reduce(Self.modelsURL) {
            $0.appendingPathComponent(String($1))
        }.appendingPathComponent("endpoints")

        async let live = sample(Self.statsURL.appending(queryItems: query), as: [PerformanceEndpoint].self)
        async let publicStats = sample(publicURL, as: PublicEndpoints.self)

        let performanceResult = await live
        let uptimeResult = await publicStats
        let performanceRows = try? performanceResult.get()
        let uptimeRows = try? uptimeResult.get().endpoints
        if performanceRows == nil && uptimeRows == nil {
            _ = try performanceResult.get()
        }
        let performance = Dictionary((performanceRows ?? []).map { ($0.providerSlug, $0) },
                                     uniquingKeysWith: { first, _ in first })
        let uptime = Dictionary((uptimeRows ?? []).map { ($0.tag, $0) },
                                uniquingKeysWith: { first, _ in first })
        let tags = Set(performance.keys).union(uptime.keys).sorted()
        let readings = tags.map { tag -> EndpointReading in
            let row = performance[tag]
            let publicRow = uptime[tag]
            let providerID = row?.providerPermaslug ?? String(tag.split(separator: "/").first ?? "")
            let name = row?.providerDisplayName ?? publicRow?.providerName ?? providerID
            let endpoint = ProviderEndpoint(id: tag, providerID: providerID, providerName: name,
                                            tier: publicRow?.serviceTier ?? row?.serviceTier)
            let minutes = row?.stats?.throughputWindowMinutes
            let tps = row?.stats?.p50Throughput.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            let uptimePercent = publicRow?.uptimeLastDay.flatMap { (0...100).contains($0) ? $0 : nil }
            return .init(endpoint: endpoint, tps: tps, throughputWindowMinutes: tps == nil ? nil : minutes,
                         uptime: uptimePercent)
        }
        return ModelReadings(endpoints: readings, tpsAvailable: performanceRows != nil, uptimeAvailable: uptimeRows != nil)
    }

    private func sample<Value: Decodable & Sendable>(_ url: URL, as type: Value.Type) async -> Result<Value, Error> {
        do {
            return .success(try await fetch(url, as: type))
        } catch {
            return .failure(error)
        }
    }

    private func fetch<Value: Decodable & Sendable>(_ url: URL, as type: Value.Type) async throws -> Value {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else { throw APIError(status: response.statusCode) }
        return try JSONDecoder().decode(Envelope<Value>.self, from: data).data
    }

    private struct APIError: LocalizedError {
        let status: Int
        var errorDescription: String? { "OpenRouter returned HTTP \(status)." }
    }
}
