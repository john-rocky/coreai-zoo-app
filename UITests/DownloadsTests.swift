// DownloadsTests — device checks for downloads the user starts: the Camera tab's Download
// buttons, the downloaded-models list and its delete, and the voices this device cannot run.
// Not part of the screenshot run:
//   xcodegen generate --spec project-shots.yml
//   xcodebuild test -project CoreAIZooShots.xcodeproj -scheme Shots -destination id=<udid> \
//     -only-testing:CoreAIZooUITests/DownloadsTests
// The Camera tests first delete Depth Anything 3 Small, YOLOX-S and V-JEPA 2 if a run left them.
// The voice tests follow the live catalog's iOS voices (`voices`): off an iPhone 17 model none
// can run, so testEveryVoiceIsMarkedBeforeAnyDownload runs there and testAvailableVoiceStillSpeaks
// is skipped; on an iPhone 17 model it is the other way round. Each step attaches a screenshot.

import XCTest

final class DownloadsTests: XCTestCase {
    var app: XCUIApplication!

    /// The live catalog's iOS voices, in catalog order (2026-10-27). VoxCPM, VoxCPM2 and
    /// VibeVoice ship iPhone files built for the iPhone 17 models only; this app does not offer
    /// Audio8 on an iPhone yet (not measured there).
    static let voices = [
        "VoxCPM 0.5B", "VoxCPM2 2B", "Audio8-TTS Preview 0.6B",
        "VibeVoice-Realtime 0.5B (multi-speaker)",
    ]

    /// The iPhone 17 models are iPhone18,x, the only phones that load the voices' iPhone files.
    static let isIPhone17Model: Bool = {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return machine.hasPrefix("iPhone18,")
    }()

    /// A voice's row in the voice menu when this device cannot run it.
    static func marked(_ voice: String) -> String { "\(voice) (not on this device)" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        answerCameraAlert()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
    }

