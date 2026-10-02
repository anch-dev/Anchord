import Foundation

@MainActor
final class AIService: ObservableObject {
    @Published private(set) var isGenerating = false
    @Published private(set) var provider: AIProviderKind = .appleFoundation

    private let appleProvider = AppleFoundationModelProvider()

    func improveLine(_ line: String, instruction: String) async throws -> String {
        isGenerating = true
        defer { isGenerating = false }

        let prompt = """
        Improve this lyric line.

        Instruction:
        \(instruction)

        Preserve:
        - approximate syllable count
        - rhythmic pocket
        - natural pronunciation
        - emotional intent

        Line:
        \(line)

        Return only the revised line.
        """

        return try await appleProvider.generate(prompt: prompt)
    }

    func analyzeLyrics(_ lyrics: String) async throws -> String {
        isGenerating = true
        defer { isGenerating = false }

        let prompt = """
        Analyze these lyrics specifically for songwriting performance.

        Discuss:
        1. cadence and pocket
        2. syllable density
        3. phonetic chaining
        4. rhyme/internal rhyme
        5. lines that may be awkward to sing

        Lyrics:
        \(lyrics)
        """

        return try await appleProvider.generate(prompt: prompt)
    }
}
