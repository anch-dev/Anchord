import Foundation

struct PromptDNA: Codable, Hashable, Sendable {
    var genres: [String] = []
    var vocalStyle: [String] = []
    var instrumentation: [String] = []
    var rhythm: [String] = []
    var production: [String] = []
    var mood: [String] = []

    var allTags: [String] {
        genres + vocalStyle + instrumentation + rhythm + production + mood
    }
}
