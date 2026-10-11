import Foundation

/// Application-layer entry point for AI work. Views ask for a task
/// ("rewrite this line"); this picks a provider per the song's
/// preference and builds prompts that carry Anchord's deterministic
/// measurements (syllables, stress, rhyme) as constraints, so the model
/// refines the writer's material instead of replacing it.
@MainActor
final class AIService: ObservableObject {
    @Published private(set) var isGenerating = false
    @Published private(set) var lastProvider: AIProviderKind?
    @Published var lastError: String?

    private let appleProvider = AppleFoundationModelProvider()

    // MARK: Provider routing

    struct Resolution {
        let provider: (any AIProvider)?
        let kind: AIProviderKind
        let status: ProviderStatus
    }

    func resolve(_ preference: AIProviderPreference) -> Resolution {
        let appleStatus = AppleFoundationModelProvider.status
        let localModel = InstalledModelRegistry.shared.selectedModel
        let localStatus = LocalModelProvider.status(for: localModel)

        switch preference {
        case .appleIntelligence:
            return Resolution(provider: appleStatus.isReady ? appleProvider : nil, kind: .appleFoundation, status: appleStatus)
        case .localModel:
            return Resolution(provider: localStatus.isReady ? LocalModelProvider(model: localModel) : nil, kind: .local, status: localStatus)
        case .automatic:
            if appleStatus.isReady {
                return Resolution(provider: appleProvider, kind: .appleFoundation, status: .ready)
            }
            if localStatus.isReady {
                return Resolution(provider: LocalModelProvider(model: localModel), kind: .local, status: .ready)
            }
            return Resolution(
                provider: nil,
                kind: .unavailable,
                status: .unavailable("\(appleStatus.message) \(localStatus.message)")
            )
        }
    }

    private func run(_ prompt: String, preference: AIProviderPreference) async throws -> String {
        let resolution = resolve(preference)
        guard let provider = resolution.provider else {
            throw AIProviderError.noProviderAvailable(resolution.status.message)
        }
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }
        do {
            let output = try await provider.generate(prompt: prompt)
            lastProvider = resolution.kind
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    // MARK: Tasks

    private var preferences: LyricPreferences { LyricPreferencesStore.shared.preferences }

    struct RewriteResult {
        var suggestions: [String]
        /// Suggestions dropped because they used a banned word/phrase.
        var hiddenForBans: Int
    }

    /// Up to three alternative versions of one line, following the
    /// writer's Lyric Preferences (default priority: cadence/pocket, then
    /// phonetic flow, then meaning). Suggestions that use a banned term
    /// are removed before they reach the UI.
    func rewriteLine(
        _ line: LineAnalysis,
        in song: LyricAnalysis,
        instruction: String,
        preference: AIProviderPreference
    ) async throws -> RewriteResult {
        let rules = preferences
        let neighbors = song.lines
            .filter { $0.stanza == line.stanza && $0.id != line.id }
            .map { "- \($0.text)" }
            .joined(separator: "\n")

        let prompt = """
        Rewrite one lyric line. Give exactly 3 alternatives, one per line, no numbering, no quotes, no commentary.

        Measured targets:
        - Cadence/pocket: keep \(line.syllableCount) syllables (±1) and this stress shape: \(line.stressPattern)
        - Phonetic flow: keep the ending rhyming on "\(line.endRhymeTail)"\(line.rhymeLetter.map { " (rhyme group \($0))" } ?? ""), preserve vowel sounds where possible
        - Meaning: keep the emotional intent

        Writer's rules (the instruction may override priorities, never bans):
        \(rules.promptRules)

        Writer's instruction: \(instruction.isEmpty ? "Make it land better while keeping the pocket." : instruction)

        Other lines in this section (for context, do not rewrite):
        \(neighbors.isEmpty ? "(none)" : neighbors)

        Line to rewrite:
        \(line.text)
        """

        let output = try await run(prompt, preference: preference)
        let candidates = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t-•*\"“”0123456789.)")) }
            .filter { !$0.isEmpty }
            .prefix(3)
        let allowed = candidates.filter { rules.bannedTerms(in: $0).isEmpty }
        return RewriteResult(suggestions: Array(allowed), hiddenForBans: candidates.count - allowed.count)
    }

    func analyzeLyrics(_ lyrics: String, measurements: LyricAnalysis, preference: AIProviderPreference) async throws -> String {
        let prompt = """
        Analyze these lyrics for songwriting performance. Anchord has already measured each line \
        (syllables, estimated stress, end-rhyme group); treat those numbers as facts and build on them.

        Cover:
        1. cadence and pocket: which lines will fight the melody and why
        2. syllable density across sections
        3. phonetic chaining and internal rhyme
        4. end-rhyme scheme and where slant rhyme could replace a weak perfect rhyme
        5. lines that may be awkward to sing, with one concrete fix each

        Be specific and brief. Quote line numbers. Respect the writer's rules below; point out \
        any line that breaks them.

        Writer's rules:
        \(preferences.promptRules)

        Measurements:
        \(measurements.constraintSummary)

        Lyrics:
        \(lyrics)
        """
        return try await run(prompt, preference: preference)
    }

    /// Critique of a dataset-generated prompt. Suggests edits; never
    /// rewrites the prompt wholesale.
    func reviewPrompt(positive: String, negative: String, dna: PromptDNA, preference: AIProviderPreference) async throws -> String {
        let tags = dna.selectedTags.map { "\($0.name) (\($0.category.displayName), \($0.songCountDescription))" }
        let prompt = """
        Review this Suno style prompt. It was generated from real tags mined from a 659,788-song dataset; \
        keep those tags and their roles. Do not rewrite the prompt. Instead give at most 5 short bullet points:
        - contradictions between tags or between POS and NEG
        - tags Suno may misread, with a clearer wording
        - anything missing for the writer's direction (energy, vocals, mood)

        Mode: \(dna.mode.displayName)
        Tags: \(tags.joined(separator: "; "))
        Direction: \(PromptDNAComposer.intentSentence(dna.intent).isEmpty ? "(none)" : PromptDNAComposer.intentSentence(dna.intent))

        POS:
        \(positive)

        NEG:
        \(negative)
        """
        return try await run(prompt, preference: preference)
    }
}
