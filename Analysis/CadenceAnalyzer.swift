import Foundation

/// Per-line cadence measurements. `id` is the line's index among the
/// song's lyric lines, so it's stable across re-analysis while typing.
struct LineAnalysis: Identifiable, Hashable, Sendable {
    let id: Int
    let text: String
    let words: [String]
    let syllableCount: Int
    /// Estimated stress, one mark per syllable: `/` stressed, `x` not.
    let stressPattern: String
    /// Rhyming tail of the last word (see `PhoneticEngine.rhymeTail`).
    let endRhymeTail: String
    /// End-rhyme scheme letter within the stanza ("A", "B"…); nil when
    /// the line's ending rhymes with nothing nearby.
    var rhymeLetter: String?
    /// How the line's ending matches its scheme partner.
    var rhymeKind: PhoneticEngine.RhymeKind?
    /// Word pairs inside the line whose endings rhyme.
    let internalRhymes: [InternalRhyme]
    /// Index of the stanza this line belongs to.
    let stanza: Int
    /// Syllables above (+) or below (−) the stanza's average.
    var deviation: Double = 0
    /// Writer-banned words/phrases found in the line.
    var bannedTerms: [String] = []
    /// Stock clichés found in the line (when cliché flagging is on).
    var cliches: [String] = []
    /// Outside the writer's per-line syllable target, if one is set.
    var isOutsideTarget: Bool = false

    var hasPreferenceIssues: Bool { !bannedTerms.isEmpty || !cliches.isEmpty || isOutsideTarget }

    /// Lines this far from their stanza's average likely fall out of the
    /// pocket when sung over the same melody.
    var isOutOfPocket: Bool { abs(deviation) >= 3 }
}

struct InternalRhyme: Hashable, Sendable {
    let first: String
    let second: String
    let kind: PhoneticEngine.RhymeKind
}

struct StanzaSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let label: String?
    let lineCount: Int
    let averageSyllables: Double
    let minSyllables: Int
    let maxSyllables: Int
    /// e.g. "AABB", "ABAB", with "x" for lines that rhyme with nothing.
    let scheme: String
}

struct LyricAnalysis: Sendable {
    var lines: [LineAnalysis]
    var stanzas: [StanzaSummary]

    static let empty = LyricAnalysis(lines: [], stanzas: [])

    var totalSyllables: Int { lines.reduce(0) { $0 + $1.syllableCount } }
    var outOfPocketLines: [LineAnalysis] { lines.filter { $0.isOutOfPocket || $0.isOutsideTarget } }
    var bannedHits: [LineAnalysis] { lines.filter { !$0.bannedTerms.isEmpty } }
    var clicheHits: [LineAnalysis] { lines.filter { !$0.cliches.isEmpty } }

    /// Compact deterministic summary handed to AI providers as
    /// constraints, so rewrites/analysis start from measured facts.
    var constraintSummary: String {
        lines.map { line in
            var s = "L\(line.id + 1) (\(line.syllableCount) syl, stress \(line.stressPattern)"
            if let letter = line.rhymeLetter { s += ", rhyme \(letter)" }
            return s + "): \(line.text)"
        }.joined(separator: "\n")
    }
}

/// Deterministic cadence/rhyme analysis built on `PhoneticEngine`.
/// Measurements here are estimates from spelling (see that type's notes);
/// AI features treat them as constraints rather than replacing them.
struct CadenceAnalyzer {
    /// The writer's rules; banned words, clichés and the syllable target
    /// are flagged per line.
    var preferences = LyricPreferences()

    /// Back-compat entry point used by quick syllable chips.
    func analyze(_ lyrics: String) -> [LineAnalysis] {
        analyzeSong(lyrics).lines
    }

