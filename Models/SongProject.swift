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

    /// Suno "LYRICS" field: the lyrics as they'll be pasted into Suno,
    /// with [Verse]/[Chorus] section tags. Kept separate from `lyrics`
    /// (the writer's working draft) so formatting for Suno never
    /// overwrites the draft. Defaults keep SwiftData's lightweight
    /// migration working for projects saved before this field existed.
    var sunoLyrics: String = ""

    /// Last AI analysis text, so it survives leaving the song.
    var analysisNotes: String = ""

    /// Raw value of the `AIProviderPreference` chosen for this song.
    var aiProviderPreferenceRaw: String = "automatic"

    /// Saved snapshots, newest first when sorted by `createdAt`.
    @Relationship(deleteRule: .cascade, inverse: \SongVersion.project)
    var versions: [SongVersion] = []

    /// The song's chat with the assistant, oldest first when sorted.
    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.project)
    var chatMessages: [ChatMessage] = []

    var sortedChat: [ChatMessage] {
        chatMessages.sorted { $0.createdAt < $1.createdAt }
    }

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

    var aiProviderPreference: AIProviderPreference {
        get { AIProviderPreference(rawValue: aiProviderPreferenceRaw) ?? .automatic }
        set { aiProviderPreferenceRaw = newValue.rawValue }
    }

    var sortedVersions: [SongVersion] {
        versions.sorted { $0.createdAt > $1.createdAt }
    }

    /// Snapshot the current state as a new version.
    @discardableResult
    func saveVersion(label: String? = nil, in context: ModelContext) -> SongVersion {
        let number = (versions.map(\.number).max() ?? 0) + 1
        let version = SongVersion(number: number, label: label, snapshotOf: self)
        context.insert(version)
        version.project = self
        return version
    }

    /// Replace the working state with a saved version. Callers should
    /// save the current state first if it shouldn't be lost.
    func restore(_ version: SongVersion) {
        title = version.title
        lyrics = version.lyrics
        soundPrompt = version.soundPrompt
        negativePrompt = version.negativePrompt
        sunoLyrics = version.sunoLyrics
        genre = version.genre
        promptDNAData = version.promptDNAData
        updatedAt = .now
    }
}
