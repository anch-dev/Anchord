import Foundation

/// The structured musical intent behind a generated Suno prompt, kept
/// separate from the generated prose itself (see `SongProject.soundPrompt`
/// / `negativePrompt`). This is what the dataset-derived prompt generator
/// (`SunoPromptGenerator`) actually consumes -- real tags from the
/// 659,788-song dataset, each carrying its real song-count and classified
/// category, not free-text strings.
struct PromptDNA: Codable, Hashable, Sendable {
    var selectedTags: [MusicTag] = []
    var mode: FusionMode = .blended
    /// Lowercased names of the tags marked as persistent anchors in
    /// Hybrid mode. Ignored by the other three modes.
    var anchorNames: Set<String> = []
    var chaosEnabled: Bool = false
    var songLengthSeconds: Int = 240

    var allTagNames: [String] { selectedTags.map(\.name) }

    var generationOptions: PromptGenerationOptions {
        PromptGenerationOptions(chaos: chaosEnabled, songLengthSeconds: songLengthSeconds)
    }

    func tagsByCategory() -> [TagCategory: [MusicTag]] {
        Dictionary(grouping: selectedTags, by: \.category)
    }
}
