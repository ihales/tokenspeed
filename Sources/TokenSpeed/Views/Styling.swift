import AppKit
import SwiftUI

struct ProviderHeading: View {
    let title: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }
}

extension BadgeColor {
    var color: Color { Color(nsColor: appKitColor) }
}

/// Uptime is only colored when it needs attention, so healthy rows stay quiet.
enum UptimeHealth {
    case healthy, degraded, poor

    init(_ uptime: Double) {
        switch uptime {
        case 99...: self = .healthy
        case 95..<99: self = .degraded
        default: self = .poor
        }
    }

    var style: AnyShapeStyle {
        switch self {
        case .healthy: AnyShapeStyle(.secondary)
        case .degraded: AnyShapeStyle(Color.orange)
        case .poor: AnyShapeStyle(Color.red)
        }
    }
}

struct BadgeChip: View {
    let rule: BadgeRule

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(rule.color.color).frame(width: 7, height: 7)
            Text(rule.name.isEmpty ? rule.color.title : rule.name)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(rule.color.color.opacity(0.14), in: Capsule())
        .help(rule.label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rule.label)
    }
}

struct ColorSwatchPicker: View {
    @Binding var selection: BadgeColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(BadgeColor.allCases) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 18, height: 18)
                        .overlay {
                            if selection == color {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(2)
                        .overlay(Circle().strokeBorder(selection == color ? color.color : .clear, lineWidth: 1.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(color.title)
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
    }
}

extension BadgeCondition {
    /// A short, readable description such as "Fable TPS > 20" or "Fable TPS > 2× Opus".
    func summary(watched: [WatchedModel]) -> String {
        func name(_ id: String) -> String {
            watched.first { $0.id == id }?.model.shortName ?? "No model"
        }
        let metric = (self.metric ?? .tps).rawValue
        let target: String
        if comparesWithModel {
            target = "\(multiplier.isEmpty ? "?" : multiplier)× \(otherModelID.isEmpty ? "?" : name(otherModelID))"
        } else {
            let unit = self.metric == .uptime ? "%" : ""
            target = "\(threshold.isEmpty ? "?" : threshold)\(unit)"
        }
        return "\(modelID.isEmpty ? "No model" : name(modelID)) \(metric) \(comparison.rawValue) \(target)"
    }
}

extension BadgeRule {
    var displayName: String { name.isEmpty ? "Untitled Rule" : name }

    func summary(watched: [WatchedModel]) -> String {
        guard !conditions.isEmpty else { return "No conditions" }
        return conditions.map { $0.summary(watched: watched) }
            .joined(separator: match == .any ? " or " : " and ")
    }
}
