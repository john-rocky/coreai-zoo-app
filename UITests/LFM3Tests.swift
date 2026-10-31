// LFM3Tests — device checks for LFM3 1.7B in the Chat tab, before it is in the live catalog: the app
// is launched with `-ZooCatalog` (ZooCatalog.swift), which only a launch argument can set.
//   xcodegen generate --spec project-shots.yml
//   xcodebuild test -project CoreAIZooShots.xcodeproj -scheme Shots -destination id=<udid> \
//     -only-testing:CoreAIZooUITests/LFM3Tests
// test1: a catalog row whose iPhone bundles are for another architecture is marked in the Chat and
// Bench pickers with the reason, before any download, and Load / Run start nothing; test1b: the
// built-in Nemotron-3-Nano 4B (iPhone files in `ios-h18p/`) is marked on the iPhone 18 Pro;
// test1c: the Vision tab's LFM2.5-VL 450M (the same) stops at Load before the download.
// test2 (iPhone 18 Pro, the architecture LFM3's `ios-h19p/` is compiled for): the built-in catalog's
// row downloads from the Chat tab, loads, and keeps the thinking out of the answer; with Think off
// the reply has no thinking. The bundle stays for the scripted run; test3 deletes it from the
// downloaded-models list. Each step attaches a screenshot.

import XCTest

final class LFM3Tests: XCTestCase {
    var app: XCUIApplication!