    func analyzeSong(_ lyrics: String) -> LyricAnalysis {
        // Split into stanzas on blank lines or [Section] tags.
        var stanzas: [(label: String?, lines: [String])] = []
        var currentLabel: String?
        var current: [String] = []

        func flush() {
            if !current.isEmpty { stanzas.append((currentLabel, current)) }
            current = []
        }

        for raw in lyrics.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
                currentLabel = nil
            } else if SunoLyricsFormatter.isTagLine(line) {
                flush()
                currentLabel = String(line.dropFirst().dropLast())
            } else {
                current.append(line)
            }
        }
        flush()

        var lines: [LineAnalysis] = []
        var summaries: [StanzaSummary] = []

        for (stanzaIndex, stanza) in stanzas.enumerated() {
            let firstIndex = lines.count
            for text in stanza.lines {
                lines.append(measure(text, index: lines.count, stanza: stanzaIndex))
            }
            let range = firstIndex..<lines.count
            assignRhymeScheme(&lines, range: range)

            let counts = range.map { lines[$0].syllableCount }
            let average = Double(counts.reduce(0, +)) / Double(max(counts.count, 1))
            for i in range {
                lines[i].deviation = Double(lines[i].syllableCount) - average
                lines[i].bannedTerms = preferences.bannedTerms(in: lines[i].text)
                lines[i].cliches = preferences.clichesFound(in: lines[i].text)
                if preferences.targetSyllablesEnabled {
                    let count = lines[i].syllableCount
                    lines[i].isOutsideTarget = count < preferences.targetSyllablesMin || count > preferences.targetSyllablesMax
                }
            }

            summaries.append(StanzaSummary(
                id: stanzaIndex,
                label: stanza.label,
                lineCount: counts.count,
                averageSyllables: average,
                minSyllables: counts.min() ?? 0,
                maxSyllables: counts.max() ?? 0,
                scheme: range.map { lines[$0].rhymeLetter ?? "x" }.joined()
            ))
        }
        return LyricAnalysis(lines: lines, stanzas: summaries)
    }

    private func measure(_ text: String, index: Int, stanza: Int) -> LineAnalysis {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let cleanWords = words.filter { !PhoneticEngine.letters($0).isEmpty }
        let last = cleanWords.last ?? ""

        var internalPairs: [InternalRhyme] = []
        let candidates = cleanWords.dropLast().filter { PhoneticEngine.letters($0).count >= 3 }
        for (i, a) in candidates.enumerated() {
            for b in candidates.dropFirst(i + 1) + [last] {
                if let kind = PhoneticEngine.rhyme(a, b), kind == .perfect {
                    internalPairs.append(InternalRhyme(first: a, second: b, kind: kind))
                }
            }
        }

        return LineAnalysis(
            id: index,
            text: text,
            words: words,
            syllableCount: cleanWords.reduce(0) { $0 + PhoneticEngine.syllableCount($1) },
            stressPattern: cleanWords.map(PhoneticEngine.stressPattern).joined(separator: " "),
            endRhymeTail: PhoneticEngine.rhymeTail(last),
            rhymeLetter: nil,
            rhymeKind: nil,
            internalRhymes: Array(internalPairs.prefix(4)),
            stanza: stanza
        )
    }

    /// Greedy scheme letters: each line takes the letter of the nearest
    /// earlier line it rhymes with (perfect preferred over slant), or a
    /// new letter if a later line rhymes with it.
    private func assignRhymeScheme(_ lines: inout [LineAnalysis], range: Range<Int>) {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
        var nextLetter = 0
        let lastWords = range.map { i in
            lines[i].words.last(where: { !PhoneticEngine.letters($0).isEmpty }) ?? ""
        }

        for (offset, i) in range.enumerated() {
            var best: (letter: String, kind: PhoneticEngine.RhymeKind)?
            for prior in stride(from: offset - 1, through: 0, by: -1) {
                guard let letter = lines[range.lowerBound + prior].rhymeLetter,
                      let kind = PhoneticEngine.rhyme(lastWords[offset], lastWords[prior]),
                      kind != .consonance else { continue }
                if best == nil || (kind == .perfect && best?.kind != .perfect) {
                    best = (letter, kind)
                }
                if kind == .perfect { break }
            }
            if let best {
                lines[i].rhymeLetter = best.letter
                lines[i].rhymeKind = best.kind
                continue
            }
            let laterMatch = (offset + 1..<range.count).contains { later in
                guard let kind = PhoneticEngine.rhyme(lastWords[offset], lastWords[later]) else { return false }
                return kind != .consonance
            }
            if laterMatch, nextLetter < alphabet.count {
                lines[i].rhymeLetter = alphabet[nextLetter]
                nextLetter += 1
            }
        }
    }
}
