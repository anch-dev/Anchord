import Foundation

/// The musical function a tag plays when woven into a generated prompt.
/// Every tag gets assigned one of these -- by category by default, or by
/// a curated override for a handful of landmark tags the dataset mining
/// surfaced (Chaconne, Ondioline, Guaguancó, etc).
enum MusicalRole: String, CaseIterable, Hashable, Sendable {
    case rhythm, harmony, instrumentation, vocal, production
    case atmosphere, technique, texture, genre, arrangement
}

/// Central role-assignment and phrasing system for the Suno prompt
/// generator. This is a direct port of the web prototype's role engine:
/// same category→role mapping, same curated landmark-tag descriptions,
/// same phrase banks, same chaos-rotation mechanic. Keeping it faithful
/// here is the point -- this *is* "the existing Suno dataset prompt
/// maker," just running natively instead of in a web view.
enum PromptRoleEngine {

    static let categoryRole: [TagCategory: MusicalRole] = [
        .rhythm: .rhythm, .regional: .rhythm,
        .genre: .genre, .subgenre: .genre,
        .instrument: .instrumentation,
        .vocal: .vocal,
        .production: .production, .electronic: .production,
        .form: .harmony,
        .technique: .technique,
        .mood: .atmosphere,
        .other: .texture,
    ]

    /// Hand-written musical framing for the landmark tags the dataset
    /// mining work surfaced, so they read with real specificity rather
    /// than generic category text. Everything else in the 215k-tag
    /// database falls through to the general role/phrase-bank system --
    /// this is deliberately a small, curated set, not an attempt to
    /// hand-classify the whole dataset.
    static let specialRoles: [String: (role: MusicalRole, description: String)] = [
        "chaconne": (.harmony, "Chaconne's repeating harmonic ground, with the rest of the material built over it"),
        "ondioline": (.instrumentation, "the Ondioline's vintage electronic lead timbre"),
        "guaguanco": (.rhythm, "Guaguancó's clave-locked Afro-Cuban rhythmic foundation"),
        "guaguancó": (.rhythm, "Guaguancó's clave-locked Afro-Cuban rhythmic foundation"),
        "eccojams": (.production, "an Eccojams-style chopped, pitched-down tape-loop treatment"),
        "sacred harp singing": (.vocal, "raw, unaccompanied Sacred Harp shape-note vocal harmony"),
        "liminal space": (.atmosphere, "a hollow, suspended Liminal Space atmosphere"),
        "extended technique": (.technique, "unconventional Extended Technique instrumental performance"),
        "chaabi": (.genre, "Chaabi's oud-and-banjo, derbouka-driven genre ecosystem with call-and-response vocals"),
        "plainchant": (.harmony, "Plainchant's modal, unmetered vocal line"),
        "motet": (.harmony, "Motet-style sacred polyphony"),
        "demoscene": (.texture, "chiptune-adjacent Demoscene digital texture"),
        "tribal ambient": (.atmosphere, "Tribal Ambient's drone-and-percussion atmosphere"),
        "black ambient": (.atmosphere, "Black Ambient's dissonant, dark atmosphere"),
        "seapunk": (.production, "Seapunk's glitchy, retro-synth production aesthetic"),
        "streetpunk": (.genre, "Street Punk's gang-vocal, working-class identity"),
        "emoviolence": (.genre, "Emoviolence's fusion of emo melodicism and powerviolence intensity"),
        "makossa": (.rhythm, "Makossa's syncopated Cameroonian dance groove"),
    ]

