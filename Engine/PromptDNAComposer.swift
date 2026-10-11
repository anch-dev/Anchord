import Foundation

/// Turns a song's `PromptDNA` into Suno POS/NEG text.
///
/// The dataset-derived `SunoPromptGenerator` stays the engine: it writes
/// the fusion prose from the real tags. This layer only adds the writer's
/// explicit `PromptIntent` (energy, vocals, mood…) as a short direction
/// sentence and extra NEG items, inside Suno's length limits. It never
/// substitutes generic text for the dataset output.
enum PromptDNAComposer {
    static let positiveLimit = 1000
    static let negativeLimit = 400

    struct Output: Sendable {
        var positive: String
        var negative: String
    }

    static func compose(_ dna: PromptDNA) -> Output {
        let base = dna.selectedTags.isEmpty
            ? ""
            : SunoPromptGenerator.generatePrompt(
                tags: dna.selectedTags,
                mode: dna.mode,
                anchorNames: dna.anchorNames,
                options: dna.generationOptions
            )
        let baseNegative = dna.selectedTags.isEmpty
            ? ""
            : SunoPromptGenerator.generateNegativePrompt(tags: dna.selectedTags, mode: dna.mode)

        return apply(dna.intent, positive: base, negative: baseNegative)
    }

    /// Layers the writer's intent onto already-generated text (e.g. the
    /// exact prompt the Fusion Builder previewed). Idempotent: text that
    /// already carries this direction is returned unchanged.
    static func apply(_ intent: PromptIntent, positive: String, negative: String) -> Output {
        Output(
            positive: appendDirection(intentSentence(intent), to: positive),
            negative: appendAvoid(intent.avoid, to: negative)
        )
    }

    /// "Direction: high, driving energy; vocals: breathy alto; …"
    static func intentSentence(_ intent: PromptIntent) -> String {
        var parts: [String] = []
        if let energy = intent.energy.promptPhrase { parts.append(energy) }
        let labeled: [(String, String)] = [
            ("vocals", intent.vocals),
            ("mood", intent.mood),
            ("instrumentation", intent.instrumentation),
            ("production", intent.production),
            ("mix", intent.mixing),
            ("performance", intent.performance),
        ]
        for (label, value) in labeled {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append("\(label): \(trimmed)") }
        }
        guard !parts.isEmpty else { return "" }
        return "Direction: \(parts.joined(separator: "; "))."
    }

    /// The writer's direction is kept whole; if the combination is over
    /// the limit, the dataset prose is trimmed at a sentence/clause
    /// boundary to make room (its timestamps in Sectioned mode come
    /// first, so those survive).
    private static func appendDirection(_ direction: String, to base: String) -> String {
        guard !direction.isEmpty, !base.contains(direction) else { return base }
        guard !base.isEmpty else {
            return SunoPromptGenerator.hardTrim(direction, limit: positiveLimit)
        }
        let combined = "\(base) \(direction)"
        if combined.count <= positiveLimit { return combined }
        let room = positiveLimit - direction.count - 1
        guard room > 200 else {
            return SunoPromptGenerator.hardTrim(combined, limit: positiveLimit)
        }
        return "\(SunoPromptGenerator.hardTrim(base, limit: room)) \(direction)"
    }

    private static func appendAvoid(_ avoid: String, to base: String) -> String {
        let extra = avoid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extra.isEmpty else { return base }
        let sentence = "Also avoid: \(extra.hasSuffix(".") ? String(extra.dropLast()) : extra)."
        guard !base.contains(sentence) else { return base }
        let combined = base.isEmpty ? sentence : "\(base) \(sentence)"
        return SunoPromptGenerator.hardTrim(combined, limit: negativeLimit)
    }
}
