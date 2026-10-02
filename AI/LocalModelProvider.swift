import Foundation

/// Placeholder for downloaded Hugging Face models.
///
/// The app intentionally separates model discovery/download from inference.
/// Future adapters can use Apple's Core AI / MLX-compatible runtimes or another
/// supported on-device runtime without changing the songwriting feature layer.
actor LocalModelProvider: AIProvider {
    let kind: AIProviderKind = .local

    private(set) var modelIdentifier: String?

    init(modelIdentifier: String? = nil) {
        self.modelIdentifier = modelIdentifier
    }

    func generate(prompt: String) async throws -> String {
        // TODO: Connect a downloaded local model runtime.
        throw AIProviderError.modelUnavailable
    }

    func select(modelIdentifier: String) {
        self.modelIdentifier = modelIdentifier
    }
}
