import SwiftUI

struct EndpointEditor: View {
    struct Request: Identifiable {
        let id = UUID()
        let model: OpenRouterModel
        let watch: WatchedModel?
    }

    @Environment(\.dismiss) private var dismiss
    @ViewState private var selection: String?
    @ViewState private var endpoints: [EndpointReading] = []
    @ViewState private var isLoading = false
    @ViewState private var error: String?

    let store: MonitorStore
    let request: Request
    let onBack: (() -> Void)?

    init(store: MonitorStore, request: Request, onBack: (() -> Void)? = nil) {
        self.store = store
        self.request = request
        self.onBack = onBack
        _selection = ViewState(initialValue: request.watch?.endpoint?.id ?? "")
        _endpoints = ViewState(initialValue: request.watch?.endpoint.map { [EndpointReading(endpoint: $0)] } ?? [])
    }

    private var selectedEndpoint: ProviderEndpoint? { endpoints.first { $0.endpoint.id == selection }?.endpoint }
    private var isDuplicate: Bool {
        store.contains(request.model, endpoint: selectedEndpoint, except: request.watch?.id)
    }

    /// Fastest first; endpoints without a reading go last, by name.
    private var sortedEndpoints: [EndpointReading] {
        endpoints.sorted { lhs, rhs in
            switch (lhs.tps, rhs.tps) {
            case let (l?, r?): l > r
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.endpoint.title.localizedStandardCompare(rhs.endpoint.title) == .orderedAscending
            }
        }
    }

    private var automaticPick: EndpointReading? {
        ModelReadings(endpoints: endpoints, tpsAvailable: true, uptimeAvailable: true)
            .reading(for: WatchedModel(id: "", model: request.model, endpoint: nil))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(request.model.shortName).font(.headline)
                Text("Choose which provider endpoint to watch. Endpoints are sorted by current speed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            List(selection: $selection) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.yellow)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic")
                        Text(automaticPick.map { "Fastest right now: \($0.endpoint.title)" }
                             ?? "Fastest endpoint in the most recent reported window")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    watchedTag(endpoint: nil)
                }
                .padding(.vertical, 3)
                .tag("")

                Section("Endpoints") {
                    ForEach(sortedEndpoints, id: \.endpoint.id) { reading in
                        endpointRow(reading)
                            .tag(reading.endpoint.id)
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .overlay {
                if isLoading && endpoints.count <= 1 {
                    ProgressView("Loading endpoints…").controlSize(.small)
                }
            }
            .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { _ in
                if canSave { save() }
            }

            HStack(spacing: 8) {
                if let onBack {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                    Button("Retry") { Task { await loadEndpoints() } }
                        .controlSize(.small)
                } else if isDuplicate {
                    Text("This endpoint is already on your watchlist.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(request.watch == nil ? "Add to Watchlist" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 500, height: 500)
        .task { await loadEndpoints() }
    }

    private var canSave: Bool {
        !isDuplicate && selection != nil && (selection == "" || selectedEndpoint != nil)
    }

    private func save() {
        store.save(request.model, endpoint: selectedEndpoint, editing: request.watch?.id)
        dismiss()
    }

    private func endpointRow(_ reading: EndpointReading) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.endpoint.providerName).lineLimit(1)
                Text(reading.endpoint.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            watchedTag(endpoint: reading.endpoint)
            Text(reading.tps.map { "\($0.tpsText) tok/s" } ?? "–")
                .frame(width: 84, alignment: .trailing)
            Text(reading.uptime?.uptimeText ?? "–")
                .foregroundStyle(reading.uptime.map { UptimeHealth($0).style } ?? AnyShapeStyle(.secondary))
                .frame(width: 52, alignment: .trailing)
                .help("24-hour uptime")
        }
        .monospacedDigit()
        .padding(.vertical, 3)
        .help(reading.endpoint.id)
    }

    @ViewBuilder
    private func watchedTag(endpoint: ProviderEndpoint?) -> some View {
        if store.contains(request.model, endpoint: endpoint, except: request.watch?.id) {
            Text("Watched")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
    }

    private func loadEndpoints() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var options = try await store.endpointChoices(for: request.model)
            if let current = request.watch?.endpoint, !options.contains(where: { $0.endpoint.id == current.id }) {
                options.append(EndpointReading(endpoint: current))
            }
            endpoints = options
            error = options.isEmpty ? "OpenRouter returned no provider endpoints." : nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
