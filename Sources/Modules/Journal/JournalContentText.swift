import Foundation
import NaturalLanguage

/// Derives a heading without changing the stored diary or splitting a word
/// between the heading and its body. The limit is a preferred length, not a cut.
struct JournalContentText {
    let title: String
    let remainder: String
    // Dictionary tokenizers may split domains and hyphenated terms into several words.
    private static let joinedTokens = try? NSRegularExpression(
        pattern: #"[\p{Latin}\p{N}][\p{Latin}\p{M}\p{N}.'’_:/@+%#?=&~\-]*"#
    )

    init(_ source: String, titleLimit: Int = 40) {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { title = ""; remainder = ""; return }
        let line = String(text.prefix { !$0.isNewline })
        let sentences = NLTokenizer(unit: .sentence)
        sentences.string = line
        let sentenceRange = sentences.tokenRange(at: line.startIndex)
        let sentenceEnd = sentenceRange.isEmpty ? line.endIndex : sentenceRange.upperBound
        let sentence = String(line[..<sentenceEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        var end = sentence.index(sentence.startIndex, offsetBy: max(1, titleLimit), limitedBy: sentence.endIndex) ?? sentence.endIndex

        if end < sentence.endIndex {
            let words = NLTokenizer(unit: .word)
            words.string = sentence
            let joinedToken = Self.joinedTokens?
                .matches(in: sentence, range: NSRange(sentence.startIndex..., in: sentence))
                .compactMap { Range($0.range, in: sentence) }
                .first { $0.lowerBound < end && end < $0.upperBound }
            let word = joinedToken ?? words.tokenRange(at: end)
            if word.lowerBound < end && end < word.upperBound {
                let preceding = sentence[..<word.lowerBound]
                // Keep an unusually long first word intact, including after an opening quote.
                end = preceding.contains(where: { $0.isLetter || $0.isNumber })
                    ? word.lowerBound : word.upperBound
            }
        }

        title = String(sentence[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        remainder = String(text.dropFirst(title.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
