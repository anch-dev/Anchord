import Foundation
import SwiftData

@Model
final class SongProject {
    @Attribute(.unique) var id: UUID
    var title: String
    var lyrics: String
    var soundPrompt: String
    var negativePrompt: String
    var genre: String
    var createdAt: Date
    var updatedAt: Date

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
    }
}