    /// Noun-phrase bank per role. A plain function (switch) rather than a
    /// dictionary of closures: static stored closures are non-Sendable
    /// global state under Swift 6 strict concurrency, and this is just as
    /// readable while being trivially concurrency-safe.
    static func nounPhrases(for role: MusicalRole, name n: String) -> [String] {
        switch role {
        case .rhythm: ["a rhythmic foundation built from \(n)", "\(n)'s pulse and groove", "the rhythmic language of \(n)"]
        case .harmony: ["a harmonic ground drawn from \(n)", "\(n)'s harmonic vocabulary", "harmonic motion shaped by \(n)"]
        case .instrumentation: ["\(n) as the core instrumentation", "\(n)'s timbral character", "instrumentation centered on \(n)"]
        case .vocal: ["vocal character shaped by \(n)", "a vocal delivery rooted in \(n)", "\(n)'s vocal approach"]
        case .production: ["a \(n) production treatment", "\(n)'s sonic processing", "production shaped by \(n)"]
        case .atmosphere: ["an atmosphere colored by \(n)", "\(n)'s spatial character", "a mood drawn from \(n)"]
        case .technique: ["\(n) as a performance technique", "playing technique borrowed from \(n)", "\(n)'s performance language"]
        case .texture: ["textural color from \(n)", "\(n) as a textural layer", "\(n)'s sonic texture"]
        case .genre: ["\(n)'s stylistic identity", "\(n) as the genre backbone", "the \(n) identity"]
        case .arrangement: ["an arrangement logic borrowed from \(n)", "\(n)'s structural approach", "structural behavior shaped by \(n)"]
        }
    }

    static let transitionByRole: [MusicalRole: [String]] = [
        .rhythm: ["rhythmically reinterpreted into", "its pulse recast as", "metrically modulated into"],
        .harmony: ["reharmonized through modal interchange into", "its harmony recontextualized as", "carried forward by a pivot chord into"],
        .instrumentation: ["timbrally transformed into", "with instrumentation migrating into", "its timbral material becoming"],
        .vocal: ["its melodic contour becoming", "reinterpreted vocally as", "the vocal character shifting into"],
        .production: ["the production treatment mutating into", "sonically reworked into", "reprocessed into"],
        .atmosphere: ["the atmosphere dissolving into", "its mood recontextualized as", "opening out into"],
        .technique: ["reinterpreted through the performance language of", "recast using"],
        .texture: ["its textural material becoming", "layered against"],
        .genre: ["gradually transforming into", "migrating into", "evolving into"],
        .arrangement: ["restructured into", "its arrangement logic reframed as"],
    ]

    /// One rotation offset applies to an entire generation (not per-tag),
    /// so a chaos-mode run feels like a deliberate, consistent reassignment
    /// of functions rather than noise -- e.g. every tag's role shifted by
    /// the same number of steps through `MusicalRole.allCases`.
    static func chaosRotation() -> Int {
        1 + Int.random(in: 0..<(MusicalRole.allCases.count - 1))
    }

    static func role(for tag: MusicTag, chaos: Bool, rotation: Int) -> MusicalRole {
        let natural = specialRoles[tag.name.lowercased()]?.role ?? (categoryRole[tag.category] ?? .texture)
        guard chaos, rotation != 0 else { return natural }
        let all = MusicalRole.allCases
        guard let idx = all.firstIndex(of: natural) else { return natural }
        let newIndex = (idx + rotation) % all.count
        return all[(newIndex + all.count) % all.count]
    }

    /// The descriptive noun phrase for a tag given its (possibly
    /// chaos-rotated) role. Falls through to the general phrase bank once
    /// chaos has moved a landmark tag off its curated role, so the
    /// "surprising relationship" is actually audible in the wording
    /// rather than masked by the hand-written description.
    static func fragment(for tag: MusicTag, chaos: Bool, rotation: Int) -> String {
        let assignedRole = role(for: tag, chaos: chaos, rotation: rotation)
        if let special = specialRoles[tag.name.lowercased()], assignedRole == special.role {
            return special.description
        }
        return nounPhrases(for: assignedRole, name: tag.name).randomElement() ?? tag.name
    }

    static func transition(for role: MusicalRole) -> String {
        (transitionByRole[role] ?? transitionByRole[.genre]!).randomElement() ?? "transforming into"
    }

    static func joinNatural(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return "\(items.dropLast().joined(separator: ", ")), and \(items.last!)"
        }
    }
}
