import Foundation
import Observation

@MainActor @Observable
final class MonitorStore {
    private struct Preferences: Codable {
        var watched = OpenRouterModel.defaults.map(WatchedModel.migrating)
        var headlineID = OpenRouterModel.defaults.first?.id
        var localHeadline: LocalRequestThroughput.Pin?
        var rules: [BadgeRule] = []

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let current = try? container.decode([WatchedModel].self, forKey: .watched) {
                watched = current
            } else {
                watched = try container.decode([OpenRouterModel].self, forKey: .watched).map(WatchedModel.migrating)
            }
            headlineID = try container.decodeIfPresent(String.self, forKey: .headlineID) ?? watched.first?.id
            localHeadline = try? container.decode(LocalRequestThroughput.Pin.self, forKey: .localHeadline)
            rules = try container.decode([BadgeRule].self, forKey: .rules)
        }
    }

    private enum Sample: Sendable {
        case reading(ModelReadings)
        case failed(String)
    }

    // Returning the values in a tuple can abort task-group completion in
    // optimized builds on macOS 27.
    private struct ModelSample: Sendable {
        let modelID: String
        let sample: Sample
    }

    enum LocalActivity {
        case unavailable
        case available(LocalRequestThroughput)

        var snapshot: LocalRequestThroughput? {
            guard case let .available(snapshot) = self else { return nil }
            return snapshot
        }
    }

    private static let preferencesKey = "MonitorPreferences"
    private let client = OpenRouterClient()
    private let codexReader: CodexThroughputReader
    private let claudeReader: ClaudeThroughputReader
    private let defaults: UserDefaults
    private var preferences: Preferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) {
                defaults.set(data, forKey: Self.preferencesKey)
            }
        }
    }

    private(set) var catalog: [OpenRouterModel] = []
    private var catalogByID: [String: OpenRouterModel] = [:]
    private(set) var isLoadingCatalog = false
    private(set) var catalogError: String?
    private var samples: [String: ModelReadings] = [:]
    private var refreshErrors: [String: String] = [:]
    private var refreshRequested = false
    private(set) var isRefreshing = false
    private(set) var updatedAt: Date?
    private var history: ThroughputHistory
    private let historyURL: URL?
    @ObservationIgnored private var readingLocalSources: Set<LocalRequestThroughput.Source> = []
    @ObservationIgnored private var lastLocalRefresh: [LocalRequestThroughput.Source: ContinuousClock.Instant] = [:]
    private(set) var localActivity: [LocalRequestThroughput.Source: LocalActivity] = [:]

    init(defaults: UserDefaults = .standard, historyURL: URL? = ThroughputHistory.defaultURL,
         codexReader: CodexThroughputReader = .init(), claudeReader: ClaudeThroughputReader = .init()) {
        self.defaults = defaults
        self.historyURL = historyURL
        self.codexReader = codexReader
        self.claudeReader = claudeReader
        history = ThroughputHistory.load(from: historyURL)
        let saved = defaults.data(forKey: Self.preferencesKey)
        preferences = saved.flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
    }

    var watched: [WatchedModel] { preferences.watched }
    var providerGroups: [ProviderGroup] { ProviderGroup.grouped(watched) }

    var rules: [BadgeRule] {
        get { preferences.rules }
        set { preferences.rules = newValue }
    }

    var headlineID: String {
        get { preferences.headlineID ?? watched.first?.id ?? "" }
        set {
            var updated = preferences
            updated.headlineID = newValue
            updated.localHeadline = nil
            preferences = updated
        }
    }

    var localHeadline: LocalRequestThroughput.Pin? {
        get { preferences.localHeadline }
        set { preferences.localHeadline = newValue }
    }

    var headline: WatchedModel? { watched.first { $0.id == headlineID } }

    func isHeadline(_ watch: WatchedModel) -> Bool {
        localHeadline == nil && watch.id == headlineID
    }

    func localReading(for pin: LocalRequestThroughput.Pin) -> LocalRequestThroughput.Reading? {
        localActivity[pin.source]?.snapshot?.models.first { $0.id == pin.modelID }?
            .readings.first { $0.tier == pin.tier }
    }

    func localModelName(for model: String) -> String {
        let isClaude = model.hasPrefix("claude-")
        let slug = isClaude
            ? model.replacingOccurrences(of: #"-(\d+)-(\d)(?:-\d{8})?$"#, with: "-$1.$2", options: .regularExpression)
            : model
        let id = (isClaude ? "anthropic/" : "openai/") + slug
        if let known = catalogByID[id] ?? OpenRouterModel.defaults.first(where: { $0.id == id }) {
            return known.shortName
        }

        if isClaude {
            return slug.replacingOccurrences(of: "-", with: " ").capitalized
        }
        guard slug.hasPrefix("gpt-") else { return model }
        let undated = slug.replacingOccurrences(of: #"-(?:\d{8}|\d{4}-\d{2}-\d{2})$"#, with: "",
                                                 options: .regularExpression)
        let parts = undated.split(separator: "-", maxSplits: 2)
        guard parts.count >= 2 else { return model }
        let name = "GPT-\(parts[1])"
        guard parts.count == 3 else { return name }
        return "\(name) \(parts[2].replacingOccurrences(of: "-", with: " ").capitalized)"
    }

    func refreshLocal(_ source: LocalRequestThroughput.Source, minimumInterval: Duration = .zero) async {
        let startedAt = ContinuousClock.now
        if let previous = lastLocalRefresh[source], previous.duration(to: startedAt) < minimumInterval { return }
        guard readingLocalSources.insert(source).inserted else { return }
        defer { readingLocalSources.remove(source) }
        let snapshot = switch source {
        case .codex: await codexReader.snapshot()
        case .claudeCode: await claudeReader.snapshot()
        }
        guard !Task.isCancelled else { return }
        lastLocalRefresh[source] = startedAt
        localActivity[source] = snapshot.map(LocalActivity.available) ?? .unavailable
    }

    func pollVisibleLocal(_ source: LocalRequestThroughput.Source) async {
        let interval = Duration.seconds(30)
        while !Task.isCancelled {
            await refreshLocal(source, minimumInterval: interval)
            do {
                try await Task.sleep(for: localRefreshDelay(for: source, interval: interval))
            } catch {
                return
            }
        }
    }

    func pollPinnedLocal() async {
        let interval = Duration.seconds(60)
        while !Task.isCancelled {
            var delay = interval
            if let source = localHeadline?.source {
                await refreshLocal(source, minimumInterval: interval)
                delay = localRefreshDelay(for: source, interval: interval)
            }
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
        }
    }

    private func localRefreshDelay(for source: LocalRequestThroughput.Source, interval: Duration) -> Duration {
        guard let previous = lastLocalRefresh[source] else { return interval }
        return max(.seconds(1), interval - previous.duration(to: .now))
    }

    /// Readings that badge rules evaluate, keyed by watch ID. Stale rows are excluded.
    var ruleReadings: [String: EndpointReading] {
        watched.reduce(into: [String: EndpointReading]()) { result, item in
            if refreshErrors[item.model.id] == nil { result[item.id] = reading(for: item) }
        }
    }

    nonisolated static let maxBadges = 3

    var matchingRules: [BadgeRule] {
        let readings = ruleReadings
        return Array(rules.lazy.filter { $0.matches(readings) }.prefix(Self.maxBadges))
    }

    var hasLoaded: Bool { updatedAt != nil || !refreshErrors.isEmpty }

    var failedCount: Int { watched.count { refreshError(for: $0) != nil } }

    func reading(for watch: WatchedModel) -> EndpointReading? {
        samples[watch.model.id]?.reading(for: watch)
    }

    /// Locally recorded TPS for the endpoint this row currently shows.
    func history(for watch: WatchedModel) -> [ThroughputPoint] {
        guard let endpointID = watch.endpoint?.id ?? reading(for: watch)?.endpoint.id else { return [] }
        let cutoff = Date.now.addingTimeInterval(-ThroughputHistory.window)
        return history.points(modelID: watch.model.id, endpointID: endpointID).filter { $0.date >= cutoff }
    }

    func refreshError(for watch: WatchedModel) -> String? {
        if let error = refreshErrors[watch.model.id] { return error }
        guard let sample = samples[watch.model.id] else { return nil }
        if !sample.tpsAvailable { return "Couldn’t refresh TPS." }
        if !sample.uptimeAvailable { return "Couldn’t refresh uptime." }
        return nil
    }

    func isStale(_ watch: WatchedModel) -> Bool {
        refreshErrors[watch.model.id] != nil
    }

    func contains(_ model: OpenRouterModel, endpoint: ProviderEndpoint?, except watchID: String?) -> Bool {
        watched.contains { $0.id != watchID && $0.model.id == model.id && $0.endpoint?.id == endpoint?.id }
    }

    func save(_ model: OpenRouterModel, endpoint: ProviderEndpoint?, editing watchID: String?) {
        guard !contains(model, endpoint: endpoint, except: watchID) else { return }
        if let watchID, let index = watched.firstIndex(where: { $0.id == watchID }) {
            preferences.watched[index].endpoint = endpoint
        } else {
            let watch = WatchedModel(id: UUID().uuidString, model: model, endpoint: endpoint)
            var updated = preferences
            updated.watched.append(watch)
            if updated.headlineID == nil { updated.headlineID = watch.id }
            preferences = updated
        }
        Task { await refresh() }
    }

    func unwatch(_ id: String) {
        var updated = preferences
        updated.watched.removeAll { $0.id == id }
        if updated.headlineID == id { updated.headlineID = updated.watched.first?.id }
        for rule in updated.rules.indices {
            for condition in updated.rules[rule].conditions.indices {
                if updated.rules[rule].conditions[condition].modelID == id {
                    updated.rules[rule].conditions[condition].modelID = ""
                }
                if updated.rules[rule].conditions[condition].otherModelID == id {
                    updated.rules[rule].conditions[condition].otherModelID = ""
                }
            }
        }
        preferences = updated
    }

    func moveGroup(_ id: String, by offset: Int) {
        var groups = providerGroups
        guard let index = groups.firstIndex(where: { $0.id == id }),
              groups.indices.contains(index + offset) else { return }
        groups.swapAt(index, index + offset)
        preferences.watched = groups.flatMap(\.models)
    }

    func moveWatch(_ id: String, by offset: Int) {
        var groups = providerGroups
        guard let group = groups.firstIndex(where: { $0.models.contains { $0.id == id } }),
              let index = groups[group].models.firstIndex(where: { $0.id == id }),
              groups[group].models.indices.contains(index + offset) else { return }
        groups[group].models.swapAt(index, index + offset)
        preferences.watched = groups.flatMap(\.models)
    }

    func moveWatches(inGroup id: String, fromOffsets source: IndexSet, toOffset destination: Int) {
        var groups = providerGroups
        guard let group = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[group].models.move(fromOffsets: source, toOffset: destination)
        preferences.watched = groups.flatMap(\.models)
    }

    func endpointChoices(for model: OpenRouterModel) async throws -> [EndpointReading] {
        if let sample = samples[model.id], sample.tpsAvailable, sample.uptimeAvailable {
            return sample.endpoints
        }
        return try await client.readings(for: catalogByID[model.id] ?? model).endpoints
    }

    func loadCatalog() async {
        guard !isLoadingCatalog else { return }
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            let models = try await client.models()
            catalog = models.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            catalogByID = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            catalogError = nil
        } catch {
            catalogError = error.localizedDescription
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            refreshRequested = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshRequested = false
            await fetchReadings()
        } while refreshRequested && !Task.isCancelled
    }

    private func fetchReadings() async {
        var seen: Set<String> = []
        let models = watched.map(\.model).filter { seen.insert($0.id).inserted }
            .map { catalogByID[$0.id] ?? $0 }
        let client = self.client
        var results: [String: Sample] = [:]
        for offset in stride(from: 0, to: models.count, by: 4) {
            await withTaskGroup(of: ModelSample.self) { group in
                for model in models.dropFirst(offset).prefix(4) {
                    group.addTask {
                        do {
                            let reading = try await client.readings(for: model)
                            return ModelSample(modelID: model.id, sample: .reading(reading))
                        } catch {
                            return ModelSample(modelID: model.id, sample: .failed(error.localizedDescription))
                        }
                    }
                }
                for await result in group {
                    results[result.modelID] = result.sample
                }
            }
        }
        guard !Task.isCancelled else { return }
        let stillWatched = Set(watched.map(\.model.id))
        samples = samples.filter { stillWatched.contains($0.key) }
        refreshErrors = refreshErrors.filter { stillWatched.contains($0.key) }
        var refreshed = false
        var recorded = false
        let now = Date.now
        for (id, result) in results where stillWatched.contains(id) {
            switch result {
            case .reading(let reading):
                samples[id] = reading
                refreshErrors[id] = nil
                refreshed = true
                if history.record(modelID: id, readings: reading.endpoints, at: now) { recorded = true }
            case .failed(let error):
                refreshErrors[id] = error
            }
        }
        if refreshed { updatedAt = now }
        if recorded {
            history.prune(keepingModels: stillWatched, now: now)
            history.save(to: historyURL)
        }
    }

    func poll() async {
        while !Task.isCancelled {
            await refresh()
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }
        }
    }
}

extension Double {
    var tpsText: String {
        formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Truncates to one decimal so 99.96% reads as 99.9%, never as a misleading 100%.
    var uptimeText: String {
        ((self * 10).rounded(.down) / 1000).formatted(.percent.precision(.fractionLength(0...1)))
    }
}
