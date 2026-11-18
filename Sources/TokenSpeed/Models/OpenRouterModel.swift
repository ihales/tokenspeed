import Foundation

struct OpenRouterModel: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let canonicalSlug: String?

    var shortName: String {
        guard let colon = name.range(of: ": ") else { return name }
        return String(name[colon.upperBound...])
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case canonicalSlug = "canonical_slug"
    }
}

extension OpenRouterModel {
    static let defaults: [Self] = [
        .init(id: "anthropic/claude-fable-5.2", name: "Anthropic: Claude Fable 5.2",
              canonicalSlug: "anthropic/claude-fable-5.2-20261109"),
        .init(id: "anthropic/claude-opus-5.5", name: "Anthropic: Claude Opus 5.5",
              canonicalSlug: "anthropic/claude-opus-5.5-20260921"),
        .init(id: "openai/gpt-6.2-sol", name: "OpenAI: GPT-6.2 Sol",
              canonicalSlug: "openai/gpt-6.2-sol-20261117"),
        .init(id: "openai/gpt-6.2-astra", name: "OpenAI: GPT-6.2 Astra",
              canonicalSlug: "openai/gpt-6.2-astra-20261117"),
        .init(id: "meta/muse-ember", name: "Meta: Muse Ember",
              canonicalSlug: "meta/muse-ember-20261109")
    ]

    /// The model's provider comparison page on openrouter.ai.
    var providersURL: URL? {
        let slug = id.split(separator: ":", maxSplits: 1).first.map(String.init) ?? id
        return URL(string: "https://openrouter.ai/\(slug)/providers")
    }

    var variant: String {
        id.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? "standard"
    }
}
