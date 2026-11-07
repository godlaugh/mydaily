import XCTest
@testable import ALog

final class JournalContentTextTests: XCTestCase {
    func testEnglishWordMovesWholeToBodyWhenItCrossesTheLimit() {
        let value = JournalContentText("This recording is about better transcription quality.")
        XCTAssertEqual(value.title, "This recording is about better")
        XCTAssertEqual(value.remainder, "transcription quality.")
    }

    func testMixedLanguageHeadingDoesNotSplitEnglishWord() {
        let value = JournalContentText("这段日记是在讨论语音识别的准确性，以及使用 SenseVoice transcription 模型时的感受。")
        XCTAssertEqual(value.title, "这段日记是在讨论语音识别的准确性，以及使用 SenseVoice")
        XCTAssertEqual(value.remainder, "transcription 模型时的感受。")
    }

    func testSentenceDetectionPreservesDecimalsAndDomainNames() {
        let value = JournalContentText("I used version 2.1 at example.com. It worked.", titleLimit: 80)
        XCTAssertEqual(value.title, "I used version 2.1 at example.com.")
        XCTAssertEqual(value.remainder, "It worked.")
    }

    func testDomainAtTheLengthBoundaryStaysWhole() {
        let value = JournalContentText("A note about API version 2.1 and example.com today.")
        XCTAssertEqual(value.title, "A note about API version 2.1 and")
        XCTAssertEqual(value.remainder, "example.com today.")
    }

    func testHyphenatedTermAtTheLengthBoundaryStaysWhole() {
        let value = JournalContentText("Today we discussed reliable state-of-the-art transcription.")
        XCTAssertEqual(value.title, "Today we discussed reliable")
        XCTAssertEqual(value.remainder, "state-of-the-art transcription.")
    }

    func testLongFirstWordAndOpeningQuoteStayIntact() {
        let value = JournalContentText("“pneumonoultramicroscopicsilicovolcanoconiosis” is an unusually long word.")
        XCTAssertTrue(value.title.contains("pneumonoultramicroscopicsilicovolcanoconiosis"))
        XCTAssertEqual(value.title + value.remainder, "“pneumonoultramicroscopicsilicovolcanoconiosis” is an unusually long word.")
    }

    func testFirstLineAndPunctuationArePreservedAcrossHeadingAndBody() {
        let value = JournalContentText("  走慢一点，也没有关系。\n不用把每一天都安排得很满。  ")
        XCTAssertEqual(value.title, "走慢一点，也没有关系。")
        XCTAssertEqual(value.remainder, "不用把每一天都安排得很满。")
        let line = JournalContentText("A heading without punctuation\nA separate paragraph.")
        XCTAssertEqual(line.title, "A heading without punctuation")
        XCTAssertEqual(line.remainder, "A separate paragraph.")
    }

    func testEmptyAndEmojiOnlyEntriesDoNotLoseContent() {
        XCTAssertEqual(JournalContentText(" \n ").title, "")
        XCTAssertEqual(JournalContentText(" \n ").remainder, "")
        let source = String(repeating: "👨‍👩‍👧‍👦", count: 45)
        let value = JournalContentText(source)
        XCTAssertEqual(value.title + value.remainder, source)
    }
}
