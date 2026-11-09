import Foundation

/// Checks whether a spoken sentence starts with the wake word, and strips it off.
///
/// Matching is lenient, because speech recognition often mangles names: case, accents and
/// punctuation are ignored, words may be run together ("heyalarm") and a small typo is
/// tolerated for longer wake words ("Hey alarms" still matches "Hey Alarm").
enum WakeWord {
    /// Returns the rest of the sentence after the wake word: empty if only the wake word was said,
    /// nil if the sentence doesn't start with it. An empty wake word lets everything through.
    static func strip(_ wakeWord: String, from utterance: String) -> String? {
        let wakeTokens = tokens(in: wakeWord)
        guard !wakeTokens.isEmpty else { return utterance }
        let wake = wakeTokens.map(\.folded).joined()

        let words = tokens(in: utterance)
        var joined = ""
        for word in words.prefix(wakeTokens.count + 1) {
            joined += word.folded
            if matches(joined, wake) {
                return trimmingLeadingPunctuation(String(utterance[word.end...]))
            }
        }
        return nil
    }

    // MARK: - Helpers

    private struct Token {
        let folded: String
        let end: String.Index
    }

    private static func tokens(in text: String) -> [Token] {
        var result: [Token] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            let character = text[index]
            if character.isLetter || character.isNumber {
                current.append(character)
                let atWordEnd = next == text.endIndex || !(text[next].isLetter || text[next].isNumber)
                if atWordEnd {
                    result.append(Token(folded: fold(current), end: next))
                    current = ""
                }
            }
            index = next
        }
        return result
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    private static func matches(_ heard: String, _ wake: String) -> Bool {
        if heard == wake { return true }
        let allowed = wake.count >= 9 ? 2 : (wake.count >= 5 ? 1 : 0)
        guard allowed > 0, abs(heard.count - wake.count) <= allowed else { return false }
        return editDistance(heard, wake) <= allowed
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1]
                    : 1 + min(previous[j - 1], previous[j], current[j - 1])
            }
            previous = current
        }
        return previous[b.count]
    }

    private static func trimmingLeadingPunctuation(_ text: String) -> String {
        let skip = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let trimmed = text.unicodeScalars.drop { skip.contains($0) }
        return String(String.UnicodeScalarView(trimmed)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
