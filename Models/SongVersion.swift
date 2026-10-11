import Foundation
import SwiftData

/// An immutable snapshot of a song's creative state, so iterating never
/// destroys earlier work: Version 1 → Version 2 → Version 3, each one
/// restorable or copyable into a new song.
@Model
final class SongVersion {
    var id: UUID = UUID()
    var number: Int = 0
    var label: String?
    var createdAt: Date = Date.now

    var title: String = ""
    var lyrics: String = ""
    var soundPrompt: String = ""
    var negativePrompt: String = ""
    var sunoLyrics: String = ""
    var genre: String = ""
    var promptDNAData: Data?

    var project: SongProject?

    init(number: Int, label: String?, snapshotOf project: SongProject) {
        self.id = UUID()
        self.number = number
        self.label = label
        self.createdAt = .now
        self.title = project.title
        self.lyrics = project.lyrics
        self.soundPrompt = project.soundPrompt
        self.negativePrompt = project.negativePrompt
        self.sunoLyrics = project.sunoLyrics
        self.genre = project.genre
        self.promptDNAData = project.promptDNAData
    }

    var displayName: String {
        if let label, !label.isEmpty { return "Version \(number) · \(label)" }
        return "Version \(number)"
    }
}
