import SwiftUI

struct RuleSettingsView: View {
    @Bindable var store: MonitorStore
    @ViewState private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 230)
            Divider()
            if let selection, let rule = $store.rules.first(where: { $0.wrappedValue.id == selection }) {
                RuleEditor(rule: rule, store: store)
                    .id(selection)
            } else {
                ContentUnavailableView {
                    Label(store.rules.isEmpty ? "No Badge Rules" : "No Rule Selected", systemImage: "circle.badge.checkmark")
                } description: {
                    Text("Badges are colored dots next to the menu bar reading. Add a rule to show one when a model gets fast, slow, or unreliable.")
                } actions: {
                    Button("Add Rule", action: addRule)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 680, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .onAppear { selection = selection ?? store.rules.first?.id }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    ForEach(store.rules) { rule in
                        RuleRow(rule: rule, status: status(of: rule), watched: store.watched)
                            .tag(rule.id)
                    }
                    .onMove { source, destination in
                        var rules = store.rules
                        rules.move(fromOffsets: source, toOffset: destination)
                        store.rules = rules
                    }
                } header: {
                    if !store.rules.isEmpty {
                        Text("Checked top to bottom")
                    }
                }
            }
            .listStyle(.sidebar)
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, let index = store.rules.firstIndex(where: { $0.id == id }) {
                    Button(store.rules[index].isEnabled ? "Disable" : "Enable") {
                        store.rules[index].isEnabled.toggle()
                    }
                    Button("Duplicate") { duplicate(at: index) }
                    Divider()
                    Button("Move Up") { move(id, by: -1) }.disabled(index == 0)
                    Button("Move Down") { move(id, by: 1) }.disabled(index == store.rules.count - 1)
                    Divider()
                    Button("Delete", role: .destructive) { delete(id) }
                }
            }
            .onDeleteCommand { if let selection { delete(selection) } }

            Divider()
            HStack(spacing: 0) {
                barButton("Add Rule", icon: "plus", action: addRule)
                Divider().frame(height: 16)
                barButton("Delete Rule", icon: "minus") { if let selection { delete(selection) } }
                    .disabled(selection == nil)
                Spacer()
            }
            .frame(height: 28)
            .background(.bar)
        }
    }

    private func status(of rule: BadgeRule) -> RuleStatus {
        RuleStatus(rule: rule, readings: store.ruleReadings, shown: store.matchingRules.map(\.id))
    }

    private func barButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
        .help(title)
    }

    private func addRule() {
        let rule = BadgeRule(conditions: [.init(modelID: store.headlineID)])
        store.rules.append(rule)
        selection = rule.id
    }

    private func duplicate(at index: Int) {
        var copy = store.rules[index]
        copy.id = UUID()
        copy.conditions = copy.conditions.map { condition in
            var condition = condition
            condition.id = UUID()
            return condition
        }
        copy.name = copy.name.isEmpty ? "" : "\(copy.name) copy"
        store.rules.insert(copy, at: index + 1)
        selection = copy.id
    }

    private func delete(_ id: UUID) {
        guard let index = store.rules.firstIndex(where: { $0.id == id }) else { return }
        store.rules.remove(at: index)
        if selection == id {
            selection = store.rules.dropFirst(index).first?.id ?? store.rules.last?.id
        }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = store.rules.firstIndex(where: { $0.id == id }),
              store.rules.indices.contains(index + offset) else { return }
        store.rules.swapAt(index, index + offset)
    }
}

/// Where a rule stands right now, for the sidebar and the editor's status row.
private enum RuleStatus {
    case disabled, incomplete, notMatching, shown, hidden

    init(rule: BadgeRule, readings: [String: EndpointReading], shown: [UUID]) {
        if !rule.isEnabled {
            self = .disabled
        } else if rule.conditions.isEmpty || rule.conditions.contains(where: { ConditionStatus($0, readings: readings).isIncomplete }) {
            self = .incomplete
        } else if !rule.matches(readings) {
            self = .notMatching
        } else {
            self = shown.contains(rule.id) ? .shown : .hidden
        }
    }

