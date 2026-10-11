import Foundation
import SwiftData

/// One turn of a song's chat. Assistant text is stored raw (with its
/// ```blocks```) and parsed for display, so nothing is lost.
@Model
final class ChatMessage {
    var id: UUID = UUID()
    var role: String = "user"
    var text: String = ""
    var createdAt: Date = Date.now
    /// Version saved just before this reply's blocks were applied; Undo
    /// restores it. Nil if the reply hasn't been applied.
    var appliedVersionNumber: Int?
    var appliedSummary: String?

    var project: SongProject?

    init(role: String, text: String) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.createdAt = .now
    }

    var isUser: Bool { role == "user" }
}
