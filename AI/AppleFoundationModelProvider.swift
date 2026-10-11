import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleFoundationModelProvider: AIProvider {
    let kind: AIProviderKind = .appleFoundation

    static let instructions = """
    You are Anchord, a songwriting assistant.

    Prioritize cadence and performance pocket first, phonetic flow second,
    and meaning third, unless the writer explicitly asks otherwise.
    Preserve the user's intent unless asked to change it.
    Pay attention to syllable count, stressed syllables, phonetic chaining,
    internal rhyme, end rhyme, and natural spoken phrasing.

    Do not automatically turn a rewrite into generic poetry.
    Avoid cliché imagery unless the writer explicitly asks for it.
    """

    /// Live availability of Apple's on-device model on this device.
    static var status: ProviderStatus {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.deviceNotEligible):
            return .unavailable("This device doesn't support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in Settings to use it here.")
        case .unavailable(.modelNotReady):
            return .unavailable("Apple Intelligence is still downloading or preparing its model.")
        case .unavailable:
            return .unavailable("Apple Intelligence is unavailable right now.")
        @unknown default:
            return .unavailable("Apple Intelligence is unavailable right now.")
        }
        #else
        return .unavailable("This build doesn't include the Foundation Models framework.")
        #endif
    }

    func generate(prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        guard Self.status.isReady else { throw AIProviderError.modelUnavailable }
        // A fresh session per request: each task is self-contained, and a
        // long-lived session would keep growing its transcript until it
        // overflowed the model's context window.
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(to: prompt)
        return response.content
        #else
        throw AIProviderError.unsupported
        #endif
    }
}

enum AIProviderError: LocalizedError {
    case unsupported
    case modelUnavailable
    case generationFailed
    case noProviderAvailable(String)
    case localRuntimeMissing

    var errorDescription: String? {
        switch self {
        case .unsupported: "This AI provider is not available on this build."
        case .modelUnavailable: "The selected model is unavailable."
        case .generationFailed: "The model could not complete the request."
        case .noProviderAvailable(let reason): reason
        case .localRuntimeMissing: "Local models can be downloaded and verified, but this build doesn't include a local inference engine yet."
        }
    }
}
