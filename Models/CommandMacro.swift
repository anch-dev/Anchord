import Foundation

/// A reusable chat command: typing `/hook dark and slow` sends the
/// macro's template with `{input}` replaced by "dark and slow".
///
/// Placeholders: {input} {title} {genre} {lyrics} {tags} {pos} {neg}.
/// If the template has no {input}, the typed text is appended.
struct CommandMacro: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    /// Typed after "/", lowercase, no spaces.
    var trigger: String
    var title: String
    var template: String

    static let placeholders = ["{input}", "{title}", "{genre}", "{lyrics}", "{tags}", "{pos}", "{neg}"]

    static let builtIns: [CommandMacro] = [
        CommandMacro(trigger: "verse", title: "Write a verse",
                     template: "Write the next verse. Match the existing syllable counts per line and rhyme scheme, keep my voice, and return the complete lyrics. {input}"),
        CommandMacro(trigger: "chorus", title: "Write a chorus",
                     template: "Write a chorus that lands the song's central idea in a short, repeatable hook with strong end rhymes. Return the complete lyrics with the chorus placed where it belongs. {input}"),
        CommandMacro(trigger: "hook", title: "Hook ideas",
                     template: "Give me five hook lines for this song, each with a different rhythmic shape, and say which one you'd pick. Don't change the song yet. {input}"),
        CommandMacro(trigger: "punchup", title: "Punch up weak lines",
                     template: "Find the three weakest lines and rewrite them, keeping each line's syllable count and rhyme. Return the complete lyrics. {input}"),
        CommandMacro(trigger: "fusion", title: "Build a fusion",
                     template: "Pick 5 to 7 real Suno style tags that fit these lyrics and set the direction (energy, vocals, mood, production). {input}"),
        CommandMacro(trigger: "suno", title: "Format for Suno",
                     template: "Format the lyrics for Suno with [Section] tags and a few short performance cues where they help. {input}"),
        CommandMacro(trigger: "title", title: "Title the song",
                     template: "Suggest five titles drawn from the lyrics' strongest image or hook, then set the best one. {input}"),
        CommandMacro(trigger: "rhymes", title: "Rhyme options",
                     template: "List perfect rhymes, slant rhymes and multisyllabic rhymes for: {input}. Group them, no song changes."),
        CommandMacro(trigger: "full", title: "Fill every tab",
                     template: "Using the lyrics and any direction so far, fill everything: title, fusion tags, direction, and Suno-formatted lyrics. {input}"),
    ]

    @MainActor
    func expand(input: String, project: SongProject) -> String {
        let dna = project.promptDNA
        let values: [String: String] = [
            "{title}": project.title,
            "{genre}": project.genre,
            "{lyrics}": project.lyrics,
            "{tags}": dna.allTagNames.joined(separator: ", "),
            "{pos}": project.soundPrompt,
            "{neg}": project.negativePrompt,
        ]
        var text = template
        for (key, value) in values { text = text.replacingOccurrences(of: key, with: value) }
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("{input}") {
            text = text.replacingOccurrences(of: "{input}", with: trimmedInput)
        } else if !trimmedInput.isEmpty {
            text += " " + trimmedInput
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedTrigger(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

/// The writer's macros (built-ins plus their own), persisted locally.
@MainActor
final class CommandMacroStore: ObservableObject {
    static let shared = CommandMacroStore()

    @Published var macros: [CommandMacro] {
        didSet { save() }
    }

    private static let key = "anchord.commandMacros"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([CommandMacro].self, from: data) {
            macros = decoded
        } else {
            macros = CommandMacro.builtIns
        }
    }

    func macro(for trigger: String) -> CommandMacro? {
        let t = CommandMacro.normalizedTrigger(trigger)
        return macros.first { $0.trigger == t }
    }

    /// Macros whose trigger starts with what's typed after "/".
    func suggestions(for typed: String) -> [CommandMacro] {
        let t = CommandMacro.normalizedTrigger(typed)
        return t.isEmpty ? macros : macros.filter { $0.trigger.hasPrefix(t) }
    }

    /// "/hook dark and slow" → expanded prompt; nil if not a known macro.
    func expand(_ message: String, project: SongProject) -> String? {
        guard message.hasPrefix("/") else { return nil }
        let body = message.dropFirst()
        let trigger = body.prefix { !$0.isWhitespace }
        guard let macro = macro(for: String(trigger)) else { return nil }
        let input = String(body.dropFirst(trigger.count))
        return macro.expand(input: input, project: project)
    }

    func restoreBuiltIns() {
        let existing = Set(macros.map(\.trigger))
        macros.append(contentsOf: CommandMacro.builtIns.filter { !existing.contains($0.trigger) })
    }

    private func save() {
        if let data = try? JSONEncoder().encode(macros) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
