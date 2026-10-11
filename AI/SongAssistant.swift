import Foundation
import SwiftData

/// One labeled block in an assistant reply (```lyrics … ```), mapped to
/// the song field it fills.
struct ReplyBlock: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case lyrics, title, tags, direction, sunoLyrics = "suno_lyrics", pos, neg

        var displayName: String {
            switch self {
            case .lyrics: "Lyrics"
            case .title: "Title"
            case .tags: "Fusion Tags"
            case .direction: "Direction"
            case .sunoLyrics: "Suno Lyrics"
            case .pos: "Style (POS)"
            case .neg: "Exclude (NEG)"
            }
        }

        var symbolName: String {
            switch self {
            case .lyrics: "music.note.list"
            case .title: "textformat"
            case .tags: "wand.and.stars"
            case .direction: "slider.horizontal.3"
            case .sunoLyrics: "text.alignleft"
            case .pos: "text.badge.star"
            case .neg: "nosign"
            }
        }
    }

    let id: Int
    let kind: Kind
    let content: String
}

struct AssistantReply: Sendable {
    /// The conversational part, with blocks removed.
    let prose: String
    let blocks: [ReplyBlock]

    /// Parses ```name\n…``` blocks. Unknown block names stay in the prose.
    static func parse(_ text: String) -> AssistantReply {
        let pattern = "```[ \\t]*([A-Za-z_]+)[ \\t]*\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return AssistantReply(prose: text, blocks: [])
        }
        let ns = text as NSString
        var blocks: [ReplyBlock] = []
        var prose = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1)).lowercased()
            let alias = name == "sunolyrics" || name == "suno" ? "suno_lyrics" : name
            guard let kind = ReplyBlock.Kind(rawValue: alias) else { continue }
            let content = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            blocks.append(ReplyBlock(id: blocks.count, kind: kind, content: content))
            prose = prose.replacingOccurrences(of: ns.substring(with: match.range), with: "")
        }
        let cleaned = prose
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AssistantReply(prose: cleaned, blocks: blocks)
    }
}

/// Builds chat prompts from the song's live state and applies the model's
/// blocks back onto the song. Fusion tags always go through the dataset:
/// each name is resolved against `TagDatabase`, and POS/NEG are written by
/// the dataset-driven generator, not by the model.
@MainActor
enum SongAssistant {

    // MARK: Prompt

    /// Apple's on-device model has a small context window, so the song
    /// snapshot and history are trimmed to stay well inside it.
    static func prompt(
        for message: String,
        project: SongProject,
        history: [ChatMessage],
        preferences: LyricPreferences
    ) -> String {
        let dna = project.promptDNA
        let analysis = CadenceAnalyzer(preferences: preferences).analyzeSong(project.lyrics)
        let pocket = analysis.stanzas.map { stanza in
            analysis.lines.filter { $0.stanza == stanza.id }.map { "\($0.syllableCount)" }.joined(separator: ",")
                + " (\(stanza.scheme))"
        }.joined(separator: " | ")

        let direction = PromptDNAComposer.intentSentence(dna.intent)
        let recent = history.suffix(6).map(historyLine).joined(separator: "\n")

        return """
        SONG STATE
        Title: \(project.title)
        Genre: \(project.genre.isEmpty ? "(none)" : project.genre)
        Lyrics:
        \(project.lyrics.isEmpty ? "(empty)" : clip(project.lyrics, 2200))
        Syllables per line by section (rhyme scheme): \(pocket.isEmpty ? "(none)" : pocket)
        Fusion: \(dna.selectedTags.isEmpty ? "(no tags)" : "\(dna.mode.displayName) mode; " + dna.allTagNames.joined(separator: ", "))
        \(direction.isEmpty ? "Direction: (none)" : direction)
        POS: \(project.soundPrompt.isEmpty ? "(empty)" : clip(project.soundPrompt, 500))
        NEG: \(project.negativePrompt.isEmpty ? "(empty)" : clip(project.negativePrompt, 200))
        Suno lyrics: \(project.sunoLyrics.isEmpty ? "(empty)" : "\(project.sunoLyrics.count) characters")

        WRITER'S RULES
        \(preferences.promptRules)

        CONVERSATION SO FAR
        \(recent.isEmpty ? "(new conversation)" : recent)

        Writer: \(message)
        Anchord:
        """
    }

    private static func historyLine(_ message: ChatMessage) -> String {
        if message.isUser { return "Writer: \(clip(message.text, 500))" }
        let prose = AssistantReply.parse(message.text).prose
        return "Anchord: \(clip(prose.isEmpty ? "(updated the song)" : prose, 500))"
    }

