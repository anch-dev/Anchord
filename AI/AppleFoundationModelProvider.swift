import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleFoundationModelProvider: AIProvider {
    let kind: AIProviderKind = .appleFoundation

    #if canImport(FoundationModels)
    private let session: LanguageModelSession

    init() {
        session = LanguageModelSession(instructions: """
        You are Anchord, a songwriting assistant.

        Prioritize cadence and performance pocket before word choice.
        Preserve the user's intent unless asked to change it.
        Pay attention to syllable count, stressed syllables, phonetic chaining,
        internal rhyme, end rhyme, and natural spoken phrasing.

        Do not automatically turn a rewrite into generic poetry.
        Avoid cliché imagery unless the writer explicitly asks for it.
        """)
    }
    #else
    init() {}
    #endif

    func generate(prompt: String) async throws -> String {
        #if canImport(FoundationModels)
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

    var errorDescription: String? {
        switch self {
        case .unsupported: "This AI provider is not available on this build."
        case .modelUnavailable: "The selected model is unavailable."
        case .generationFailed: "The model could not complete the request."
        }
    }
}
