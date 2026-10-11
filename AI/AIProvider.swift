import Foundation

enum AIProviderKind: String, CaseIterable, Identifiable, Codable {
    case appleFoundation
    case local
    case unavailable

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleFoundation: "Apple Intelligence"
        case .local: "Local Model"
        case .unavailable: "Unavailable"
        }
    }
}

/// What the writer asked for. `automatic` prefers Apple Intelligence when
/// it's available and falls back to the selected local model.
enum AIProviderPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case appleIntelligence
    case localModel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .appleIntelligence: "Apple Intelligence"
        case .localModel: "Local Model"
        }
    }
}

/// Whether a provider can run right now, and if not, why -- shown to the
/// writer verbatim instead of failing silently.
enum ProviderStatus: Equatable, Sendable {
    case ready
    case unavailable(String)

    var isReady: Bool { self == .ready }

    var message: String {
        switch self {
        case .ready: "Ready"
        case .unavailable(let reason): reason
        }
    }
}

protocol AIProvider: Sendable {
    var kind: AIProviderKind { get }
    /// One self-contained request. `instructions` is the system prompt.
    func generate(prompt: String, instructions: String) async throws -> String
}

extension AIProvider {
    func generate(prompt: String) async throws -> String {
        try await generate(prompt: prompt, instructions: AnchordPrompts.system)
    }
}
