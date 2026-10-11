import Foundation

/// The structured musical intent behind a generated Suno prompt, kept
/// separate from the generated prose itself (see `SongProject.soundPrompt`
/// / `negativePrompt`). This is what the dataset-derived prompt generator
/// (`SunoPromptGenerator`) actually consumes -- real tags from the
/// 659,788-song dataset, each carrying its real song-count and classified
/// category, not free-text strings -- plus the writer's own `intent`
/// (energy, vocals, mood, production direction) layered on top.
struct PromptDNA: Codable, Hashable, Sendable {
    var selectedTags: [MusicTag] = []
    var mode: FusionMode = .blended
    /// Lowercased names of the tags marked as persistent anchors in
    /// Hybrid mode. Ignored by the other three modes.
    var anchorNames: Set<String> = []
    var chaosEnabled: Bool = false
    var songLengthSeconds: Int = 240
    var intent: PromptIntent = PromptIntent()

    init(
        selectedTags: [MusicTag] = [],
        mode: FusionMode = .blended,
        anchorNames: Set<String> = [],
        chaosEnabled: Bool = false,
        songLengthSeconds: Int = 240,
        intent: PromptIntent = PromptIntent()
    ) {
        self.selectedTags = selectedTags
        self.mode = mode
        self.anchorNames = anchorNames
        self.chaosEnabled = chaosEnabled
        self.songLengthSeconds = songLengthSeconds
        self.intent = intent
    }

    // Decoded field by field with defaults, so DNA saved by earlier builds
    // (which had no `intent`) still loads instead of silently resetting.
    private enum CodingKeys: String, CodingKey {
        case selectedTags, mode, anchorNames, chaosEnabled, songLengthSeconds, intent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedTags = try c.decodeIfPresent([MusicTag].self, forKey: .selectedTags) ?? []
        mode = try c.decodeIfPresent(FusionMode.self, forKey: .mode) ?? .blended
        anchorNames = try c.decodeIfPresent(Set<String>.self, forKey: .anchorNames) ?? []
        chaosEnabled = try c.decodeIfPresent(Bool.self, forKey: .chaosEnabled) ?? false
        songLengthSeconds = try c.decodeIfPresent(Int.self, forKey: .songLengthSeconds) ?? 240
        intent = try c.decodeIfPresent(PromptIntent.self, forKey: .intent) ?? PromptIntent()
    }

    var allTagNames: [String] { selectedTags.map(\.name) }

    var generationOptions: PromptGenerationOptions {
        PromptGenerationOptions(chaos: chaosEnabled, songLengthSeconds: songLengthSeconds)
    }

    func tagsByCategory() -> [TagCategory: [MusicTag]] {
        Dictionary(grouping: selectedTags, by: \.category)
    }
}

/// The writer's explicit direction, independent of the dataset tags.
/// Each field is optional; empty fields are simply left out of the
/// generated prompt.
struct PromptIntent: Codable, Hashable, Sendable {
    var energy: EnergyLevel = .unspecified
    var vocals: String = ""
    var mood: String = ""
    var instrumentation: String = ""
    var production: String = ""
    var mixing: String = ""
    var performance: String = ""
    /// Extra things to keep out, appended to NEG.
    var avoid: String = ""

    init() {}

    private enum CodingKeys: String, CodingKey {
        case energy, vocals, mood, instrumentation, production, mixing, performance, avoid
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        energy = try c.decodeIfPresent(EnergyLevel.self, forKey: .energy) ?? .unspecified
        vocals = try c.decodeIfPresent(String.self, forKey: .vocals) ?? ""
        mood = try c.decodeIfPresent(String.self, forKey: .mood) ?? ""
        instrumentation = try c.decodeIfPresent(String.self, forKey: .instrumentation) ?? ""
        production = try c.decodeIfPresent(String.self, forKey: .production) ?? ""
        mixing = try c.decodeIfPresent(String.self, forKey: .mixing) ?? ""
        performance = try c.decodeIfPresent(String.self, forKey: .performance) ?? ""
        avoid = try c.decodeIfPresent(String.self, forKey: .avoid) ?? ""
    }

    var isEmpty: Bool {
        energy == .unspecified && [vocals, mood, instrumentation, production, mixing, performance, avoid]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

enum EnergyLevel: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case unspecified, low, medium, high, explosive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unspecified: "Any"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .explosive: "Explosive"
        }
    }

    /// Wording used inside the generated POS prompt.
    var promptPhrase: String? {
        switch self {
        case .unspecified: nil
        case .low: "low, restrained energy"
        case .medium: "steady mid-level energy"
        case .high: "high, driving energy"
        case .explosive: "explosive, peak-intensity energy"
        }
    }
}
