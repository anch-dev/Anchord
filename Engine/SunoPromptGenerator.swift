import Foundation

/// A fusion's generation mode. Each case has its own linguistic
/// architecture -- these are not the same template with different
/// headings, per the product requirement that all four must produce
/// genuinely different prompts from identical tag selections.
enum FusionMode: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case blended
    case evolution
    case hybrid
    case sectioned

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blended: "Blended"
        case .evolution: "Evolution"
        case .hybrid: "Hybrid"
        case .sectioned: "Sectioned"
        }
    }

    var hint: String {
        switch self {
        case .blended: "All selected tags blend into one coherent identity."
        case .evolution: "Tags become a chronological transformation, A → B → C…"
        case .hybrid: "Anchor tags stay constant while the rest mutate around them."
        case .sectioned: "Each tag gets its own distinct section — no blending, clean cuts between parts."
        }
    }
}

/// Runtime options that affect generation without being part of the
/// fusion's persisted identity (tag selection + mode are what's saved;
/// chaos and song length are generation-time knobs).
struct PromptGenerationOptions: Sendable {
    var chaos: Bool = false
    var songLengthSeconds: Int = 240
}

enum SunoPromptGenerator {

    // MARK: - Ordering & anchor selection

    /// Loose narrative ordering for Evolution/Sectioned: rhythm/regional
    /// roots first, then harmonic/compositional material, then
    /// instrumentation & vocal character, then production/mood/technique
    /// coloring, closing on genre identity.
    private static let sequenceOrder: [TagCategory: Int] = [
        .rhythm: 0, .regional: 1, .form: 2, .instrument: 3, .vocal: 4,
        .technique: 5, .production: 6, .electronic: 7, .mood: 8,
        .subgenre: 9, .genre: 10, .other: 11,
    ]

    static func orderedForSequence(_ tags: [MusicTag]) -> [MusicTag] {
        tags.sorted { (sequenceOrder[$0.category] ?? 11) < (sequenceOrder[$1.category] ?? 11) }
    }

    /// Category priority for Hybrid-mode anchors: rhythm/genre/instrument/
    /// vocal identity is what a listener locks onto as "the constant";
    /// production/mood/technique/electronic reads as more naturally
    /// variable. This chooses anchors by category, not array position.
    private static let anchorPriority: [TagCategory: Int] = [
        .rhythm: 0, .genre: 1, .subgenre: 2, .regional: 3, .instrument: 4,
        .vocal: 5, .form: 6, .technique: 7, .production: 8, .mood: 9,
        .electronic: 10, .other: 11,
    ]

    /// Returns the same tags with `anchor` flags set on the
    /// highest-priority `count` of them. Pass the result's indices back
    /// into your selection model; this function doesn't mutate anything
    /// external, it just tells you which ones should be anchors.
    static func chooseAnchorNames(from tags: [MusicTag], count: Int) -> Set<String> {
        let sorted = tags.sorted { (anchorPriority[$0.category] ?? 11) < (anchorPriority[$1.category] ?? 11) }
        return Set(sorted.prefix(count).map { $0.name.lowercased() })
    }

    // MARK: - Per-mode prompt builders

    private static func buildBlended(_ tags: [MusicTag], chaos: Bool, rotation: Int) -> String {
        let names = tags.map(\.name)
        let roles = tags.map { PromptRoleEngine.role(for: $0, chaos: chaos, rotation: rotation) }
        var text = "A dense hybrid combining \(PromptRoleEngine.joinNatural(names)). "

        var clauses: [String] = []
        var usedIndices = Set<Int>()
        for role in MusicalRole.allCases {
            if clauses.count >= 4 { break }
            guard let idx = roles.firstIndex(of: role), !usedIndices.contains(idx) else { continue }
            usedIndices.insert(idx)
            clauses.append(PromptRoleEngine.nounPhrases(for: role, name: tags[idx].name).randomElement() ?? tags[idx].name)
        }

        text += clauses.isEmpty
            ? "Every element stays continuously present rather than taking turns."
            : "\(PromptRoleEngine.joinNatural(clauses)) all coexist throughout, none fully receding before the others resurface."
        return text
    }