    func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func button(beginsWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    func waitGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// Taps Allow on the camera permission alert, which only SpringBoard sees and which outlives
    /// the app's relaunch.
    func answerCameraAlert() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "OK"] {
            let button = springboard.buttons[label].firstMatch
            if button.exists {
                button.tap()
                return
            }
        }
    }

    /// Waits for `text` while answering the camera permission alert.
    func waitForText(_ text: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.staticTexts[text].exists { return true }
            answerCameraAlert()
            sleep(2)
        }
        return false
    }

    /// Opens the downloaded-models list from the current tab and waits until it has loaded.
    func openList() {
        app.buttons["Downloaded models"].firstMatch.tap()
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if app.staticTexts["No models downloaded yet."].exists
                || button(beginsWith: "Delete ").exists { return }
            sleep(1)
        }
        XCTFail("the list did not load")
    }

    /// `voice`'s row in the open voice menu, marked; logs the hierarchy if it is not a button.
    func menuRow(_ voice: String) -> XCUIElement {
        let row = button(beginsWith: Self.marked(voice))
        if row.waitForExistence(timeout: 10) { return row }
        NSLog("HIERARCHY voice menu\n%@", app.debugDescription)
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.marked(voice))).firstMatch
    }

    func listedRow(_ name: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Delete ' AND label CONTAINS %@", name)).firstMatch
    }

    /// Deletes the rows naming `names`, so a test starts from "not downloaded" even after an
    /// earlier run stopped between its download and its delete.
    func deleteListed(_ names: [String]) {
        openList()
        for name in names where listedRow(name).exists {
            NSLog("DOWNLOADS cleanup: %@", listedRow(name).label)
            listedRow(name).tap()
            app.buttons["Delete"].firstMatch.tap()
            XCTAssertTrue(waitGone(listedRow(name), timeout: 10), "cleanup removed \(name)")
        }
        app.buttons["Done"].tap()
    }

    func testCameraAsksBeforeDownloadingAndDeleteRemovesIt() {
        app.tabBars.buttons["Camera"].tap()
        deleteListed(["Depth Anything"])
        // A fresh Depth view looks at the disk.
        app.buttons["Detect"].tap()
        app.buttons["Depth"].tap()
        let download = button(beginsWith: "Download ")
        XCTAssertTrue(download.waitForExistence(timeout: 30), "Depth asks before downloading")
        XCTAssertTrue(app.staticTexts["Not downloaded yet"].exists)
        let asked = download.label
        NSLog("DOWNLOADS asked: %@", asked)
        shot("depth asks")

        download.tap()
        XCTAssertTrue(waitForText("Live", timeout: 900), "Depth runs after the download")
        NSLog("DOWNLOADS live after the tap")
        shot("depth live")

        openList()
        let delete = button(beginsWith: "Delete Depth Anything")
        XCTAssertTrue(delete.exists, "Depth Anything is listed")
        NSLog("DOWNLOADS listed: %@", delete.label)
        shot("list with depth")
        delete.tap()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "delete asks to confirm")
        shot("delete confirm")
        confirm.tap()
        XCTAssertTrue(waitGone(delete, timeout: 10), "row gone after delete")
        shot("list after delete")
        app.buttons["Done"].tap()

        // A fresh Depth view looks at the disk again.
        app.buttons["Detect"].tap()
        app.buttons["Depth"].tap()
        XCTAssertTrue(app.buttons[asked].waitForExistence(timeout: 30),
                      "Depth asks again after the delete")
        NSLog("DOWNLOADS asked again after delete")
        shot("depth asks again")
    }

    func testDetectAndActionAskBeforeDownloading() {
        app.tabBars.buttons["Camera"].tap()
        deleteListed(["Depth Anything", "YOLOX", "V-JEPA"])
        var previous: String?
        for mode in ["Detect", "Action", "Depth"] {
            app.buttons[mode].tap()
            if let previous {
                XCTAssertTrue(waitGone(app.buttons[previous], timeout: 10), "the previous mode is gone")
            }
            let download = button(beginsWith: "Download ")
            XCTAssertTrue(download.waitForExistence(timeout: 30), "\(mode) asks before downloading")
            XCTAssertTrue(app.staticTexts["Not downloaded yet"].exists)
            NSLog("DOWNLOADS %@ asked: %@", mode, download.label)
            shot("\(mode.lowercased()) asks")
            previous = download.label
        }

        // Opening the three modes downloaded none of their models.
        openList()
        shot("list after opening the modes")
        for name in ["Depth Anything", "YOLOX", "V-JEPA"] {
            XCTAssertFalse(listedRow(name).exists, "\(name) not downloaded by opening its mode")
        }
        app.buttons["Done"].tap()
    }

    func testDownloadedModelsOpensFromChatCameraAndAudio() {
        for tab in ["Chat", "Camera", "Audio"] {
            app.tabBars.buttons[tab].tap()
            let open = app.buttons["Downloaded models"].firstMatch
            XCTAssertTrue(open.waitForExistence(timeout: 30), "\(tab) has the list button")
            open.tap()
            let title = app.navigationBars["Downloaded models"]
            XCTAssertTrue(title.waitForExistence(timeout: 10), "the list opens from \(tab)")
            shot("list from \(tab.lowercased())")
            app.buttons["Done"].tap()
            XCTAssertTrue(waitGone(title, timeout: 10), "Done closes the list")
            NSLog("DOWNLOADS list opened from %@", tab)
        }
    }

    func testEveryVoiceIsMarkedBeforeAnyDownload() throws {
        try XCTSkipIf(Self.isIPhone17Model, "the iPhone 17 models run these voices")
        app.tabBars.buttons["Audio"].tap()
        let load = app.buttons["Download & Load"]
        XCTAssertTrue(load.waitForExistence(timeout: 30))
        // With no voice runnable, the first one stays selected; the menu's button shows its name.
        var current = Self.voices[0]
        if !app.buttons[current].waitForExistence(timeout: 30) {
            NSLog("HIERARCHY speak\n%@", app.debugDescription)
            XCTFail("the first voice is selected")
            return
        }

        // The menu marks every voice.
        app.buttons[current].tap()
        for voice in Self.voices {
            XCTAssertTrue(menuRow(voice).exists, "\(voice) is marked in the menu")
        }
        shot("voice menu")
        menuRow(current).tap()

        let window = app.windows.firstMatch.frame
        for voice in Self.voices {
            if voice != current {
                app.buttons[current].tap()
                let row = menuRow(voice)
                XCTAssertTrue(row.exists, "\(voice) is in the menu")
                row.tap()
                XCTAssertTrue(app.buttons[voice].waitForExistence(timeout: 10), "\(voice) selected")
                current = voice
            }
            let reason = app.staticTexts.matching(NSPredicate(
                format: "label BEGINSWITH %@ AND (label CONTAINS 'built for iPhone 17 models only'"
                    + " OR label CONTAINS 'needs a newer version of this app')", voice)).firstMatch
            XCTAssertTrue(reason.waitForExistence(timeout: 10), "the reason for \(voice) shows")
            NSLog("DOWNLOADS reason: %@", reason.label)
            shot("speak \(voice)")
            NSLog("DOWNLOADS frames: %@",
                  "window \(window) menu \(app.buttons[voice].frame) load \(load.frame)")
            XCTAssertTrue(window.contains(load.frame), "Load stays on screen for \(voice)")
            XCTAssertFalse(load.isEnabled, "Load is off for \(voice)")

            // A tap on the disabled button starts nothing.
            load.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            sleep(2)
            XCTAssertTrue(app.staticTexts["Pick a voice and load it"].exists, "still idle")
            XCTAssertFalse(app.progressIndicators.firstMatch.exists, "no download started")
        }
    }

    func testAvailableVoiceStillSpeaks() throws {
        try XCTSkipUnless(Self.isIPhone17Model, "no voice runs on a phone other than an iPhone 17 model")
        app.tabBars.buttons["Audio"].tap()
        let load = app.buttons["Download & Load"]
        XCTAssertTrue(load.waitForExistence(timeout: 30))
        load.tap()
        XCTAssertTrue(waitForText("Ready", timeout: 900), "the first available voice loads")
        // The mode picker has a "Speak" segment too; the button is the last match.
        let speakButtons = app.buttons.matching(identifier: "Speak")
        speakButtons.element(boundBy: max(0, speakButtons.count - 1)).tap()
        let spoken = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 's of audio'"))
            .firstMatch
        XCTAssertTrue(spoken.waitForExistence(timeout: 300), "it speaks")
        NSLog("DOWNLOADS spoke: %@", spoken.label)
    }
}
