import Foundation

enum BadgeColor: String, CaseIterable, Codable, Identifiable {
    case blue, green, orange, red, purple
    var id: Self { self }
}

struct BadgeRule: Identifiable, Codable {
    enum Match: String, CaseIterable, Codable {
        case any, all
    }

    var id = UUID()
    var name = ""
    var isEnabled = true
    var color: BadgeColor = .blue
    var match: Match = .any
    var conditions: [BadgeCondition]

    var label: String {
        name.isEmpty ? "\(color.title) badge" : "\(color.title) badge, \(name)"
    }

    func matches(_ readings: [String: EndpointReading]) -> Bool {
        guard isEnabled, !conditions.isEmpty else { return false }
        switch match {
        case .any: return conditions.contains { $0.matches(readings) }
        case .all: return conditions.allSatisfy { $0.matches(readings) }
        }
    }
}

struct BadgeCondition: Identifiable, Codable {
    enum Metric: String, CaseIterable, Codable {
        case tps = "TPS"
        case uptime = "Uptime"
    }

    enum Comparison: String, CaseIterable, Codable {
        case greaterThan = ">"
        case atLeast = "≥"
        case lessThan = "<"
        case atMost = "≤"

        func compare(_ lhs: Double, _ rhs: Double) -> Bool {
            switch self {
            case .greaterThan: lhs > rhs
            case .atLeast: lhs >= rhs
            case .lessThan: lhs < rhs
            case .atMost: lhs <= rhs
            }
        }
    }

    var id = UUID()
    var modelID: String
    var metric: Metric?
    var comparison: Comparison = .greaterThan
    var threshold = "20"
    var comparesWithModel = false
    var otherModelID = ""
    var multiplier = "2"

    func matches(_ readings: [String: EndpointReading]) -> Bool {
        guard let lhs = value(readings[modelID]) else { return false }
        if comparesWithModel {
            guard let factor = number(multiplier),
                  let other = value(readings[otherModelID]),
                  (factor * other).isFinite else { return false }
            return comparison.compare(lhs, factor * other)
        }
        guard let rhs = number(threshold) else { return false }
        return comparison.compare(lhs, rhs)
    }

    func value(_ reading: EndpointReading?) -> Double? {
        switch metric ?? .tps {
        case .tps: reading?.tps
        case .uptime: reading?.uptime
        }
    }

    func number(_ text: String) -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(text) ?? (try? Double(text, format: .number, lenient: false)),
              value.isFinite, value >= 0 else { return nil }
        return value
    }
}

extension BadgeColor {
    var title: String { rawValue.capitalized }
}
