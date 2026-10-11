import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Platform clipboard behind one call, so shared views don't need
/// UIKit/AppKit conditionals of their own.
enum Clipboard {
    @MainActor
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

/// Line-level edits that keep the analyzer's line numbering (non-blank,
/// non-[Section] lines in order) consistent with the stored lyrics.
enum LyricsEditing {
    static func replacingLine(at index: Int, in lyrics: String, with newText: String) -> String {
        var lines = lyrics.components(separatedBy: "\n")
        var counter = 0
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !SunoLyricsFormatter.isTagLine(trimmed) else { continue }
            if counter == index {
                let indent = String(lines[i].prefix { $0 == " " || $0 == "\t" })
                lines[i] = indent + newText
                return lines.joined(separator: "\n")
            }
            counter += 1
        }
        return lyrics
    }
}
