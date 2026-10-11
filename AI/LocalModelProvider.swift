import Foundation

/// Runs prompts on a downloaded, verified local model through whatever
/// `LocalInferenceRuntime` is registered. It never pretends: if no model
/// is installed or no runtime exists, it says exactly that.
actor LocalModelProvider: AIProvider {
    nonisolated let kind: AIProviderKind = .local

    private let model: InstalledModel?
    private var loadedModelID: String?

    init(model: InstalledModel?) {
        self.model = model
    }

    /// Status for a given installed model, without loading anything.
    static func status(for model: InstalledModel?) -> ProviderStatus {
        guard let model else {
            return .unavailable("No local model selected. Download one in AI Settings.")
        }
        guard FileManager.default.fileExists(atPath: model.fileURL.path) else {
            return .unavailable("\(model.displayName) is missing from storage. Download it again.")
        }
        guard let runtime = LocalRuntimeRegistry.current else {
            return .unavailable(AIProviderError.localRuntimeMissing.errorDescription ?? "No local runtime.")
        }
        let ext = model.fileURL.pathExtension.lowercased()
        guard runtime.supportedFormats.contains(ext) else {
            return .unavailable("\(runtime.name) can't load .\(ext) models.")
        }
        return .ready
    }

    func generate(prompt: String, instructions: String) async throws -> String {
        guard let model else { throw AIProviderError.modelUnavailable }
        guard let runtime = LocalRuntimeRegistry.current else { throw AIProviderError.localRuntimeMissing }
        if loadedModelID != model.id {
            await runtime.unloadModel()
            try await runtime.loadModel(at: model.fileURL)
            loadedModelID = model.id
        }
        return try await runtime.generate(
            prompt: prompt,
            systemPrompt: instructions,
            maxTokens: 768
        )
    }
}
