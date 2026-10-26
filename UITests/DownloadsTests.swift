// DownloadsTests — device checks for downloads the user starts: the Camera tab's Download
// button, the downloaded-models list and its delete, and a voice this device cannot run.
// Not part of the screenshot run:
//   xcodegen generate --spec project-shots.yml
//   xcodebuild test -project CoreAIZooShots.xcodeproj -scheme Shots -destination id=<udid> \
//     -only-testing:CoreAIZooUITests/DownloadsTests
// testCamera… expects Depth Anything 3 Small not downloaded yet; testVoice… expects a device
// other than an iPhone 17 model (VoxCPM2's iPhone files are built for those only).

import XCTest

final class DownloadsTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
    }

    func button(beginsWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Waits for `text` while answering the camera permission alert, which only SpringBoard sees.
    func waitForText(_ text: String, timeout: TimeInterval) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.staticTexts[text].exists { return true }
            for label in ["Allow", "OK"] where springboard.buttons[label].exists {
                springboard.buttons[label].tap()
            }
            sleep(2)
        }
        return false
    }

    func testCameraAsksBeforeDownloadingAndDeleteRemovesIt() {
        app.tabBars.buttons["Camera"].tap()
        let download = button(beginsWith: "Download ")
        XCTAssertTrue(download.waitForExistence(timeout: 30), "Depth asks before downloading")
        XCTAssertTrue(app.staticTexts["Not downloaded yet"].exists)
        NSLog("DOWNLOADS asked: %@", download.label)

        download.tap()
        XCTAssertTrue(waitForText("Live", timeout: 900), "Depth runs after the download")
        NSLog("DOWNLOADS live after the tap")

        app.buttons["Downloaded models"].firstMatch.tap()
        let delete = button(beginsWith: "Delete Depth Anything")
        XCTAssertTrue(delete.waitForExistence(timeout: 20), "Depth Anything is listed")
        NSLog("DOWNLOADS listed: %@", delete.label)
        delete.tap()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertFalse(delete.waitForExistence(timeout: 5), "row gone after delete")
        app.buttons["Done"].tap()

        // A fresh Depth view looks at the disk again.
        app.buttons["Detect"].tap()
        app.buttons["Depth"].tap()
        XCTAssertTrue(button(beginsWith: "Download ").waitForExistence(timeout: 30),
                      "Depth asks again after the delete")
        NSLog("DOWNLOADS asked again after delete")
    }

    func testVoiceThisDeviceCannotRunIsMarkedBeforeDownload() {
        app.tabBars.buttons["Audio"].tap()
        let voice = button(beginsWith: "Kokoro")
        XCTAssertTrue(voice.waitForExistence(timeout: 30), "an available voice is picked first")
        voice.tap()
        let vox = button(beginsWith: "VoxCPM2 2B")
        XCTAssertTrue(vox.waitForExistence(timeout: 10))
        NSLog("DOWNLOADS picker row: %@", vox.label)
        XCTAssertTrue(vox.label.contains("not on this device"))
        vox.tap()
        let reason = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'built for iPhone 17 models only'")).firstMatch
        XCTAssertTrue(reason.waitForExistence(timeout: 10), "the reason shows before any download")
        XCTAssertFalse(app.buttons["Download & Load"].isEnabled, "nothing to download")
        NSLog("DOWNLOADS reason: %@", reason.label)
    }

    func testAvailableVoiceStillSpeaks() {
        app.tabBars.buttons["Audio"].tap()
        let load = app.buttons["Download & Load"]
        XCTAssertTrue(load.waitForExistence(timeout: 30))
        load.tap()
        XCTAssertTrue(waitForText("Ready", timeout: 900), "the first available voice loads")
        app.buttons["Speak"].tap()
        let spoken = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 's of audio'"))
            .firstMatch
        XCTAssertTrue(spoken.waitForExistence(timeout: 300), "it speaks")
        NSLog("DOWNLOADS spoke: %@", spoken.label)
    }
}
