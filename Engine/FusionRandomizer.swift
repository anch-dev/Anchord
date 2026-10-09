import Foundation

/// Rarity presets for the fusion randomizer. Each maps to a starting
/// slider position; the slider itself (0...100) is the real continuous
/// control, same relationship as the original web prototype.
enum RarityMode: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case pure
    case rare
    case veryRare
    case balanced
    case weird

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pure: "Pure Random"
        case .rare: "Rare"
        case .veryRare: "Very Rare"
        case .balanced: "Balanced"
        case .weird: "Weird / Experimental"
        }
    }

    var defaultSlider: Double {
        switch self {
        case .pure: 0
        case .rare: 70
        case .veryRare: 92
        case .balanced: 30
        case .weird: 88
        }
    }
}

/// Selects tags from the dataset with rarity bias and optional
/// category-balance constraints. Pure functions over `[MusicTag]` --
/// no dependency on `TagDatabase` itself, so this stays independently
/// testable.
enum FusionRandomizer {

    static func rarityBand(forSlider slider: Double) -> String {
        switch slider {
        case ..<15: "No rarity bias — any tag may appear"
        case ..<40: "Mildly favoring less common tags"
        case ..<65: "Prioritizing tags appearing in roughly 1–100 songs"
        case ..<85: "Prioritizing tags appearing in roughly 1–25 songs"
        default: "Prioritizing tags appearing in only 1–5 songs"
        }
    }

    /// 0 at slider=0 (uniform/no bias) up to ~2.3 at slider=100 (sharp bias).
    static func weightPower(forSlider slider: Double) -> Double {
        (slider / 100) * 2.3
    }

    private static func weirdCategoryBonus(_ category: TagCategory) -> Double {
        switch category {
        case .other: 1.6
        case .mood: 1.3
        case .electronic: 1.25
        case .technique: 1.4
        case .form: 1.3
        case .rhythm: 1.15
        default: 1.0
        }
    }

    /// Weighted sampling without replacement via the exponential-key
    /// (A-ExpJ) trick: key = -ln(rand) / weight, take the N smallest keys.
    /// O(n log n) on the filtered pool, which is what makes this cheap
    /// enough to re-run on every tap even over the full dataset.
    static func weightedSample(
        from pool: [MusicTag],
        count: Int,
        power: Double,
        weirdBoost: Bool = false
    ) -> [MusicTag] {
        guard !pool.isEmpty, count > 0 else { return [] }
        let keyed: [(tag: MusicTag, key: Double)] = pool.map { tag in
            var weight = 1.0 / pow(Double(max(tag.count, 1)), power)
            if weirdBoost { weight *= weirdCategoryBonus(tag.category) }
            let r = max(Double.random(in: 0..<1), 1e-9)
            let key = -log(r) / max(weight, 1e-12)
            return (tag, key)
        }
        return Array(keyed.sorted { $0.key < $1.key }.prefix(count).map(\.tag))
    }

    private static func dedupedByName(_ tags: [MusicTag]) -> [MusicTag] {
        var seen = Set<String>()
        var out: [MusicTag] = []
        for tag in tags {
            let key = tag.name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(tag)
        }
        return out
    }

    /// Plain weighted draw across the whole enabled pool.
    static func simpleFusion(
        pool: [MusicTag],
        count: Int,
        power: Double,
        weirdBoost: Bool
    ) -> [MusicTag] {
        let oversampled = weightedSample(from: pool, count: count * 2, power: power, weirdBoost: weirdBoost)
        return Array(dedupedByName(oversampled).prefix(count))
    }

    /// Guarantees at least `minCategories` distinct categories are
    /// represented among the result, then fills remaining slots from the
    /// full pool. Mirrors the web prototype's category-balanced mode.
    static func categoryBalancedFusion(
        tagsByCategory: [TagCategory: [MusicTag]],
        enabledCategories: Set<TagCategory>,
        tagCount: Int,
        minCategories: Int,
        power: Double,
        weirdBoost: Bool
    ) -> [MusicTag] {
        let eligible = enabledCategories.filter { !(tagsByCategory[$0] ?? []).isEmpty }
        guard !eligible.isEmpty else { return [] }
        let minCats = min(minCategories, eligible.count, tagCount)

        let chosenCategories = Array(eligible.shuffled().prefix(minCats))
        var result: [MusicTag] = []
        var usedNames = Set<String>()

        for category in chosenCategories {
            let candidates = weightedSample(from: tagsByCategory[category] ?? [], count: 3, power: power, weirdBoost: weirdBoost)
            if let pick = candidates.first(where: { !usedNames.contains($0.name.lowercased()) }) {
                result.append(pick)
                usedNames.insert(pick.name.lowercased())
            }
        }

        let fullPool = eligible.reduce(into: [MusicTag]()) { $0.append(contentsOf: tagsByCategory[$1] ?? []) }
        var guardCount = 0
        while result.count < tagCount, guardCount < 40 {
            guardCount += 1
            let extra = weightedSample(from: fullPool, count: tagCount, power: power, weirdBoost: weirdBoost)
            for tag in extra {
                if result.count >= tagCount { break }
                let key = tag.name.lowercased()
                if !usedNames.contains(key) {
                    result.append(tag)
                    usedNames.insert(key)
                }
            }
        }
        return Array(result.prefix(tagCount))
    }
}
