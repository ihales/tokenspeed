import SwiftUI

// Use the property wrapper on Swift toolchains that lack the SwiftUI macros plugin.
typealias ViewState<Value> = SwiftUI.State<Value>

struct ModelSettingsView: View {
    @Bindable var store: MonitorStore
    @ViewState private var selection: String?
    @ViewState private var edit: EndpointEditor.Request?
    @ViewState private var isAdding = false

    private var selectedWatch: WatchedModel? { store.watched.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Watchlist").font(.headline)
                Text("Pin a model to show its speed in the menu bar. Drag rows to reorder them within a provider.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                if store.watched.isEmpty {
                    ContentUnavailableView {
                        Label("No Models Yet", systemImage: "gauge.with.dots.needle.33percent")
                    } description: {
                        Text("Add an OpenRouter model to start tracking its throughput.")
                    } actions: {
                        Button("Add Model…") { isAdding = true }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                } else {
                    watchlist
                }
                Divider()
                bottomBar
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))
        }
        .padding(20)
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .task {
            if store.catalog.isEmpty { await store.loadCatalog() }
        }
        .sheet(item: $edit) { request in
            EndpointEditor(store: store, request: request)
        }
        .sheet(isPresented: $isAdding) {
            AddModelSheet(store: store)
        }
    }

    private var watchlist: some View {
        let groups = store.providerGroups
        return List(selection: $selection) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                Section {
                    ForEach(group.models) { watch in
                        WatchlistRow(store: store, watch: watch)
                            .tag(watch.id)
                    }
                    .onMove { source, destination in
                        store.moveWatches(inGroup: group.id, fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    HStack(spacing: 4) {
                        if group.isAutomatic {
                            Image(systemName: "bolt.fill").imageScale(.small)
                        }
                        Text(group.isAutomatic ? "Automatic · Fastest Endpoint" : group.title)
                        Spacer()
                        if groups.count > 1 {
                            groupMoveButton(group, up: true, disabled: index == 0)
                            groupMoveButton(group, up: false, disabled: index == groups.count - 1)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let watch = store.watched.first(where: { $0.id == id }) {
                menuItems(for: watch)
            }
        } primaryAction: { ids in
            if let id = ids.first, let watch = store.watched.first(where: { $0.id == id }) {
                edit = .init(model: watch.model, watch: watch)
            }
        }
        .onDeleteCommand(perform: removeSelection)
    }

    @ViewBuilder
    private func menuItems(for watch: WatchedModel) -> some View {
        Button("Show in Menu Bar", systemImage: "pin") { store.headlineID = watch.id }
            .disabled(watch.id == store.headlineID)
        Button("Change Endpoint…", systemImage: "slider.horizontal.3") {
            edit = .init(model: watch.model, watch: watch)
        }
        if let url = watch.model.providersURL {
            Button("Open on OpenRouter", systemImage: "safari") { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button("Move Provider Up") { store.moveGroup(watch.providerID, by: -1) }
        Button("Move Provider Down") { store.moveGroup(watch.providerID, by: 1) }
        Divider()
        Button("Remove from Watchlist", systemImage: "trash", role: .destructive) { store.unwatch(watch.id) }
    }

    private func groupMoveButton(_ group: ProviderGroup, up: Bool, disabled: Bool) -> some View {
        let title = "Move \(group.isAutomatic ? "Automatic" : group.title) \(up ? "up" : "down")"
        return Button {
            store.moveGroup(group.id, by: up ? -1 : 1)
        } label: {
            Image(systemName: up ? "chevron.up" : "chevron.down")
                .imageScale(.small)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(title)
        .accessibilityLabel(title)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barButton("Add Model…", icon: "plus") { isAdding = true }
            Divider().frame(height: 16)
            barButton("Remove Selected Model", icon: "minus", action: removeSelection)
                .disabled(selectedWatch == nil)
            Divider().frame(height: 16)
            Button("Change Endpoint…") {
                if let watch = selectedWatch { edit = .init(model: watch.model, watch: watch) }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .disabled(selectedWatch == nil)
            Spacer()
            Text("\(store.watched.count) watched")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.trailing, 10)
        }
        .frame(height: 28)
        .background(.bar)
    }

    private func barButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }

    private func removeSelection() {
        guard let id = selection else { return }
        let ordered = store.watched.map(\.id)
        let next = ordered.firstIndex(of: id).flatMap { index in
            ordered.indices.contains(index + 1) ? ordered[index + 1] : (index > 0 ? ordered[index - 1] : nil)
        }
        store.unwatch(id)
        selection = next
    }
}

private struct WatchlistRow: View {
    let store: MonitorStore
    let watch: WatchedModel

    var body: some View {
        let isPinned = watch.id == store.headlineID
        let reading = store.reading(for: watch)
        HStack(spacing: 10) {
            Button {
                store.headlineID = watch.id
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(isPinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(isPinned ? "Shown in the menu bar" : "Show in Menu Bar")
            .accessibilityLabel(isPinned ? "\(watch.model.shortName) is shown in the menu bar"
                                : "Show \(watch.model.shortName) in menu bar")

            VStack(alignment: .leading, spacing: 2) {
                Text(watch.model.shortName).lineLimit(1)
                Text(watch.endpoint?.detail ?? reading.map { "Currently \($0.endpoint.title)" } ?? "Fastest available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let tps = reading?.tps {
                Text("\(tps.tpsText) tok/s")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Two steps: pick a model from the OpenRouter catalog, then pick its endpoint.
struct AddModelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: MonitorStore
    @ViewState private var query = ""
    @ViewState private var selection: OpenRouterModel.ID?
    @ViewState private var chosen: OpenRouterModel?
    @FocusState private var searchFocused: Bool

    private var results: [OpenRouterModel] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return store.catalog }
        return store.catalog.filter {
            $0.name.localizedStandardContains(search) || $0.id.localizedStandardContains(search)
        }
    }

    var body: some View {
        if let chosen {
            EndpointEditor(store: store, request: .init(model: chosen, watch: nil)) {
                self.chosen = nil
            }
        } else {
            catalogPicker
        }
    }

    private var catalogPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add a Model").font(.headline)
                Text("Choose an OpenRouter model, then pick which endpoint to watch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            TextField("Search by name or ID", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityLabel("Search OpenRouter models")
                .onSubmit {
                    if results.count == 1 { chosen = results.first }
                }

            Group {
                if store.isLoadingCatalog && store.catalog.isEmpty {
                    ProgressView("Loading OpenRouter models…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = store.catalogError, store.catalog.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn’t Load Models", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await store.loadCatalog() } }
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results, selection: $selection) { model in
                        let watchCount = store.watched.count { $0.model.id == model.id }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.shortName).lineLimit(1)
                                Text(model.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if watchCount > 0 {
                                Text(watchCount == 1 ? "Watching" : "Watching \(watchCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                    .contextMenu(forSelectionType: OpenRouterModel.ID.self) { _ in } primaryAction: { ids in
                        chosen = ids.first.flatMap { id in store.catalog.first { $0.id == id } }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                if !store.catalog.isEmpty {
                    Text("\(results.count) of \(store.catalog.count) models")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Next") {
                    chosen = store.catalog.first { $0.id == selection }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
        }
        .padding(20)
        .frame(width: 500, height: 500)
        .task {
            searchFocused = true
            if store.catalog.isEmpty { await store.loadCatalog() }
        }
    }
}
