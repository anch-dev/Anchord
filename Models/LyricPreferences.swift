import Foundation

/// The writer's standing rules for the lyric engine: words to never use,
/// vocabulary to lean toward, and style constraints. Deterministic
/// analysis flags violations; every AI request carries these as hard
/// rules; AI suggestions that break a ban are filtered out.
struct LyricPreferences: Codable, Hashable, Sendable {
    var bannedWords: [String] = []
    var preferredWords: [String] = []
    var flagCliches: Bool = true
    var priority: RewritePriority = .cadenceFirst
    var rhymeStyle: RhymeStyle = .perfectOrSlant
    var explicitContent: ExplicitContent = .allowed
    var perspective: Perspective = .any
    var tense: Tense = .any
    /// Optional per-line syllable target; lines outside it are flagged.
    var targetSyllablesEnabled: Bool = false
    var targetSyllablesMin: Int = 6
    var targetSyllablesMax: Int = 12
    /// Free-form direction ("Southern slang", "no 'gonna'", "imagery from the ocean").
    var styleNotes: String = ""

    init() {}

    // Field-by-field decoding with defaults so preferences saved by an
    // older build keep working when new options are added.
    private enum CodingKeys: String, CodingKey {
        case bannedWords, preferredWords, flagCliches, priority, rhymeStyle, explicitContent
        case perspective, tense, targetSyllablesEnabled, targetSyllablesMin, targetSyllablesMax, styleNotes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LyricPreferences()
        bannedWords = try c.decodeIfPresent([String].self, forKey: .bannedWords) ?? d.bannedWords
        preferredWords = try c.decodeIfPresent([String].self, forKey: .preferredWords) ?? d.preferredWords
        flagCliches = try c.decodeIfPresent(Bool.self, forKey: .flagCliches) ?? d.flagCliches
        priority = try c.decodeIfPresent(RewritePriority.self, forKey: .priority) ?? d.priority
        rhymeStyle = try c.decodeIfPresent(RhymeStyle.self, forKey: .rhymeStyle) ?? d.rhymeStyle
        explicitContent = try c.decodeIfPresent(ExplicitContent.self, forKey: .explicitContent) ?? d.explicitContent
        perspective = try c.decodeIfPresent(Perspective.self, forKey: .perspective) ?? d.perspective
        tense = try c.decodeIfPresent(Tense.self, forKey: .tense) ?? d.tense
        targetSyllablesEnabled = try c.decodeIfPresent(Bool.self, forKey: .targetSyllablesEnabled) ?? d.targetSyllablesEnabled
        targetSyllablesMin = try c.decodeIfPresent(Int.self, forKey: .targetSyllablesMin) ?? d.targetSyllablesMin
        targetSyllablesMax = try c.decodeIfPresent(Int.self, forKey: .targetSyllablesMax) ?? d.targetSyllablesMax
        styleNotes = try c.decodeIfPresent(String.self, forKey: .styleNotes) ?? d.styleNotes
    }

    // MARK: Options

