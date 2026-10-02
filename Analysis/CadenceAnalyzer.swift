import Foundation

struct LineAnalysis: Identifiable, Hashable, Sendable {
    let id = UUID()
    let text: String
    let syllableCount: Int
    let words: [String]
}

struct CadenceAnalyzer {
    func analyze(_ lyrics: String) -> [LineAnalysis] {
        lyrics
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                let text = String(line).trimmingCharacters(in: .whitespaces)
                let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                return LineAnalysis(
                    text: text,
                    syllableCount: words.reduce(0) { $0 + estimateSyllables(in: $1) },
                    words: words
                )
            }
    }

    private func estimateSyllables(in word: String) -> Int {
        let normalized = word
            .lowercased()
            .filter { $0.isLetter }

        guard !normalized.isEmpty else { return 0 }
        if normalized.count <= 3 { return 1 }

        let vowels = Set("aeiouy")
        var count = 0
        var previousWasVowel = false

        for character in normalized {
            let isVowel = vowels.contains(character)
            if isVowel && !previousWasVowel {
                count += 1
            }
            previousWasVowel = isVowel
        }

        if normalized.hasSuffix("e"), count > 1 {
            count -= 1
        }

        return max(1, count)
    }
}
