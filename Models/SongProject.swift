import Foundation
import SwiftData

@Model
final class SongProject {
    @Attribute(.unique) var id: UUID
    var title: String
    var lyrics: String
    /// The generated Suno "POS" (style/sound direction) prompt. Kept as
    /// plain editable text -- the user can hand-edit whatever the fusion
    /// engine produced -- with `promptDNA` separately preserving the
    /// structured tag selection that produced it, per the POS/NEG/LYRICS
    /// separation requirement (this field is POS).
    var soundPrompt: String
    /// Suno "NEG" (negative prompt). Separate field, never folded into
    /// `soundPrompt` as one giant string.
    var negativePrompt: String
    var genre: String
    var createdAt: Date
    var updatedAt: Date

    /// Structured musical intent (selected tags, mode, chaos, song
    /// length) behind the current `soundPrompt`/`negativePrompt`, so the
    /// fusion builder can be reopened later and continue from where it
    /// left off instead of starting over. Stored as encoded JSON rather
    /// than a native SwiftData relationship for now -- simple, and easy
    /// to evolve once version history (point 9 in the roadmap) lands.
    var promptDNAData: Data?

    var promptDNA: PromptDNA {
        get {
            guard let promptDNAData,
                  let decoded = try? JSONDecoder().decode(PromptDNA.self, from: promptDNAData) else {
                return PromptDNA()
            }
            return decoded
        }
        set {
            promptDNAData = try? JSONEncoder().encode(newValue)
        }
    }

    init(
        title: String = "Untitled Song",
        lyrics: String = "",
        soundPrompt: String = "",
        negativePrompt: String = "",
        genre: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.lyrics = lyrics
        self.soundPrompt = soundPrompt
        self.negativePrompt = negativePrompt
        self.genre = genre
        self.createdAt = .now
        self.updatedAt = .now
        self.promptDNAData = nil
    }
}