    enum RewritePriority: String, CaseIterable, Identifiable, Codable, Sendable {
        case cadenceFirst, soundFirst, meaningFirst
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .cadenceFirst: "Cadence first"
            case .soundFirst: "Sound first"
            case .meaningFirst: "Meaning first"
            }
        }
        /// Ordered priorities as they're stated to the model.
        var ordered: [String] {
            let cadence = "cadence/pocket (syllable count and stress shape)"
            let sound = "phonetic flow (rhyme, vowel and consonant sounds)"
            let meaning = "meaning and emotional intent"
            switch self {
            case .cadenceFirst: return [cadence, sound, meaning]
            case .soundFirst: return [sound, cadence, meaning]
            case .meaningFirst: return [meaning, cadence, sound]
            }
        }
    }

    enum RhymeStyle: String, CaseIterable, Identifiable, Codable, Sendable {
        case perfectOnly, perfectOrSlant, loose
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .perfectOnly: "Perfect rhymes only"
            case .perfectOrSlant: "Perfect or slant"
            case .loose: "Loose / no rhyme required"
            }
        }
        var instruction: String {
            switch self {
            case .perfectOnly: "Use perfect end rhymes only."
            case .perfectOrSlant: "Perfect or slant end rhymes are both fine."
            case .loose: "End rhyme is optional."
            }
        }
    }

    enum ExplicitContent: String, CaseIterable, Identifiable, Codable, Sendable {
        case allowed, clean
        var id: String { rawValue }
        var displayName: String { self == .allowed ? "Allowed" : "Clean only" }
    }

    enum Perspective: String, CaseIterable, Identifiable, Codable, Sendable {
        case any, first, second, third
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .any: "Any"
            case .first: "First person (I/we)"
            case .second: "Second person (you)"
            case .third: "Third person (he/she/they)"
            }
        }
    }

    enum Tense: String, CaseIterable, Identifiable, Codable, Sendable {
        case any, present, past
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .any: "Any"
            case .present: "Present"
            case .past: "Past"
            }
        }
    }

    // MARK: Matching

    /// Overused lyric images flagged when `flagCliches` is on. Short and
    /// deliberately conservative: phrases, not common single words.
    static let cliches: [String] = [
        "heart of gold", "set me free", "fire burning", "burning desire", "end of time",
        "end of the road", "tears like rain", "in the dark of night", "dance the night away",
        "light up the sky", "touch the sky", "broken heart", "chasing dreams", "ride or die",
        "against all odds", "lost without you", "meant to be", "now or never", "one more time",
        "all night long", "can't live without you", "you complete me", "shine like a star",
        "baby baby", "fly away", "sweet surrender", "stand the test of time", "cold as ice",
    ]

    /// Banned terms present in `text`. Single words match whole words
    /// (so banning "fire" doesn't flag "firefly"); phrases match anywhere.
    func bannedTerms(in text: String) -> [String] {
        Self.matches(of: bannedWords, in: text)
    }

    func clichesFound(in text: String) -> [String] {
        flagCliches ? Self.matches(of: Self.cliches, in: text) : []
    }

    static func matches(of terms: [String], in text: String) -> [String] {
        let lowered = text.lowercased()
        let words = Set(lowered.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init))
        var found: [String] = []
        for term in terms {
            let t = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !t.isEmpty else { continue }
            let hit = t.contains(" ") ? lowered.contains(t) : words.contains(t)
            if hit, !found.contains(t) { found.append(t) }
        }
        return found
    }

    /// The rules block every AI prompt includes.
    var promptRules: String {
        var rules: [String] = []
        rules.append("Priorities, in order: " + priority.ordered.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "; "))
        rules.append(rhymeStyle.instruction)
        let banned = bannedWords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !banned.isEmpty {
            rules.append("NEVER use these words or phrases (hard ban): \(banned.joined(separator: ", ")).")
        }
        if flagCliches {
            rules.append("Avoid stock lyric clichés such as: \(Self.cliches.prefix(10).joined(separator: ", ")).")
        }
        let preferred = preferredWords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !preferred.isEmpty {
            rules.append("Lean toward this vocabulary where it fits naturally: \(preferred.joined(separator: ", ")).")
        }
        if explicitContent == .clean { rules.append("Keep it clean: no profanity or explicit content.") }
        if perspective != .any { rules.append("Write in \(perspective.displayName.lowercased()).") }
        if tense != .any { rules.append("Use \(tense.displayName.lowercased()) tense.") }
        if targetSyllablesEnabled {
            rules.append("Aim for \(targetSyllablesMin)–\(targetSyllablesMax) syllables per line.")
        }
        let notes = styleNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { rules.append("Writer's style notes: \(notes)") }
        return rules.map { "- \($0)" }.joined(separator: "\n")
    }
}

/// App-wide store for the writer's lyric preferences, persisted locally.
@MainActor
final class LyricPreferencesStore: ObservableObject {
    static let shared = LyricPreferencesStore()

    @Published var preferences: LyricPreferences {
        didSet { save() }
    }

    private static let key = "anchord.lyricPreferences"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(LyricPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = LyricPreferences()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
