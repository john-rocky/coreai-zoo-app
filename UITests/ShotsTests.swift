// ShotsTests — drives CoreAI Zoo on a real iPhone and attaches App Store screenshots.
// Each test reaches one screen state, then attaches a full-resolution screenshot named NN_*.
// Export with: xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>

import XCTest

final class ShotsTests: XCTestCase {
    var app: XCUIApplication!
    let long: TimeInterval = 1200   // model downloads
    let gen: TimeInterval = 400     // one generation

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 30)
    }

    // MARK: helpers

    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        NSLog("SHOT %@", name)
    }

    func dump(_ tag: String) {
        NSLog("HIERARCHY %@\n%@", tag, app.debugDescription)
    }

    func tab(_ name: String) {
        let b = app.tabBars.buttons[name]
        XCTAssertTrue(b.waitForExistence(timeout: 20), "tab \(name)")
        b.tap()
        sleep(2)
    }

    func waitEnabled(_ e: XCUIElement, _ timeout: TimeInterval, _ what: String) {
        let p = NSPredicate(format: "exists == true AND isEnabled == true")
        let r = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: timeout)
        XCTAssertEqual(r, .completed, "\(what) did not become enabled in \(Int(timeout))s")
    }

    func waitGone(_ e: XCUIElement, _ timeout: TimeInterval, _ what: String) {
        let p = NSPredicate(format: "exists == false")
        let r = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: timeout)
        XCTAssertEqual(r, .completed, "\(what) still present after \(Int(timeout))s")
    }

    func waitText(containing s: String, _ timeout: TimeInterval) -> Bool {
        let q = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s))
        return q.firstMatch.waitForExistence(timeout: timeout)
    }

    /// Opens the model menu/picker whose trigger currently shows `current` (or any of the
    /// candidates) and picks the item whose label begins with `wanted`.
    func pick(wanted: String, triggerCandidates: [String]) {
        // Already selected?
        if app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", wanted)).firstMatch.exists { return }
        var trigger: XCUIElement?
        for c in triggerCandidates {
            let q = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", c)).firstMatch
            if q.exists { trigger = q; break }
        }
        guard let t = trigger else { dump("no trigger for \(wanted)"); XCTFail("picker trigger"); return }
        t.tap()
        let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", wanted)).firstMatch
        if !item.waitForExistence(timeout: 10) {
            // menu items sometimes surface as static texts / cells
            let alt = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", wanted)).firstMatch
            if alt.waitForExistence(timeout: 5) { alt.tap(); return }
            dump("no item \(wanted)"); XCTFail("picker item \(wanted)"); return
        }
        item.tap()
        sleep(1)
    }

    func allowSystemAlert() {
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "OK", "Allow While Using App", "Allow Full Access"] {
            let b = sb.buttons[label]
            if b.waitForExistence(timeout: 3) { b.tap(); return }
        }
    }

    // MARK: tests (alphabetical order = execution order)

    func test1Chat() {
        tab("Chat")
        _ = app.buttons["Download & Load"].waitForExistence(timeout: 60) || app.buttons["Reload"].waitForExistence(timeout: 5)
        sleep(2)
        pick(wanted: "Qwen3 0.6B", triggerCandidates: ["Model", "Qwen", "Gemma", "LFM", "Mistral", "Granite", "MiniCPM", "Nanbeige", "Nemotron", "Youtu", "GLM"])
        // model menu open state for a screenshot
        let field = app.textFields["Message"]
        if !field.isEnabled {
            let load = app.buttons["Download & Load"].exists ? app.buttons["Download & Load"] : app.buttons["Reload"]
            load.tap()
        }
        waitEnabled(field, long, "chat field")
        field.tap()
        field.typeText("Write a haiku about a model running on a phone.\n")
        _ = app.buttons["Stop"].waitForExistence(timeout: 20)
        waitGone(app.buttons["Stop"], gen, "chat generation")
        // dismiss keyboard by leaving and returning
        tab("Bench"); tab("Chat")
        sleep(1)
        shot("01_chat")
        // model list
        let trig = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Qwen3 0.6B'")).firstMatch
        if trig.exists { trig.tap(); sleep(1); shot("02_chat_models"); app.tabBars.firstMatch.tap() }
    }

    func test2Vision() {
        tab("Vision")
        _ = app.buttons["Download & Load"].waitForExistence(timeout: 60)
        sleep(2)
        pick(wanted: "LFM2.5-VL 450M", triggerCandidates: ["Model", "Qwen", "LFM", "MiniCPM", "Holo", "North"])
        app.buttons["Download & Load"].tap()
        let choose = app.buttons["Choose Photo"]
        waitEnabled(choose, long, "vision model")
        choose.tap()
        sleep(4)
        allowSystemAlert()
        for label in ["Continue", "OK", "Done", "Got It"] {
            let b = app.buttons[label]
            if b.waitForExistence(timeout: 3) { b.tap(); sleep(2); break }
        }
        sleep(2)
        shot("90_picker_debug")
        // The PHPicker content is out-of-process and opaque to the host hierarchy, so tap the
        // first grid cell by normalized coordinates (portrait iPhone: grid starts under the
        // picker header; first cell is at the top-left of the grid).
        let candidates: [(Double, Double)] = [(0.12, 0.19), (0.12, 0.23), (0.12, 0.27), (0.12, 0.15), (0.36, 0.19)]
        for (x, y) in candidates {
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
            if app.buttons["Change Photo"].waitForExistence(timeout: 8) { NSLog("PICKED at %.2f %.2f", x, y); break }
            if app.buttons["Choose Photo"].exists && app.buttons["Choose Photo"].isHittable {
                // picker got dismissed without a selection; reopen
                app.buttons["Choose Photo"].tap(); sleep(3)
            }
        }
        _ = app.buttons["Change Photo"].waitForExistence(timeout: 30)
        let field = app.textFields.firstMatch
        waitEnabled(field, 60, "vision field")
        field.tap()
        field.typeText("What is in this photo?\n")
        _ = app.buttons["Stop"].waitForExistence(timeout: 30)
        waitGone(app.buttons["Stop"], gen, "vision generation")
        tab("Bench"); tab("Vision")
        sleep(1)
        shot("03_vision")
    }

    func test3Camera() {
        tab("Camera")
        allowSystemAlert()
        sleep(3)
        allowSystemAlert()
        _ = waitText(containing: "ms/frame", 300)
        sleep(3)
        shot("04_camera_depth")
        let detect = app.buttons["Detect"].exists ? app.buttons["Detect"] : app.segmentedControls.buttons["Detect"]
        if detect.exists { detect.tap(); _ = waitText(containing: "ms/frame", 300); sleep(4); shot("05_camera_detect") }
    }

    func test4Audio() {
        tab("Audio")
        _ = app.buttons["Download & Load"].waitForExistence(timeout: 60)
        sleep(2)
        app.buttons["Download & Load"].tap()
        let speakButtons = app.buttons.matching(identifier: "Speak")
        _ = speakButtons.firstMatch.waitForExistence(timeout: 30)
        let speak = speakButtons.element(boundBy: max(0, speakButtons.count - 1))
        waitEnabled(speak, long, "tts model")
        speak.tap()
        _ = waitText(containing: "s of audio", 300)
        sleep(1)
        shot("06_audio_speak")
    }

    func test5Bench() {
        tab("Bench")
        _ = app.buttons["Run benchmark"].waitForExistence(timeout: 60)
        sleep(2)
        pick(wanted: "Qwen3 0.6B", triggerCandidates: ["Model", "Qwen", "Gemma", "LFM", "Mistral", "Granite", "MiniCPM", "Nanbeige", "Nemotron", "Youtu", "GLM"])
        app.buttons["Run benchmark"].tap()
        sleep(5)
        waitEnabled(app.buttons["Run benchmark"], 900, "benchmark finished")
        sleep(2)
        shot("07_bench")
    }
}
