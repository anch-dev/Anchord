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

protocol AIProvider: Sendable {
    var kind: AIProviderKind { get }
    func generate(prompt: String) async throws -> String
}
