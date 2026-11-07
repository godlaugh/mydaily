import XCTest

/// Run only this class with the SnapshotTests scheme and `-configuration Debug`.
/// The Snapshot configuration seeds sample recordings. These tests do not call
/// setupSnapshot() or record audio; real model downloads require explicit opt-in.
@MainActor
final class TranscriptionModelsUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        // Override these preferences only for this launch. Leave the provider
        // writable so the tests exercise the real persisted selection binding.
        app.launchArguments = [
            "-trans_enabled", "NO",
            "-auto_start_on_startup", "",
            "-AppleLanguages", "(zh-Hans)"
        ]
        app.launch()
        openModelsPage()
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    func testAvailableModelsDoNotStartADownload() {
        for suffix in ["", "_fp32"] {
            let local = app.buttons["transcription_model_sensevoice" + suffix]
            reveal(local)
            XCTAssertTrue(local.label.contains(suffix.isEmpty ? "INT8" : "FP32"))
            XCTAssertFalse(app.buttons["transcription_model_cancel_download" + suffix].exists)

            let download = app.buttons["transcription_model_download" + suffix]
            let retry = app.buttons["transcription_model_retry" + suffix]
            if download.exists || retry.exists {
                XCTAssertFalse(local.isEnabled, "An uninstalled model must not be selectable.")
                XCTAssertFalse(local.isSelected)
            } else {
                XCTAssertTrue(app.buttons["transcription_model_delete" + suffix].exists)
                XCTAssertTrue(local.isEnabled)
            }
        }

        reveal(app.buttons["transcription_model_apple"])
        reveal(app.buttons["transcription_model_openai"])
    }

    func testAppleAndOpenAISelection() {
        let providerIDs = [
            "transcription_model_sensevoice",
            "transcription_model_sensevoice_fp32",
            "transcription_model_apple",
            "transcription_model_openai"
        ]
        var originalProvider: String?
        for identifier in providerIDs {
            let provider = app.buttons[identifier]
            reveal(provider)
            if provider.isSelected { originalProvider = identifier }
        }
        defer {
            if let originalProvider {
                let original = app.buttons[originalProvider]
                reveal(original, scrollingUp: originalProvider == "transcription_model_openai")
                original.tap()
            }
        }

        let apple = app.buttons["transcription_model_apple"]
        let openAI = app.buttons["transcription_model_openai"]
        let cloudModelPicker = app.descendants(matching: .any)
            .matching(identifier: "transcription_cloud_model_picker").firstMatch

        reveal(apple, scrollingUp: false)
        apple.tap()
        assertSelected(apple)
        XCTAssertFalse(openAI.isSelected)
        XCTAssertFalse(cloudModelPicker.exists)

        reveal(openAI)
        openAI.tap()
        assertSelected(openAI)
        XCTAssertFalse(apple.isSelected)
        reveal(cloudModelPicker)
        XCTAssertTrue(cloudModelPicker.waitForExistence(timeout: 5))

        reveal(apple, scrollingUp: false)
        apple.tap()
        assertSelected(apple)
        XCTAssertFalse(openAI.isSelected)
        XCTAssertFalse(cloudModelPicker.exists)
    }

    /// Explicit opt-in: exercises the real ~240 MB HTTPS download and native preload.
    func testDownloadCancelSelectAndDeleteModel() throws {
        guard ProcessInfo.processInfo.environment["ALOG_TEST_MODEL_DOWNLOAD"] == "1" else {
            throw XCTSkip("Set ALOG_TEST_MODEL_DOWNLOAD=1 to verify the real model download.")
        }
        verifyDownloadLifecycle(suffix: "", downloadTimeout: 180)
    }

    /// Separate opt-in because FP32 downloads about 938 MB.
    func testFP32DownloadCancelSelectAndDeleteModel() throws {
        guard ProcessInfo.processInfo.environment["ALOG_TEST_MODEL_DOWNLOAD_FP32"] == "1" else {
            throw XCTSkip("Set ALOG_TEST_MODEL_DOWNLOAD_FP32=1 to verify the FP32 model download.")
        }
        verifyDownloadLifecycle(suffix: "_fp32", downloadTimeout: 300)
    }

    /// Uses two verified installations provisioned in a dedicated simulator.
    /// This test deletes both variants and never starts a network download.
    func testInstalledVariantsSelectionDeletionAndPersistence() throws {
        guard ProcessInfo.processInfo.environment["ALOG_TEST_MODEL_VARIANTS"] == "1" else {
            throw XCTSkip("Set ALOG_TEST_MODEL_VARIANTS=1 after installing both model variants.")
        }

        for suffix in ["", "_fp32"] {
            let model = app.buttons["transcription_model_sensevoice" + suffix]
            reveal(model)
            XCTAssertTrue(model.isEnabled, "Both verified model variants must be installed before this test.")
            XCTAssertTrue(app.buttons["transcription_model_delete" + suffix].exists)
            XCTAssertFalse(app.buttons["transcription_model_download" + suffix].exists)
            XCTAssertFalse(app.buttons["transcription_model_cancel_download" + suffix].exists)
        }

        let int8 = app.buttons["transcription_model_sensevoice"]
        let fp32 = app.buttons["transcription_model_sensevoice_fp32"]
        let deleteINT8 = app.buttons["transcription_model_delete"]
        let deleteFP32 = app.buttons["transcription_model_delete_fp32"]

        reveal(int8, scrollingUp: false)
        int8.tap()
        assertSelected(int8)
        XCTAssertFalse(fp32.isSelected)
        reveal(deleteINT8)
        waitUntilEnabled(deleteINT8)

        reveal(fp32)
        fp32.tap()
        assertSelected(fp32)
        XCTAssertFalse(int8.isSelected)
        reveal(deleteFP32)
        waitUntilEnabled(deleteFP32)

        let variantsScreenshot = XCTAttachment(screenshot: app.screenshot())
        variantsScreenshot.name = "Transcription Models — INT8 and FP32 installed"
        variantsScreenshot.lifetime = .keepAlways
        add(variantsScreenshot)

        reveal(deleteINT8, scrollingUp: false)
        waitUntilEnabled(deleteINT8)
        deleteINT8.tap()
        let confirmINT8 = app.buttons.matching(identifier: "transcription_model_confirm_delete").firstMatch
        XCTAssertTrue(confirmINT8.waitForExistence(timeout: 5))
        confirmINT8.tap()
        XCTAssertTrue(app.buttons["transcription_model_download"].waitForExistence(timeout: 5))
        XCTAssertFalse(int8.isEnabled)
        XCTAssertFalse(int8.isSelected)
        reveal(fp32)
        assertSelected(fp32)
        XCTAssertTrue(deleteFP32.exists, "Deleting INT8 must preserve the installed FP32 variant.")

        app.terminate()
        app.launch()
        openModelsPage()
        XCTAssertTrue(app.buttons["transcription_model_download"].exists)
        XCTAssertFalse(int8.isEnabled)
        reveal(fp32)
        assertSelected(fp32)
        XCTAssertTrue(fp32.isEnabled)
        reveal(deleteFP32)
        waitUntilEnabled(deleteFP32)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Transcription Models — FP32 selection persisted after deleting INT8"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        deleteFP32.tap()
        let confirmFP32 = app.buttons.matching(identifier: "transcription_model_confirm_delete_fp32").firstMatch
        XCTAssertTrue(confirmFP32.waitForExistence(timeout: 5))
        confirmFP32.tap()
        XCTAssertTrue(app.buttons["transcription_model_download_fp32"].waitForExistence(timeout: 5))
        XCTAssertFalse(fp32.isEnabled)
        XCTAssertFalse(fp32.isSelected)
        let apple = app.buttons["transcription_model_apple"]
        reveal(apple)
        assertSelected(apple)
    }

    private func verifyDownloadLifecycle(suffix: String, downloadTimeout: TimeInterval) {
        let apple = app.buttons["transcription_model_apple"]
        reveal(apple)
        apple.tap()
        assertSelected(apple)

        let local = app.buttons["transcription_model_sensevoice" + suffix]
        let download = app.buttons["transcription_model_download" + suffix]
        let retry = app.buttons["transcription_model_retry" + suffix]
        let delete = app.buttons["transcription_model_delete" + suffix]
        reveal(local, scrollingUp: false)
        if download.exists || retry.exists {
            let start = download.exists ? download : retry
            reveal(start)
            start.tap()
            let cancel = app.buttons["transcription_model_cancel_download" + suffix]
            XCTAssertTrue(cancel.waitForExistence(timeout: 10))
            let progressID = "transcription_model_download_progress" + suffix
            let phase = app.descendants(matching: .any)
                .matching(identifier: progressID + "_phase").firstMatch
            XCTAssertTrue(phase.waitForExistence(timeout: 5))
            XCTAssertFalse(phase.label.contains("0%"), "Connection status must not appear as a stalled zero percent.")
            XCTAssertTrue(app.staticTexts[progressID + "_foreground"].exists)
            XCTAssertTrue(app.staticTexts[progressID + "_source"].exists)
            reveal(cancel)
            cancel.tap()
            XCTAssertTrue(download.waitForExistence(timeout: 5))
            XCTAssertFalse(local.isEnabled)
            XCTAssertFalse(phase.exists)

            download.tap()
            if suffix.isEmpty {
                captureDownloadProgress(identifier: progressID, installedControl: delete)
            }
            XCTAssertTrue(delete.waitForExistence(timeout: downloadTimeout), "The official model should download and verify.")
            XCTAssertFalse(local.isSelected, "Downloading must not change the selected provider.")
        } else {
            XCTAssertTrue(delete.exists, "A model from an earlier test run should remain installed.")
        }
        reveal(local, scrollingUp: false)
        XCTAssertTrue(local.isEnabled)
        local.tap()
        assertSelected(local)
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: delete)
        wait(for: [ready], timeout: 30)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Transcription Models — SenseVoice \(suffix.isEmpty ? "INT8" : "FP32") installed"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        reveal(delete)
        delete.tap()
        let confirm = app.buttons.matching(identifier: "transcription_model_confirm_delete" + suffix).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        XCTAssertFalse(local.isEnabled)
        XCTAssertFalse(local.isSelected)
        reveal(apple)
        assertSelected(apple)
    }

    private func captureDownloadProgress(identifier: String, installedControl: XCUIElement) {
        let amount = app.staticTexts[identifier + "_amount"].firstMatch
        let speed = app.staticTexts[identifier + "_speed"].firstMatch
        let progressOrFinished = expectation(
            for: NSPredicate { _, _ in
                (amount.exists && speed.exists) || installedControl.exists
            },
            evaluatedWith: app
        )
        wait(for: [progressOrFinished], timeout: 45)

        guard amount.exists && speed.exists else {
            let result = installedControl.exists
                ? "Installation completed before transfer labels could be observed."
                : "Transfer labels changed before their values could be captured."
            let note = XCTAttachment(string: result + " This run did not capture live download progress.")
            note.name = "INT8 download progress — no live observation"
            note.lifetime = .keepAlways
            add(note)
            print("INT8 UI download progress: no live observation. " + result)
            return
        }

        // The speed control is only rendered with received bytes and a positive
        // transfer rate. Keep the actual labels as evidence, independent of locale.
        let observedAmount = amount.label
        let observedSpeed = speed.label
        XCTAssertFalse(observedAmount.isEmpty)
        XCTAssertFalse(observedSpeed.isEmpty)
        for element in [amount, speed] {
            if installedControl.exists { break }
            guard element.exists, !element.isHittable else { continue }
            if element.frame.midY > app.frame.midY {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
        }

        let visible = amount.exists && speed.exists && amount.isHittable && speed.isHittable
        let note = XCTAttachment(string: "Observed transfer amount: \(observedAmount)\nObserved transfer rate: \(observedSpeed)\nLive progress visible for screenshot: \(visible)")
        note.name = "INT8 download progress — observed transfer values"
        note.lifetime = .keepAlways
        add(note)
        print("INT8 UI download progress: \(observedAmount); \(observedSpeed); visible: \(visible)")

        if visible {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Transcription Models — INT8 download in progress"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        } else if amount.exists && speed.exists && !installedControl.exists {
            XCTFail("Live byte count and transfer rate should be visible while downloading.")
        }
    }

    private func openModelsPage() {
        let settings = app.buttons["journal_settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        let models = app.descendants(matching: .any)
            .matching(identifier: "transcription_models_settings").firstMatch
        XCTAssertTrue(models.waitForExistence(timeout: 5))
        reveal(models)
        models.tap()
        XCTAssertTrue(app.buttons["transcription_model_sensevoice"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, scrollingUp: Bool = true) {
        for _ in 0..<6 {
            if element.isHittable { return }
            if scrollingUp {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
        }
        XCTAssertTrue(element.isHittable, "Expected model control to be visible: \(element.identifier)")
    }

    private func assertSelected(_ element: XCUIElement) {
        let selected = expectation(
            for: NSPredicate(format: "selected == true"),
            evaluatedWith: element
        )
        wait(for: [selected], timeout: 5)
    }

    private func waitUntilEnabled(_ element: XCUIElement) {
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: element)
        wait(for: [ready], timeout: 120)
    }
}
