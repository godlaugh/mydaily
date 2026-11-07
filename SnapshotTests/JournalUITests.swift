import XCTest

@MainActor
final class JournalUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launchArguments = ["-journal-ui-test", "-journal-ui-seed", "-AppleLanguages", "(zh-Hans)", "-dark_mode", "light"]
        app.launch()
    }

    override func tearDown() { app.terminate(); super.tearDown() }

    func testTextAdditionStaysInThreadAndSurvivesRelaunch() {
        let root = app.buttons["journal_entry_quiet-root"]
        XCTAssertTrue(root.waitForExistence(timeout: 10))
        app.buttons["journal_thread_quiet-root"].tap()
        let appendButton = app.buttons["journal_continue_text"]
        XCTAssertTrue(appendButton.waitForExistence(timeout: 5))
        appendButton.tap()
        let input = app.textFields["journal_note_input"].exists
            ? app.textFields["journal_note_input"] : app.textViews["journal_note_input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("一年后追加的独立记录")
        app.buttons["journal_save_note"].tap()
        XCTAssertTrue(app.staticTexts["一年后追加的独立记录"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["后续"].exists)
        XCTAssertFalse(app.staticTexts["3 次后续"].exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-journal-ui-seed" }
        app.launch()
        XCTAssertTrue(app.buttons["journal_thread_quiet-root"].waitForExistence(timeout: 10))
        app.buttons["journal_thread_quiet-root"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["一年后追加的独立记录"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Journal thread with persisted addition"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMiniPlayerAppearsOnlyAfterPlaybackAndClosesWhilePaused() {
        XCTAssertTrue(app.buttons["journal_audio_quiet-root"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["journal_mini_toggle"].exists)
        app.buttons["journal_audio_quiet-root"].tap()
        let toggle = app.buttons["journal_mini_toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        app.buttons["journal_mini_close"].tap()
        XCTAssertFalse(toggle.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Quiet journal home"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSeparateDiaryHasNoOtherThreadsContents() {
        app.buttons["journal_entry_quiet-other"].tap()
        XCTAssertTrue(app.buttons["journal_continue_text"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "开始每周给自己")).firstMatch.exists)
        app.buttons["journal_continue_voice"].tap()
        XCTAssertTrue(app.buttons["journal_recording_stop"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "把刚刚的灵感")).firstMatch.exists)
        let clock = app.staticTexts["journal_recording_time"]
        XCTAssertTrue(clock.waitForExistence(timeout: 5))
        let recorded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "00:00"), object: clock)
        XCTAssertEqual(XCTWaiter.wait(for: [recorded], timeout: 8), .completed)
        capture("Recording an addition")
        app.buttons["journal_recording_stop"].tap()
        XCTAssertTrue(app.buttons["journal_continue_text"].waitForExistence(timeout: 10))
        let audio = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "journal_audio_")).firstMatch
        XCTAssertTrue(audio.waitForExistence(timeout: 5))
    }

    func testHoldToRecordSavesAndSelectionCanBeCanceled() {
        app.terminate()
        app.launchArguments.append("-journal-ui-hold")
        app.launch()
        let microphone = app.descendants(matching: .any).matching(identifier: "microphone").firstMatch
        XCTAssertTrue(microphone.waitForExistence(timeout: 10))
        microphone.press(forDuration: 2)
        let diaries = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "journal_entry_"))
        let added = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in diaries.count == 3 }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [added], timeout: 10), .completed)
        // The new voice diary sorts ahead of the seeded thread.
        XCTAssertTrue(app.buttons["journal_entry_quiet-root"].exists)
        let root = app.buttons["journal_entry_quiet-root"]
        root.press(forDuration: 1)
        app.buttons["journal_begin_selection"].tap()
        XCTAssertTrue(app.buttons["journal_cancel_selection"].waitForExistence(timeout: 5))
        app.buttons["journal_cancel_selection"].tap()
        XCTAssertTrue(app.buttons["journal_settings"].exists)
    }

    func testManualRecordingSave() {
        app.terminate()
        app.launchArguments.append("-journal-ui-manual-save")
        app.launch()
        app.buttons["journal_entry_quiet-other"].tap()
        app.buttons["journal_continue_voice"].tap()
        let clock = app.staticTexts["journal_recording_time"]
        XCTAssertTrue(clock.waitForExistence(timeout: 10))
        let recorded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "00:00"), object: clock)
        XCTAssertEqual(XCTWaiter.wait(for: [recorded], timeout: 8), .completed)
        app.buttons["journal_recording_stop"].tap()
        let save = app.buttons["journal_save_recording"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        capture("Recording editor")
        save.tap()
        XCTAssertTrue(app.buttons["journal_continue_voice"].waitForExistence(timeout: 10))
    }

    func testDarkAndLargeTextLayouts() {
        app.terminate()
        app.launchArguments.removeLast()
        app.launchArguments += ["dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        XCTAssertTrue(app.buttons["journal_settings"].waitForExistence(timeout: 10))
        capture("Dark journal with large text")
        app.buttons["journal_entry_quiet-root"].tap()
        XCTAssertTrue(app.buttons["journal_continue_voice"].waitForExistence(timeout: 5))
        capture("Dark thread with large text")
    }

    func testEnglishWordsStayWholeInListAndDetail() {
        app.terminate()
        app.launchArguments.append("-journal-ui-word-boundary")
        app.launch()
        let root = app.buttons["journal_entry_quiet-root"]
        XCTAssertTrue(root.waitForExistence(timeout: 10))
        XCTAssertTrue(root.label.contains("transcription quality."))
        XCTAssertTrue(app.buttons["journal_entry_quiet-other"].label.contains("transcription 模型时的感受。"))
        capture("Complete English words in diary titles and excerpts")
        root.tap()
        XCTAssertTrue(app.staticTexts["This recording is about better"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["transcription quality."].exists)
        capture("Complete English words in diary detail")
    }

    func testLastDiaryRemainsAboveDockAndCanOpenAfterScrollRelease() {
        launchLongList()
        scrollToLastDiary()
        assertLastDiaryAbove(app.buttons["microphone"].frame.minY - 14)
        capture("Last diary above dock after releasing scroll")
        app.buttons["journal_thread_scroll-tail"].tap()
        XCTAssertTrue(app.buttons["journal_continue_text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["留在这里的补充记录，也应该能完整点开。"].exists)
    }

    func testLastDiaryRemainsAboveMiniPlayerAndSupportsLongPress() {
        launchLongList()
        app.buttons["journal_audio_quiet-root"].tap()
        let toggle = app.buttons["journal_mini_toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        scrollToLastDiary()
        assertLastDiaryAbove(toggle.frame.minY - 10)
        capture("Last diary above paused player")
        app.buttons["journal_entry_scroll-tail"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["journal_begin_selection"].waitForExistence(timeout: 5))
        app.buttons["journal_begin_selection"].tap()
        XCTAssertTrue(app.buttons["journal_select_scroll-tail"].isSelected)
    }

    func testLastDiaryRemainsReachableWithLargeTextAndMiniPlayer() {
        launchLongList(largeText: true)
        let audio = app.buttons["journal_audio_quiet-root"]
        if !audio.isHittable { app.swipeUp() }
        audio.tap()
        let toggle = app.buttons["journal_mini_toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        scrollToLastDiary()
        assertLastDiaryAbove(toggle.frame.minY - 10)
        capture("Last diary above player with large text")
        app.buttons["journal_thread_scroll-tail"].tap()
        XCTAssertTrue(app.buttons["journal_continue_text"].waitForExistence(timeout: 5))
    }

    private func launchLongList(largeText: Bool = false) {
        app.terminate()
        app.launchArguments.append("-journal-ui-long-list")
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["journal_settings"].waitForExistence(timeout: 10))
    }

    private func scrollToLastDiary() {
        let tail = app.buttons["journal_thread_scroll-tail"]
        for _ in 0..<24 {
            app.swipeUp()
            if tail.exists && tail.frame.minY < app.buttons["microphone"].frame.minY { break }
        }
        // XCTest waits for the gesture and bounce to settle before the next query.
        app.swipeUp()
        XCTAssertTrue(tail.exists)
    }

    private func assertLastDiaryAbove(_ toolbarTop: CGFloat) {
        let tail = app.buttons["journal_thread_scroll-tail"]
        XCTAssertTrue(tail.isHittable)
        XCTAssertLessThanOrEqual(tail.frame.maxY, toolbarTop,
                                 "The last entry must stay above bottom controls after the gesture ends.")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