    var title: String {
        switch self {
        case .disabled: "Off"
        case .incomplete: "Needs attention"
        case .notMatching: "Not matching right now"
        case .shown: "Matching — shown in the menu bar"
        case .hidden: "Matching, but hidden: only the first \(MonitorStore.maxBadges) matches are shown"
        }
    }

    var icon: String {
        switch self {
        case .disabled: "pause.circle"
        case .incomplete: "exclamationmark.triangle.fill"
        case .notMatching: "circle.dashed"
        case .shown: "checkmark.circle.fill"
        case .hidden: "eye.slash"
        }
    }

    var tint: AnyShapeStyle {
        switch self {
        case .incomplete: AnyShapeStyle(Color.orange)
        case .shown: AnyShapeStyle(Color.green)
        default: AnyShapeStyle(.secondary)
        }
    }
}

private struct RuleRow: View {
    let rule: BadgeRule
    let status: RuleStatus
    let watched: [WatchedModel]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(rule.color.color)
                .frame(width: 10, height: 10)
                .opacity(rule.isEnabled ? 1 : 0.35)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName)
                    .lineLimit(1)
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                Text(rule.summary(watched: watched))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: status.icon)
                .font(.caption)
                .foregroundStyle(status.tint)
                .padding(.top, 3)
                .help(status.title)
                .accessibilityLabel(status.title)
        }
        .padding(.vertical, 3)
    }
}

private struct RuleEditor: View {
    @Binding var rule: BadgeRule
    let store: MonitorStore

