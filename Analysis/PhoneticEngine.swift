import Foundation

/// Spelling-based phonetic estimates for English lyric words.
///
/// This is deliberately honest about what it is: rules plus a small
/// exception list, not a pronunciation dictionary. It gets common lyric
/// vocabulary right and degrades gracefully on unusual words. A future
/// pass can back it with a real lexicon (e.g. CMUdict) behind the same
/// API without touching callers.
enum PhoneticEngine {

    // MARK: Normalization

    static func letters(_ word: String) -> String {
        String(word.lowercased().unicodeScalars.filter { CharacterSet.lowercaseLetters.contains($0) || $0 == "'" })
            .replacingOccurrences(of: "'", with: "")
    }

    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]

    private static func isVowel(_ c: Character, at index: Int, in chars: [Character]) -> Bool {
        if c == "y" {
            // Word-initial y ("you", "yeah") is a consonant.
            return index > 0
        }
        return vowels.contains(c)
    }

    // MARK: Syllables

    /// Common lyric words the rules get wrong. Values are the usual sung
    /// syllable count.
    private static let syllableExceptions: [String: Int] = [
        "the": 1, "fire": 1, "hour": 1, "our": 1, "flower": 2, "every": 2,
        "everything": 3, "everybody": 4, "everyone": 3, "heaven": 2, "being": 2,
        "people": 2, "really": 2, "beautiful": 3, "something": 2, "nothing": 2,
        "business": 2, "different": 2, "evening": 2, "family": 3, "forever": 3,
        "whatever": 3, "lion": 2, "quiet": 2, "science": 2, "poem": 2, "idea": 3,
        "area": 3, "radio": 3, "piano": 3, "video": 3, "create": 2, "alive": 2,
        "baby": 2, "maybe": 2, "lady": 2, "crazy": 2, "lazy": 2, "only": 2,
        "money": 2, "honey": 2, "wanna": 2, "gonna": 2, "gotta": 2,
        "oh": 1, "ooh": 1, "yeah": 1, "whoa": 1, "uh": 1, "ah": 1,
        "naive": 2, "chaos": 2, "real": 1, "dial": 1, "trial": 2, "denial": 3,
        "smile": 1, "while": 1, "fuel": 1, "cruel": 1, "jewel": 2,
    ]

    static func syllableCount(_ word: String) -> Int {
        let w = letters(word)
        guard !w.isEmpty else { return 0 }
        if let known = syllableExceptions[w] { return known }
        if w.count <= 3 { return 1 }

        let chars = Array(w)
        var count = 0
        var previousWasVowel = false
        for (i, c) in chars.enumerated() {
            let v = isVowel(c, at: i, in: chars)
            if v && !previousWasVowel { count += 1 }
            previousWasVowel = v
        }

        // Silent final e ("make", "love"), but not consonant+le ("table").
        if w.hasSuffix("e"), !w.hasSuffix("le") || isVowelBeforeLe(chars), !w.hasSuffix("ee"), count > 1 {
            count -= 1
        }
        // Silent -ed ("walked", "loved") unless after t/d ("wanted").
        if w.hasSuffix("ed"), chars.count > 3 {
            let before = chars[chars.count - 3]
            if before != "t", before != "d", !isVowel(before, at: chars.count - 3, in: chars), count > 1 {
                count -= 1
            }
        }
        // Silent -es after non-sibilants ("makes", "lines").
        if w.hasSuffix("es"), chars.count > 3 {
            let before = chars[chars.count - 3]
            let sibilant: Set<Character> = ["s", "x", "z", "c", "g", "h"]
            if !sibilant.contains(before), !isVowel(before, at: chars.count - 3, in: chars), count > 1 {
                count -= 1
            }
        }
        // Vowel pairs usually split across syllables ("ia", "io", "eo").
        for pair in ["ia", "io", "eo"] where w.contains(pair) && !w.hasSuffix("tion") && !w.hasSuffix("sion") {
            count += 1
        }
        return max(1, count)
    }

    private static func isVowelBeforeLe(_ chars: [Character]) -> Bool {
        guard chars.count >= 3 else { return false }
        return vowels.contains(chars[chars.count - 3])
    }

    // MARK: Stress

    /// Unstressed in running speech unless emphasized.
    static let functionWords: Set<String> = [
        "a", "an", "the", "and", "but", "or", "nor", "so", "yet", "of", "to", "in",
        "on", "at", "by", "for", "with", "from", "as", "is", "am", "are", "was",
        "were", "be", "been", "it", "its", "i", "me", "my", "you", "your", "he",
        "him", "his", "she", "her", "we", "us", "our", "they", "them", "their",
        "that", "this", "than", "then", "if", "do", "does", "did", "have", "has",
        "had", "can", "could", "will", "would", "shall", "should", "may", "might",
        "must", "not", "no", "up", "out", "just", "im", "ive", "youre", "dont",
        "its", "thats", "theres", "aint", "cause", "til", "till",
    ]

    private static let unstressedPrefixes = ["a", "be", "de", "re", "un", "in", "con", "com", "for", "pre", "pro", "dis", "mis", "ex", "en", "em"]
    private static let penultimateSuffixes = ["tion", "sion", "cian", "ic", "ity", "ial", "ian", "ious", "eous"]

    /// Estimated stress per syllable: `/` stressed, `x` unstressed.
    static func stressPattern(_ word: String) -> String {
        let w = letters(word)
        let n = syllableCount(word)
        guard n > 0 else { return "" }
        if n == 1 { return functionWords.contains(w) ? "x" : "/" }

        var stressed = 0
        if penultimateSuffixes.contains(where: { w.hasSuffix($0) }) {
            stressed = max(0, n - 2)
        } else if n == 2, unstressedPrefixes.contains(where: { w.hasPrefix($0) && w.count > $0.count + 3 }) {
            // "away", "become", "release", "undone"
            stressed = 1
        }
        return (0..<n).map { $0 == stressed ? "/" : "x" }.joined()
    }

    // MARK: Rhyme

    /// Spelling variants that sound alike at the end of a word, longest
    /// first. Applied to the word's tail before comparison.
    private static let tailRewrites: [(String, String)] = [
        ("eigh", "ay"), ("ight", "ite"), ("ought", "ot"), ("aught", "ot"),
        ("tion", "shun"), ("sion", "shun"), ("cian", "shun"),
        ("ey", "ay"), ("ai", "ay"), ("ae", "ay"),
        ("ee", "ea"), ("ie", "ea"),
        ("ew", "oo"), ("ue", "oo"), ("ou", "oo"),
        ("igh", "i"), ("ye", "i"), ("uy", "i"),
        ("ck", "k"), ("ph", "f"), ("wr", "r"), ("kn", "n"),
        ("mb", "m"), ("ss", "s"), ("ll", "l"), ("tt", "t"), ("nn", "n"), ("zz", "z"),
    ]

    /// The rhyming part of a word: its last vowel sound and everything
    /// after it, with spelling normalized ("night" and "bite" → "ite",
    /// "away" and "they" → "ay").
    static func rhymeTail(_ word: String) -> String {
        var w = letters(word)
        guard !w.isEmpty else { return "" }

        // Monosyllables ending in consonant+y sound like "eye": my/sky/fly.
        if w.count <= 4, w.hasSuffix("y"), w.count >= 2 {
            let before = w[w.index(w.endIndex, offsetBy: -2)]
            if !vowels.contains(before) { w = String(w.dropLast()) + "i" }
        }
        // Multisyllables ending in consonant+y sound like "ee": baby/crazy.
        if w.count > 4, w.hasSuffix("y") {
            let before = w[w.index(w.endIndex, offsetBy: -2)]
            if !vowels.contains(before) { w = String(w.dropLast()) + "ea" }
        }

        // Short -ie words sound like "eye": lie/die/tie.
        if w.count <= 4, w.hasSuffix("ie") { w = String(w.dropLast(2)) + "i" }
        // Multisyllables ending in -ey sound like "ee": money/honey.
        if w.count > 4, w.hasSuffix("ey") { w = String(w.dropLast(2)) + "ea" }

        for (from, to) in tailRewrites {
            w = w.replacingOccurrences(of: from, with: to)
        }

        // Magic e: "time" → "i_m" so it rhymes with "rhyme" but not "him".
        var magic = false
        if w.count >= 3, w.hasSuffix("e") {
            let chars = Array(w)
            let consonant = chars[chars.count - 2]
            let vowel = chars[chars.count - 3]
            if !vowels.contains(consonant), vowels.contains(vowel) {
                magic = true
                w = String(w.dropLast())
            }
        }

        let chars = Array(w)
        guard let lastVowelIndex = chars.lastIndex(where: { vowels.contains($0) }) else { return w }
        var start = lastVowelIndex
        while start > 0, vowels.contains(chars[start - 1]) { start -= 1 }
        let tail = String(chars[start...])
        return magic ? tail + "_" : tail
    }

    /// Vowel portion of a rhyme tail (for assonance / slant rhyme).
    static func vowelSound(ofTail tail: String) -> String {
        let core = tail.prefix { vowels.contains($0) }
        return String(core) + (tail.hasSuffix("_") ? "_" : "")
    }

    /// Consonant ending of a rhyme tail (for consonance).
    static func coda(ofTail tail: String) -> String {
        String(tail.drop { vowels.contains($0) }.filter { $0 != "_" })
    }

    enum RhymeKind: String, Sendable {
        case perfect, slant, consonance
    }

    static func rhyme(_ a: String, _ b: String) -> RhymeKind? {
        let la = letters(a), lb = letters(b)
        guard !la.isEmpty, !lb.isEmpty, la != lb else { return nil }
        let ta = rhymeTail(a), tb = rhymeTail(b)
        guard !ta.isEmpty, !tb.isEmpty else { return nil }
        if ta == tb { return .perfect }
        let va = vowelSound(ofTail: ta), vb = vowelSound(ofTail: tb)
        if !va.isEmpty, va == vb { return .slant }
        let ca = coda(ofTail: ta), cb = coda(ofTail: tb)
        if !ca.isEmpty, ca == cb { return .consonance }
        return nil
    }
}
