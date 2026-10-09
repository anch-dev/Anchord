import Foundation

/// The 12-category taxonomy used when the Suno dataset (659,788 songs,
/// 215,240 cleaned tags after spelling correction) was mined and classified.
/// Single-letter raw values match the category codes stored in the bundled
/// `MusicTags.tsv` resource, so decoding stays a direct lookup.
enum TagCategory: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case genre = "G"
    case subgenre = "S"
    case regional = "C"
    case instrument = "I"
    case vocal = "V"
    case rhythm = "R"
    case production = "P"
    case form = "F"
    case technique = "T"
    case mood = "M"
    case electronic = "E"
    case other = "O"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .genre: "Genre"
        case .subgenre: "Subgenre"
        case .regional: "Regional/Cultural"
        case .instrument: "Instrument"
        case .vocal: "Vocal"
        case .rhythm: "Rhythm"
        case .production: "Production"
        case .form: "Composition/Form"
        case .technique: "Performance Technique"
        case .mood: "Mood/Aesthetic"
        case .electronic: "Electronic/Digital"
        case .other: "Other"
        }
    }

    /// SF Symbol used in chips/rows throughout the fusion builder UI.
    var symbolName: String {
        switch self {
        case .genre: "guitars"
        case .subgenre: "guitars.fill"
        case .regional: "globe"
        case .instrument: "pianokeys"
        case .vocal: "mic"
        case .rhythm: "metronome"
        case .production: "slider.horizontal.3"
        case .form: "doc.text"
        case .technique: "hand.draw"
        case .mood: "cloud.moon"
        case .electronic: "bolt"
        case .other: "questionmark.circle"
        }
    }

    /// Whether this category is included by default when a new fusion
    /// selection is created. "Other" is a noisy catch-all (typo fragments,
    /// unclassifiable phrases) so it starts disabled, same default as the
    /// original web prototype.
    var enabledByDefault: Bool { self != .other }
}

/// A single tag mined from the dataset, with its real song-level frequency
/// and classified category. `count` is the number of distinct songs (out of
/// 659,788) whose `metadata_tags` field contained this tag at least once.
struct MusicTag: Identifiable, Hashable, Codable, Sendable {
    var name: String
    var count: Int
    var category: TagCategory

    var id: String { name.lowercased() }

    var songCountDescription: String {
        count == 1 ? "1 song" : "\(count) songs"
    }
}