    var body: some View {
        let groups = store.providerGroups
        let readings = store.ruleReadings
        let status = RuleStatus(rule: rule, readings: readings, shown: store.matchingRules.map(\.id))

        Form {
            Section {
                TextField("Name", text: $rule.name, prompt: Text("Untitled Rule"))
                LabeledContent("Color") {
                    ColorSwatchPicker(selection: $rule.color)
                }
                Toggle("Enabled", isOn: $rule.isEnabled)
                LabeledContent("Status") {
                    Label(status.title, systemImage: status.icon)
                        .foregroundStyle(status.tint)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                Picker("Show the badge when", selection: $rule.match) {
                    Text("Any condition is true").tag(BadgeRule.Match.any)
                    Text("All conditions are true").tag(BadgeRule.Match.all)
                }
                ForEach($rule.conditions) { condition in
                    ConditionEditor(condition: condition, groups: groups, readings: readings,
                                    canRemove: rule.conditions.count > 1) {
                        let id = condition.wrappedValue.id
                        rule.conditions.removeAll { $0.id == id }
                    }
                }
                Button {
                    rule.conditions.append(.init(modelID: groups.first?.models.first?.id ?? ""))
                } label: {
                    Label("Add Condition", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Conditions")
            } footer: {
                Text("Rules are checked top to bottom and the menu bar shows up to \(MonitorStore.maxBadges) matching badges. Conditions use each row’s displayed reading; stale readings never match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum ConditionStatus {
    case incomplete(String)
    case noData(String)
    case evaluated(Bool, String)

    init(_ condition: BadgeCondition, readings: [String: EndpointReading]) {
        if condition.modelID.isEmpty {
            self = .incomplete("Choose a model")
            return
        }
        let unit = condition.metric == .uptime ? "%" : " TPS"
        let format: (Double) -> String = \.tpsText
        if condition.comparesWithModel {
            guard let factor = condition.number(condition.multiplier) else {
                self = .incomplete("Enter a multiplier, like 2 or 1.5")
                return
            }
            guard !condition.otherModelID.isEmpty else {
                self = .incomplete("Choose a model to compare with")
                return
            }
            guard let lhs = condition.value(readings[condition.modelID]),
                  let other = condition.value(readings[condition.otherModelID]) else {
                self = .noData("Waiting for current readings")
                return
            }
            let rhs = factor * other
            self = .evaluated(condition.comparison.compare(lhs, rhs),
                              "Now \(format(lhs))\(unit) vs \(format(rhs))\(unit) (\(condition.multiplier)× \(format(other)))")
        } else {
            guard let rhs = condition.number(condition.threshold) else {
                self = .incomplete("Enter a number")
                return
            }
            guard let lhs = condition.value(readings[condition.modelID]) else {
                self = .noData("Waiting for a current reading")
                return
            }
            self = .evaluated(condition.comparison.compare(lhs, rhs), "Now \(format(lhs))\(unit)")
        }
    }

    var isIncomplete: Bool {
        if case .incomplete = self { true } else { false }
    }
}

private struct ConditionEditor: View {
    @Binding var condition: BadgeCondition
    let groups: [ProviderGroup]
    let readings: [String: EndpointReading]
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                modelPicker("Model", selection: $condition.modelID)
                Picker("Metric", selection: Binding(
                    get: { condition.metric ?? .tps },
                    set: { condition.metric = $0 }
                )) {
                    ForEach(BadgeCondition.Metric.allCases, id: \.self) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Metric")
                .fixedSize()
                Spacer(minLength: 0)
                if canRemove {
                    Button(action: remove) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove Condition")
                    .accessibilityLabel("Remove condition")
                }
            }

            HStack(spacing: 6) {
                Picker("Comparison", selection: $condition.comparison) {
                    ForEach(BadgeCondition.Comparison.allCases, id: \.self) { operation in
                        Text(operation.rawValue).tag(operation)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Comparison")
                .fixedSize()
                if condition.comparesWithModel {
                    TextField("Multiplier", text: $condition.multiplier, prompt: Text("2"))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 48)
                        .accessibilityLabel("Multiplier")
                    Text("×").foregroundStyle(.secondary)
                    modelPicker("Other model", selection: $condition.otherModelID)
                } else {
                    TextField("Threshold", text: $condition.threshold, prompt: Text("20"))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        .accessibilityLabel("Threshold")
                    Text(condition.metric == .uptime ? "%" : "TPS").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Picker("Compare with", selection: $condition.comparesWithModel) {
                    Text("Fixed value").tag(false)
                    Text("Another model").tag(true)
                }
                .labelsHidden()
                .accessibilityLabel("Compare with")
                .fixedSize()
            }
            .textFieldStyle(.roundedBorder)

            statusLine
        }
        .labelsHidden()
        .padding(.vertical, 4)
    }

    @ViewBuilder private var statusLine: some View {
        switch ConditionStatus(condition, readings: readings) {
        case .incomplete(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        case .noData(let message):
            Label(message, systemImage: "clock")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .evaluated(let isTrue, let detail):
            Label {
                Text("\(detail) · \(isTrue ? "true" : "false")")
            } icon: {
                Image(systemName: isTrue ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(isTrue ? Color.green : Color.secondary)
            }
            .foregroundStyle(.secondary)
            .font(.caption)
            .monospacedDigit()
        }
    }

    private func modelPicker(_ title: String, selection: Binding<String>) -> some View {
        let watchedSelection = Binding(
            get: { groups.contains { $0.models.contains { $0.id == selection.wrappedValue } } ? selection.wrappedValue : "" },
            set: { selection.wrappedValue = $0 }
        )
        return Picker(title, selection: watchedSelection) {
            Text("Choose a model…").tag("")
            ForEach(groups) { group in
                Section(group.isAutomatic ? "Automatic" : group.title) {
                    ForEach(group.models) { watch in
                        Text(watch.title).tag(watch.id)
                    }
                }
            }
        }
        .labelsHidden()
        .accessibilityLabel(title)
        .fixedSize()
    }
}