    private static func buildEvolution(_ tags: [MusicTag], chaos: Bool, rotation: Int) -> String {
        guard let first = tags.first else { return "" }
        var text = "A single continuous composition transforming through distinct musical identities. It begins in "
        text += PromptRoleEngine.fragment(for: first, chaos: chaos, rotation: rotation)

        for tag in tags.dropFirst() {
            let role = PromptRoleEngine.role(for: tag, chaos: chaos, rotation: rotation)
            text += ", \(PromptRoleEngine.transition(for: role)) \(PromptRoleEngine.fragment(for: tag, chaos: chaos, rotation: rotation))"
        }
        text += ". A shared tone and recurring rhythmic cell carry across every shift, so each transformation is musically earned rather than a hard cut."
        return text
    }

    private static func buildHybrid(_ tags: [MusicTag], anchorNames: Set<String>, chaos: Bool, rotation: Int) -> String {
        let anchors = tags.filter { anchorNames.contains($0.name.lowercased()) }
        let rest = tags.filter { !anchorNames.contains($0.name.lowercased()) }
        let frag: (MusicTag) -> String = { PromptRoleEngine.fragment(for: $0, chaos: chaos, rotation: rotation) }

        let anchorList = anchors.isEmpty ? [frag(tags[0])] : anchors.map(frag)
        var text = "Maintain \(PromptRoleEngine.joinNatural(anchorList)) as the persistent identity throughout. "
        text += rest.isEmpty
            ? "Every other element reinterprets itself repeatedly around that fixed core."
            : "Around that constant, \(PromptRoleEngine.joinNatural(rest.map(frag))) take turns reinterpreting the surrounding musical language, each returning to the anchor's pulse and character before mutating again."
        return text
    }

    private static func fmtTime(_ seconds: Double) -> String {
        let m = Int(seconds / 60)
        let s = Int(seconds.truncatingRemainder(dividingBy: 60).rounded())
        return "\(m):\(String(format: "%02d", s))"
    }

    private static func buildSectioned(_ tags: [MusicTag], totalSeconds: Int, chaos: Bool, rotation: Int) -> String {
        let n = tags.count
        guard n > 0 else { return "" }
        let per = Double(totalSeconds) / Double(n)

        let richBits: [String] = tags.enumerated().map { i, tag in
            let start = fmtTime(Double(i) * per)
            let end = fmtTime(Double(i + 1) * per)
            let upper = tag.name.count <= 22 ? tag.name.uppercased() : tag.name
            let label = i == 0 ? "\(upper) FOUNDATION" : i == n - 1 ? "\(upper) RESOLUTION" : "\(upper) DEVELOPMENT"
            let body: String
            if i == 0 {
                body = "Establish \(PromptRoleEngine.fragment(for: tag, chaos: chaos, rotation: rotation))."
            } else {
                let role = PromptRoleEngine.role(for: tag, chaos: chaos, rotation: rotation)
                body = "Carrying the previous section's core forward, it is \(PromptRoleEngine.transition(for: role)) \(PromptRoleEngine.fragment(for: tag, chaos: chaos, rotation: rotation))."
            }
            return "[\(start)\u{2013}\(end) \u{2014} \(label)] \(body)"
        }
        let rich = richBits.joined(separator: " ").collapsedWhitespace()
        if rich.count <= 1000 { return rich }

        // Compact fallback -- timestamps are never dropped, only the
        // wording around them.
        let compactBits: [String] = tags.enumerated().map { i, tag in
            let start = fmtTime(Double(i) * per)
            let end = fmtTime(Double(i + 1) * per)
            if i == 0 {
                let role = PromptRoleEngine.role(for: tag, chaos: chaos, rotation: rotation)
                let noun = PromptRoleEngine.nounPhrases(for: role, name: tag.name).randomElement() ?? tag.name
                return "[\(start)\u{2013}\(end)] \(tag.name) establishes \(noun)."
            }
            let role = PromptRoleEngine.role(for: tag, chaos: chaos, rotation: rotation)
            return "[\(start)\u{2013}\(end)] \(PromptRoleEngine.transition(for: role)) \(tag.name)."
        }
        let compact = compactBits.joined(separator: " ").collapsedWhitespace()
        return compact.count <= 1000 ? compact : hardTrim(compact, limit: 1000)
    }

