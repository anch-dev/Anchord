import Foundation

/// Loads the dataset mined from 659,788 Suno songs (bundled as
/// `MusicTags.tsv`: one `name\tcount\tcategory` row per tag, already
/// cleaned of conservative garbage and corrected for common spelling
/// typos) into memory once, and indexes it by category.
///
/// This is the native equivalent of the original web prototype's
/// `parseTags()` + `CAT_POOLS` setup -- same data, same format, loaded
/// from a bundled resource instead of an inlined JS string so a native
/// app can ship it properly instead of embedding a multi-megabyte
/// source-code literal.
@MainActor
final class TagDatabase: ObservableObject {
    static let shared = TagDatabase()

    @Published private(set) var isLoaded = false
    @Published private(set) var loadError: String?

    private(set) var allTags: [MusicTag] = []
    private(set) var tagsByCategory: [TagCategory: [MusicTag]] = [:]

    var totalSongs: Int { 659_788 }

    private init() {}

    /// Safe to call repeatedly; only parses once.
    func loadIfNeeded() async {
        guard !isLoaded else { return }
        let result = await Task.detached(priority: .userInitiated) {
            Self.parseBundledResource()
        }.value

        switch result {
        case .success(let tags):
            allTags = tags
            tagsByCategory = Dictionary(grouping: tags, by: \.category)
            isLoaded = true
        case .failure(let error):
            loadError = error.errorDescription
        }
    }

    func pool(for categories: Set<TagCategory>) -> [MusicTag] {
        categories.reduce(into: [MusicTag]()) { partial, category in
            partial.append(contentsOf: tagsByCategory[category] ?? [])
        }
    }

    func search(_ query: String, limit: Int = 100) -> [MusicTag] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        var startsWith: [MusicTag] = []
        var contains: [MusicTag] = []
        for tag in allTags {
            let lowered = tag.name.lowercased()
            if lowered == needle {
                startsWith.insert(tag, at: 0)
            } else if lowered.hasPrefix(needle) {
                startsWith.append(tag)
            } else if lowered.contains(needle) {
                contains.append(tag)
                if contains.count > 2000 { break } // bound the scan cost
            }
        }
        return Array((startsWith + contains).prefix(limit))
    }

    // MARK: - Resource parsing

    private enum LoadError: LocalizedError, Sendable {
        case resourceMissing
        case unreadable

        var errorDescription: String? {
            switch self {
            case .resourceMissing: "MusicTags.tsv was not found in the app bundle."
            case .unreadable: "MusicTags.tsv could not be read as UTF-8 text."
            }
        }
    }

    private nonisolated static func parseBundledResource() -> Result<[MusicTag], LoadError> {
        guard let url = Bundle.main.url(forResource: "MusicTags", withExtension: "tsv") else {
            return .failure(LoadError.resourceMissing)
        }
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return .failure(LoadError.unreadable)
        }

        var result: [MusicTag] = []
        result.reserveCapacity(220_000)

        content.enumerateLines { line, _ in
            guard !line.isEmpty else { return }
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let count = Int(parts[1]),
                  let category = TagCategory(rawValue: String(parts[2])) else { return }
            result.append(MusicTag(name: String(parts[0]), count: count, category: category))
        }
        return .success(result)
    }
}