    /// The built-in row of LFM3 1.7B with its iPhone architectures set to the iPhone 17 Pro's, so
    /// an iPhone 18 Pro reads it the way an iPhone 17 Pro reads the real one.
    static let otherArchitectureCatalog = #"""
        {"version":1,"models":[{"id":"lfm3-1.7b","name":"LFM3 1.7B","repo":"mlboydaisuke/LFM3-1.7B-CoreAI","revision":"8621dc42f2a6f25b1ad3f955aab39d608dbdfef4","kind":"chat","variants":{"macos":{"path":"gpu-pipelined/lfm3_1_7b_decode_int8hu_block32_sym_pf64","sizeMB":2720},"ios":{"path":"ios","engine":"static-shape","sizeMB":2164,"architectures":["h18p"]}},"thinking":true,"engine":"pipelined"}]}
        """#

    /// The iPhone 18 Pro (iPhone19,2), the phone LFM3's `ios-h19p/` was compiled and checked on.
    static let isIPhone18Pro: Bool = {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        NSLog("LFM3 machine: %@", machine)
        return machine == "iPhone19,2"
    }()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func launch(catalog: String) {
        app.launchArguments = ["-ZooCatalog", catalog]
        app.launch()
        answerCameraAlert()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
    }

    /// Taps Allow on a camera permission alert left by an earlier run (DownloadsTests opens the
    /// Camera tab); only SpringBoard sees it, and it blocks this run's taps until answered.
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

    func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func button(beginsWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    func status(_ text: String, within timeout: TimeInterval) -> Bool {
        let label = app.staticTexts["chat.status"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if label.exists, label.label == text { return true }
            if label.exists, label.label.hasPrefix("Error") {
                NSLog("LFM3 status: %@", label.label)
                return false
            }
            sleep(2)
        }
        NSLog("LFM3 status after %.0f s: %@", timeout, label.exists ? label.label : "none")
        return false
    }

    func texts(containing fragment: String) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment))
    }

    func ask(_ question: String) {
        let field = app.textFields["Message"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(question)
        app.buttons["Send"].tap()
        XCTAssertTrue(status("Generating…", within: 30) || status("Ready", within: 5), "the reply starts")
        XCTAssertTrue(status("Ready", within: 600), "the reply ends")
    }

    /// The Chat tab's Think switch (a SwiftUI Toggle, so a switch, not a button): tapped on the
    /// switch's side, then read back.
    func setThink(_ on: Bool) {
        let toggle = app.switches["Think"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "the Think switch shows")
        if (toggle.value as? String == "1") != on {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, on ? "1" : "0", "Think is \(on ? "on" : "off")")
    }

    func openList() {
        app.buttons["Downloaded models"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Downloaded models"].waitForExistence(timeout: 10))
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if app.staticTexts["No models downloaded yet."].exists
                || button(beginsWith: "Delete ").exists { return }
            sleep(1)
        }
        XCTFail("the list did not load")
    }

    func test1OtherArchitectureIsMarkedBeforeAnyDownload() {
        launch(catalog: Self.otherArchitectureCatalog)
        app.tabBars.buttons["Chat"].tap()
        let reason = app.staticTexts["chat.unavailableReason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 30), "the reason shows")
        // Kept as text: the element is gone from the hierarchy once the Bench tab is open.
        let chatReason = reason.label
        NSLog("LFM3 chat reason: %@", chatReason)
        XCTAssertEqual(chatReason, "LFM3 1.7B's iPhone version is built for the iPhone 17 Pro only.")
        let picker = app.buttons["chat.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.tap()
        let row = button(beginsWith: "LFM3 1.7B (not on this device)")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the menu marks the model")
        shot("chat menu marked")
        row.tap()
        let load = app.buttons["chat.load"]
        XCTAssertFalse(load.isEnabled, "Load is off")
        load.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(2)
        XCTAssertEqual(app.staticTexts["chat.status"].label, "Pick a model", "still idle")
        XCTAssertFalse(app.progressIndicators.firstMatch.exists, "no download started")
        shot("chat marked")

        app.tabBars.buttons["Bench"].tap()
        let benchReason = app.staticTexts["bench.unavailableReason"]
        XCTAssertTrue(benchReason.waitForExistence(timeout: 30), "Bench shows the reason")
        XCTAssertEqual(benchReason.label, chatReason)
        XCTAssertFalse(app.buttons["bench.run"].isEnabled, "Run is off")
        shot("bench marked")

        // The downloaded-models list opens from Chat, Camera and Audio (DownloadsTests), not Bench.
        app.tabBars.buttons["Chat"].tap()
        openList()
        XCTAssertFalse(button(beginsWith: "Delete LFM3").exists, "nothing of LFM3 was downloaded")
        shot("list without lfm3")
        app.buttons["Done"].tap()
    }

    /// The built-in catalog's Nemotron-3-Nano 4B, whose iPhone path sits in `ios-h18p/`, is marked
    /// on the iPhone 18 Pro the same way (before 2.0.3 it downloaded 4.6 GB and then failed to load).
    func test1bNemotronIsMarkedOnTheIPhone18Pro() throws {
        try XCTSkipUnless(Self.isIPhone18Pro, "its iPhone files are for the iPhone 17 Pro")
        launch(catalog: "builtin")
        app.tabBars.buttons["Chat"].tap()
        let picker = app.buttons["chat.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 30))
        picker.tap()
        let row = button(beginsWith: "Nemotron-3-Nano 4B (not on this device)")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the menu marks Nemotron")
        row.tap()
        let reason = app.staticTexts["chat.unavailableReason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 10))
        XCTAssertEqual(reason.label,
                       "Nemotron-3-Nano 4B's iPhone version is built for the iPhone 17 Pro only.")
        XCTAssertFalse(app.buttons["chat.load"].isEnabled, "Load is off")
        shot("nemotron marked")
    }

    /// The Vision tab's LFM2.5-VL 450M (iPhone files in `ios-h18p/`): on the iPhone 18 Pro, Load
    /// stops before the download with the reason (the kit's catalog lookup refuses it).
    func test1cVisionStopsBeforeTheDownload() throws {
        try XCTSkipUnless(Self.isIPhone18Pro, "its iPhone files are for the iPhone 17 Pro")
        launch(catalog: "builtin")
        app.tabBars.buttons["Vision"].tap()
        // The picker reads "Model, <the selected model>"; Vision reads the kit's catalog itself
        // (live, then built-in), not -ZooCatalog.
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Model, ")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 30), "the Vision picker shows")
        NSLog("LFM3 vision picker: %@", picker.label)
        picker.tap()
        let row = button(beginsWith: "LFM2.5-VL 450M")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        app.buttons["Download & Load"].tap()
        let error = texts(containing: "This device cannot run the model").firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 30), "Load stops with the reason")
        XCTAssertEqual(error.label, "Error: This device cannot run the model: "
                       + "LFM2.5-VL 450M's iPhone version is built for the iPhone 17 Pro only.")
        XCTAssertFalse(app.progressIndicators.firstMatch.exists, "no download started")
        shot("vision stops")
        app.tabBars.buttons["Chat"].tap()
        openList()
        XCTAssertFalse(button(beginsWith: "Delete LFM2.5-VL").exists, "nothing of it was downloaded")
        app.buttons["Done"].tap()
    }

    func test2DownloadsLoadsAndKeepsThinkingOutOfTheAnswer() throws {
        try XCTSkipUnless(Self.isIPhone18Pro, "LFM3's iPhone bundle is compiled for the iPhone 18 Pro")
        launch(catalog: "builtin")
        app.tabBars.buttons["Chat"].tap()
        let picker = app.buttons["chat.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 30))
        picker.tap()
        let row = button(beginsWith: "LFM3 1.7B (2164 MB)")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "LFM3 is offered with its size")
        shot("chat menu")
        row.tap()
        XCTAssertFalse(app.staticTexts["chat.unavailableReason"].exists, "no reason on this phone")
        app.buttons["chat.load"].tap()
        XCTAssertTrue(status("Ready", within: 1500), "LFM3 downloads and loads")
        shot("ready")

        // Thinking on (the default): the answer has no think marker, and the thinking sits in
        // its own disclosure.
        ask("What is 17 + 25? Answer briefly.")
        shot("thinking on")
        XCTAssertEqual(texts(containing: "<think>").count + texts(containing: "</think>").count, 0,
                       "no think marker on screen")
        XCTAssertTrue(app.buttons["Thinking"].firstMatch.exists
                      || app.disclosureTriangles["Thinking"].firstMatch.exists
                      || app.staticTexts["Thinking"].firstMatch.exists, "the thinking has its own place")
        let fortyTwo = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*\\b42\\b.*"))
        XCTAssertTrue(fortyTwo.firstMatch.exists, "the answer says 42")

        // Thinking off: a new chat's reply has no thinking at all.
        app.buttons["New"].tap()
        setThink(false)
        ask("What is the capital of Japan? Answer briefly.")
        shot("thinking off")
        XCTAssertEqual(texts(containing: "<think>").count + texts(containing: "</think>").count, 0)
        XCTAssertFalse(app.buttons["Thinking"].firstMatch.exists
                       || app.disclosureTriangles["Thinking"].firstMatch.exists, "no thinking")
        XCTAssertTrue(texts(containing: "Tokyo").firstMatch.exists, "the answer says Tokyo")
        setThink(true)

        openList()
        let listed = button(beginsWith: "Delete LFM3 1.7B")
        XCTAssertTrue(listed.exists, "LFM3 is in the downloaded-models list")
        NSLog("LFM3 listed: %@", listed.label)
        shot("list with lfm3")
        app.buttons["Done"].tap()
    }

    func test3DeleteRemovesTheBundle() throws {
        try XCTSkipUnless(Self.isIPhone18Pro, "test2 downloads it on the iPhone 18 Pro only")
        launch(catalog: "builtin")
        app.tabBars.buttons["Chat"].tap()
        openList()
        let delete = button(beginsWith: "Delete LFM3 1.7B")
        XCTAssertTrue(delete.exists, "LFM3 is listed")
        delete.tap()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "delete asks to confirm")
        shot("delete confirm")
        confirm.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: delete)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 20), .completed, "row gone after delete")
        shot("list after delete")
        app.buttons["Done"].tap()
    }
}