    // MARK: - Compression

    private static func hardTrim(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        var cut = String(text.prefix(limit - 1))
        let candidates = [". ", ", ", " "]
        var bestRange: Range<String.Index>?
        for sep in candidates {
            if let r = cut.range(of: sep, options: .backwards) {
                bestRange = r
                break
            }
        }
        if let r = bestRange, cut.distance(from: cut.startIndex, to: r.lowerBound) > Int(Double(limit) * 0.6) {
            cut = String(cut[cut.startIndex..<r.lowerBound])
        }
        while let last = cut.last, last == "," || last.isWhitespace {
            cut.removeLast()
        }
        return cut + "\u{2026}"
    }

    private static func compress(_ text: String, limit: Int) -> String {
        var s = text.collapsedWhitespace()
        guard s.count > limit else { return s }
        s = s
            .replacingOccurrences(of: ", none fully receding before the others resurface", with: "")
            .replacingOccurrences(of: " rather than a hard cut", with: "")
            .replacingOccurrences(of: " before mutating again", with: "")
            .collapsedWhitespace()
        return s.count <= limit ? s : hardTrim(s, limit: limit)
    }

    // MARK: - Public entry points

    static func generatePrompt(tags: [MusicTag], mode: FusionMode, anchorNames: Set<String>, options: PromptGenerationOptions) -> String {
        let rotation = options.chaos ? PromptRoleEngine.chaosRotation() : 0

        if mode == .sectioned {
            return buildSectioned(tags, totalSeconds: options.songLengthSeconds, chaos: options.chaos, rotation: rotation)
        }
        let raw: String
        switch mode {
        case .evolution: raw = buildEvolution(tags, chaos: options.chaos, rotation: rotation)
        case .hybrid: raw = buildHybrid(tags, anchorNames: anchorNames, chaos: options.chaos, rotation: rotation)
        case .blended, .sectioned: raw = buildBlended(tags, chaos: options.chaos, rotation: rotation)
        }
        return compress(raw, limit: 1000)
    }

    private static let negativeBase = [
        "generic", "mechanically looped", "robotic", "overly quantized",
        "tin-can sounding", "brittle", "sterile", "disconnected",
        "genre-parody-like", "generic EDM", "repetitive", "overcompressed",
        "muddy", "excessively reverberant",
    ]

    static func generateNegativePrompt(tags: [MusicTag], mode: FusionMode) -> String {
        var base = negativeBase
        var extras: [String] = []

        if mode == .sectioned {
            extras.append("no crossfading or bleeding between sections")
            extras.append("no sections that sound like unrelated tracks stitched with dead silence")
        } else {
            base.append(contentsOf: ["abrupt", "poorly transitioned"])
        }
        if mode == .evolution { extras.append("no abrupt jump cuts between sections") }
        if tags.contains(where: { $0.category == .vocal }) { extras.append("no robotic autotune-locked vocals") }
        if tags.contains(where: { $0.category == .electronic }) { extras.append("no generic festival-EDM drops") }
        if tags.contains(where: { $0.category == .instrument }) { extras.append("no MIDI-mockup instrument timbres") }

        let baseStr = "Avoid: \(base.joined(separator: ", "))."
        let full = extras.isEmpty ? baseStr : "\(baseStr) Specifically: \(extras.joined(separator: "; "))."
        return compress(full, limit: 400)
    }
}

private extension String {
    func collapsedWhitespace() -> String {
        self.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