    private static func clip(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }

    // MARK: Applying

    struct ApplyResult {
        var appliedKinds: [ReplyBlock.Kind] = []
        var notes: [String] = []

        var summary: String {
            var parts: [String] = []
            if !appliedKinds.isEmpty {
                parts.append("Updated " + appliedKinds.map(\.displayName).joined(separator: ", "))
            }
            parts.append(contentsOf: notes)
            return parts.joined(separator: ". ")
        }
    }

    /// Applies blocks to the song. Callers save a version first.
    static func apply(_ blocks: [ReplyBlock], to project: SongProject) async -> ApplyResult {
        var result = ApplyResult()
        var dna = project.promptDNA
        var dnaChanged = false
        var tagsChanged = false

        for block in blocks {
            switch block.kind {
            case .lyrics:
                project.lyrics = block.content
            case .title:
                project.title = block.content.components(separatedBy: .newlines).first?
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"“”#*")) ?? project.title
            case .sunoLyrics:
                project.sunoLyrics = block.content
            case .pos:
                project.soundPrompt = SunoPromptGenerator.hardTrim(block.content, limit: PromptDNAComposer.positiveLimit)
            case .neg:
                project.negativePrompt = SunoPromptGenerator.hardTrim(block.content, limit: PromptDNAComposer.negativeLimit)
            case .direction:
                dna.intent = mergeDirection(block.content, into: dna.intent)
                dnaChanged = true
            case .tags:
                let (found, missing) = await resolveTags(block.content)
                if !found.isEmpty {
                    dna.selectedTags = found
                    dna.anchorNames = dna.mode == .hybrid
                        ? SunoPromptGenerator.chooseAnchorNames(from: found, count: max(1, found.count / 4))
                        : []
                    dnaChanged = true
                    tagsChanged = true
                }
                if !missing.isEmpty {
                    result.notes.append("Not in the dataset, skipped: \(missing.joined(separator: ", "))")
                }
                if found.isEmpty { continue }
            }
            result.appliedKinds.append(block.kind)
        }

        if dnaChanged {
            project.promptDNA = dna
            let wroteOwnPrompt = blocks.contains { $0.kind == .pos }
            // Tags or direction changed: the dataset engine rewrites POS/NEG,
            // unless the writer asked the model to hand-write POS.
            if !wroteOwnPrompt, tagsChanged || !dna.selectedTags.isEmpty {
                let output = PromptDNAComposer.compose(dna)
                project.soundPrompt = output.positive
                project.negativePrompt = output.negative
                result.notes.append("POS/NEG regenerated by the dataset engine")
            }
            if let genre = dna.selectedTags.first(where: { $0.category == .genre || $0.category == .subgenre }) {
                project.genre = genre.name
            }
        }
        project.updatedAt = .now
        return result
    }

    /// Looks each suggested tag up in the 215,240-tag dataset. Exact
    /// (case-insensitive) matches first, then the best search hit.
    private static func resolveTags(_ content: String) async -> (found: [MusicTag], missing: [String]) {
        let database = TagDatabase.shared
        await database.loadIfNeeded()
        let names = content
            .components(separatedBy: CharacterSet(charactersIn: "\n,"))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -•*\t\"“”0123456789.)")) }
            .filter { !$0.isEmpty }

        var found: [MusicTag] = []
        var missing: [String] = []
        for name in names.prefix(10) {
            let lowered = name.lowercased()
            let match = database.allTags.first(where: { $0.name.lowercased() == lowered })
                ?? database.search(name, limit: 1).first
            if let match, !found.contains(where: { $0.id == match.id }) {
                found.append(match)
            } else if match == nil {
                missing.append(name)
            }
        }
        return (found, missing)
    }

    private static func mergeDirection(_ content: String, into intent: PromptIntent) -> PromptIntent {
        var intent = intent
        for line in content.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[1].isEmpty, parts[1] != "..." else { continue }
            let value = parts[1]
            switch parts[0].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "-* ")) {
            case "energy":
                intent.energy = EnergyLevel.allCases.first { $0.rawValue == value.lowercased() } ?? intent.energy
            case "vocals", "vocal": intent.vocals = value
            case "mood": intent.mood = value
            case "instrumentation", "instruments": intent.instrumentation = value
            case "production": intent.production = value
            case "mix", "mixing", "master": intent.mixing = value
            case "performance": intent.performance = value
            case "avoid": intent.avoid = value
            default: break
            }
        }
        return intent
    }
}
