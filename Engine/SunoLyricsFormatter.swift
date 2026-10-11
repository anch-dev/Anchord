import Foundation

/// Builds Suno's LYRICS field from the writer's draft.
///
/// Deterministic, no AI: existing `[Section]` tags are kept untouched;
/// a draft without tags gets them inferred from stanza structure (a
/// stanza that repeats is treated as the chorus, the rest as verses,
/// with an [Intro]/[Outro] only if the writer marked them).
enum SunoLyricsFormatter {
    static let sectionTags = [
        "Intro", "Verse", "Pre-Chorus", "Chorus", "Post-Chorus", "Hook",
        "Bridge", "Breakdown", "Drop", "Interlude", "Instrumental", "Solo", "Outro", "End",
    ]

    static func hasSectionTags(_ lyrics: String) -> Bool {
        lyrics.split(whereSeparator: \.isNewline).contains { isTagLine(String($0)) }
    }

    static func isTagLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("[") && t.hasSuffix("]") && t.count > 2
    }

    static func format(_ lyrics: String) -> String {
        let normalized = lyrics.replacingOccurrences(of: "\r\n", with: "\n")
        if hasSectionTags(normalized) {
            return collapseBlankRuns(normalized)
        }

        let stanzas = splitStanzas(normalized)
        guard !stanzas.isEmpty else { return "" }

        // A stanza that appears more than once (ignoring case/punctuation)
        // is the chorus.
        let keys = stanzas.map(stanzaKey)
        var counts: [String: Int] = [:]
        for key in keys { counts[key, default: 0] += 1 }
        let chorusKey = counts.filter { $0.value > 1 }.max { $0.value < $1.value }?.key

        var verseNumber = 0
        var blocks: [String] = []
        for (index, stanza) in stanzas.enumerated() {
            let tag: String
            if keys[index] == chorusKey {
                tag = "[Chorus]"
            } else if stanzas.count > 2, index == stanzas.count - 1, stanza.count <= 2 {
                tag = "[Outro]"
            } else {
                verseNumber += 1
                tag = "[Verse \(verseNumber)]"
            }
            blocks.append(([tag] + stanza).joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n")
    }

    private static func splitStanzas(_ text: String) -> [[String]] {
        var stanzas: [[String]] = []
        var current: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !current.isEmpty { stanzas.append(current); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { stanzas.append(current) }
        return stanzas
    }

    private static func stanzaKey(_ stanza: [String]) -> String {
        stanza.joined(separator: " ").lowercased().filter { $0.isLetter || $0 == " " }
    }

    private static func collapseBlankRuns(_ text: String) -> String {
        text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
