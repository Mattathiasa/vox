import XCTest
@testable import VoxCore

final class MoreCommandParsingTests: XCTestCase {
    let parser = CommandParser(config: .test)

    private func desktop(_ text: String) -> [DesktopCommand]? {
        if case let .desktop(commands, nil) = parser.parse(text) { return commands }
        return nil
    }

    func testMedia() {
        XCTAssertEqual(desktop("pause"), [.media(.playPause)])
        XCTAssertEqual(desktop("next song"), [.media(.next)])
        XCTAssertEqual(desktop("previous track"), [.media(.previous)])
        XCTAssertEqual(desktop("next tab"), [.pressKey(KeyCombo(key: "tab", modifiers: [.control]))])
    }

    func testQuestions() {
        XCTAssertEqual(desktop("what time is it"), [.answer(.time)])
        XCTAssertEqual(desktop("what's the date"), [.answer(.date)])
        XCTAssertEqual(desktop("how much battery do I have"), [.answer(.battery)])
        XCTAssertEqual(desktop("what's on my clipboard"), [.answer(.clipboard)])
        XCTAssertEqual(desktop("what apps are open"), [.answer(.openApps)])
    }

    func testMath() {
        XCTAssertEqual(desktop("what's 12 times 8"), [.answer(.calculation("12 times 8"))])
        XCTAssertEqual(desktop("calculate 15 percent of 80"), [.answer(.calculation("15 percent of 80"))])
        XCTAssertEqual(desktop("12 plus 30"), [.answer(.calculation("12 plus 30"))])
        XCTAssertNil(desktop("what's up"))
    }

    func testTimers() {
        XCTAssertEqual(desktop("set a timer for 5 minutes"), [.timer(seconds: 300)])
        XCTAssertEqual(desktop("set a timer for an hour and a half"), [.timer(seconds: 5400)])
        XCTAssertEqual(desktop("10 minute timer"), [.timer(seconds: 600)])
        XCTAssertEqual(desktop("cancel the timer"), [.cancelTimers])
        XCTAssertEqual(desktop("stop the timer"), [.cancelTimers], "not 'quit an app called timer'")
    }

    func testReminders() {
        XCTAssertEqual(desktop("remind me to call mom in 10 minutes"), [.reminder("call mom", inSeconds: 600)])
        XCTAssertEqual(desktop("remind me in half an hour to stretch"), [.reminder("stretch", inSeconds: 1800)])
        XCTAssertEqual(desktop("remind me to buy injera"), [.reminder("buy injera", inSeconds: nil)])
    }

    func testFoldersAndProjects() {
        XCTAssertEqual(desktop("open downloads"), [.openFolder("downloads")])
        XCTAssertEqual(desktop("open the music folder"), [.openFolder("music")])
        XCTAssertEqual(desktop("open music"), [.openApp("music")], "Music the app, not the folder")
        XCTAssertEqual(desktop("open the chirp project"), [.openFolder("chirp")])
        XCTAssertEqual(desktop("open chirp in kiro"), [.openProject(project: "chirp", app: "kiro")])
        XCTAssertEqual(desktop("open the bible study project in visual studio code"),
                       [.openProject(project: "cbs", app: "visual studio code")])
        XCTAssertEqual(parser.parse("open freebuff in chirp"), .launch(tool: "freebuff", project: "chirp", prompt: nil))
    }

    func testSiteSearches() {
        XCTAssertEqual(desktop("search youtube for lofi beats"), [.siteSearch(.youtube, "lofi beats")])
        XCTAssertEqual(desktop("play teddy afro on youtube"), [.siteSearch(.youtube, "teddy afro")])
        XCTAssertEqual(desktop("search for swiftui navigation on github"), [.siteSearch(.github, "swiftui navigation")])
        XCTAssertEqual(desktop("directions to bole airport"), [.siteSearch(.maps, "bole airport")])
        XCTAssertEqual(desktop("search for swift concurrency"), [.webSearch("swift concurrency")])
    }

    func testSystem() {
        XCTAssertEqual(desktop("dark mode"), [.system(.darkMode(nil))])
        XCTAssertEqual(desktop("turn off dark mode"), [.system(.darkMode(false))])
        XCTAssertEqual(desktop("turn off the screen"), [.system(.screenOff)])
        XCTAssertEqual(desktop("lock screen"), [.pressKey(KeyCombo(key: "q", modifiers: [.control, .command]))])
        XCTAssertEqual(desktop("spotlight"), [.pressKey(KeyCombo(key: "space", modifiers: [.command]))])
    }

    func testToolControl() {
        XCTAssertEqual(parser.parse("interrupt"), .interrupt(tool: nil))
        XCTAssertEqual(parser.parse("interrupt freebuff"), .interrupt(tool: "freebuff"))
        XCTAssertEqual(parser.parse("restart freebuff"), .restart(tool: "freebuff"))
        XCTAssertEqual(parser.parse("show freebuff"), .showTool("freebuff"))
        XCTAssertEqual(parser.parse("stop freebuff"), .kill(tool: "freebuff"))
        XCTAssertEqual(desktop("reload"), [.pressKey(KeyCombo(key: "r", modifiers: [.command]))])
    }
}

final class MoreCommandRoutingTests: XCTestCase {
    func testInterruptWhileLockedNeedsNoPrefix() {
        var router = SessionRouter(config: .test)
        _ = router.handle("run freebuff")
        XCTAssertEqual(router.handle("stop generating"), [.interrupt(tool: "freebuff")])
        XCTAssertEqual(router.mode, .locked(tool: "freebuff"))
    }

    func testRestartConfirmsThenKillsAndLaunches() {
        var router = SessionRouter(config: .test)
        guard case .askConfirmation = router.handle("restart freebuff").first else { return XCTFail() }
        XCTAssertEqual(router.handle("yes"), [
            .kill(tool: "freebuff"),
            .launch(tool: "freebuff", directory: "~/Projects", initialPrompt: nil)
        ])
        XCTAssertEqual(router.mode, .locked(tool: "freebuff"))
    }
}

final class SpokenValueTests: XCTestCase {
    func testDurations() {
        XCTAssertEqual(SpokenDuration.seconds(in: "5 minutes"), 300)
        XCTAssertEqual(SpokenDuration.seconds(in: "1 hour 30 minutes"), 5400)
        XCTAssertEqual(SpokenDuration.seconds(in: "an hour and a half"), 5400)
        XCTAssertEqual(SpokenDuration.seconds(in: "half an hour"), 1800)
        XCTAssertEqual(SpokenDuration.seconds(in: "90 seconds"), 90)
        XCTAssertEqual(SpokenDuration.seconds(in: "a couple of minutes"), 120)
        XCTAssertEqual(SpokenDuration.seconds(in: "ten minutes"), 600)
        XCTAssertNil(SpokenDuration.seconds(in: "soon"))
        XCTAssertEqual(SpokenDuration.describe(5400), "1 hour 30 minutes")
    }

    func testMath() {
        XCTAssertEqual(SpokenMath.evaluate("12 times 8"), 96)
        XCTAssertEqual(SpokenMath.evaluate("2 plus 3 times 4"), 14)
        XCTAssertEqual(SpokenMath.evaluate("100 divided by 8"), 12.5)
        XCTAssertEqual(SpokenMath.evaluate("15 percent of 80"), 12)
        XCTAssertEqual(SpokenMath.evaluate("square root of 144"), 12)
        XCTAssertEqual(SpokenMath.evaluate("7 squared"), 49)
        XCTAssertEqual(SpokenMath.evaluate("12 × 3"), 36)
        XCTAssertEqual(SpokenMath.evaluate("what's 10 - 4"), 6)
        XCTAssertNil(SpokenMath.evaluate("5 divided by 0"))
        XCTAssertNil(SpokenMath.evaluate("up"))
        XCTAssertNil(SpokenMath.evaluate("5"))
        XCTAssertEqual(SpokenMath.format(12.5), "12.5")
        XCTAssertEqual(SpokenMath.format(96), "96")
    }

    func testBattery() {
        XCTAssertEqual(BatteryReport.describe("-InternalBattery-0 (id=1)\t82%; discharging; 3:10 remaining present: true"),
                       "Battery is at 82%, about 3 hours 10 minutes left.")
        XCTAssertEqual(BatteryReport.describe("Now drawing from 'AC Power'\n -InternalBattery-0\t100%; charged; 0:00 remaining"),
                       "Battery is at 100%, fully charged.")
        XCTAssertEqual(BatteryReport.describe("-InternalBattery-0\t45%; charging; 1:20 remaining"),
                       "Battery is at 45% and charging.")
        XCTAssertEqual(BatteryReport.describe("Now drawing from 'AC Power'"), "This Mac doesn't report a battery.")
    }

    func testKnownSites() {
        XCTAssertEqual(WebAddress.knownSite("youtube")?.absoluteString, "https://www.youtube.com")
        XCTAssertEqual(WebAddress.knownSite("gmail")?.absoluteString, "https://mail.google.com")
        XCTAssertNil(WebAddress.knownSite("photoshop"))
    }
}

final class MoreCommandEngineTests: XCTestCase {
    @MainActor
    private func makeEngine(_ desktop: FakeDesktop, runner: FakeTmuxRunner = FakeTmuxRunner()) -> VoxEngine {
        VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: runner),
                  apps: .test, desktop: desktop, pause: { _ in })
    }

    @MainActor
    func testAnswers() async {
        let desktop = FakeDesktop()
        let engine = makeEngine(desktop)
        let math = await engine.handle("what's 12 times 8")
        XCTAssertEqual(math.first?.message, "That's 96.")
        let battery = await engine.handle("battery")
        XCTAssertEqual(battery.first?.message, "Battery is at 82%, about 3 hours 10 minutes left.")
        let apps = await engine.handle("what apps are open")
        XCTAssertEqual(apps.first?.message, "Open apps: Safari, Notes.")
        let clip = await engine.handle("read clipboard")
        XCTAssertEqual(clip.first?.message, "Your clipboard says: hello from the clipboard")
    }

    @MainActor
    func testOpenFallsBackToWebsiteAndProject() async {
        let desktop = FakeDesktop()
        let engine = makeEngine(desktop)
        _ = await engine.handle("open youtube")
        _ = await engine.handle("open chirp")
        XCTAssertEqual(desktop.calls.count, 2)
        XCTAssertEqual(desktop.calls.first, .openURL("https://www.youtube.com"))
        guard case let .openURL(folder) = desktop.calls.last else { return XCTFail() }
        XCTAssertTrue(folder.hasSuffix("/Projects/chirp/") || folder.hasSuffix("/Projects/chirp"), folder)
    }

    @MainActor
    func testTimersRemindersProjects() async {
        let desktop = FakeDesktop()
        let engine = makeEngine(desktop)
        let set = await engine.handle("set a timer for 90 seconds")
        XCTAssertEqual(set.first?.message, "Timer set for 1 minute 30 seconds.")
        let cancel = await engine.handle("cancel the timer")
        XCTAssertEqual(cancel.first?.message, "Cancelled 1 timer.")
        _ = await engine.handle("remind me to stretch in 5 minutes")
        _ = await engine.handle("open chirp in kiro")
        XCTAssertTrue(desktop.calls.contains(.reminder("stretch", 300)))
        XCTAssertTrue(desktop.calls.contains(.openWith("chirp", "Kiro.app")))
    }

    @MainActor
    func testInterruptAndShowTool() async {
        let desktop = FakeDesktop()
        let runner = FakeTmuxRunner()
        runner.sessions = ["vox-freebuff"]
        let engine = makeEngine(desktop, runner: runner)
        _ = await engine.handle("interrupt freebuff")
        XCTAssertEqual(runner.calls.last, ["send-keys", "-t", "vox-freebuff:", "C-c"])
        _ = await engine.handle("show freebuff")
        XCTAssertEqual(desktop.calls.last, .terminal("tmux -L vox attach -t vox-freebuff"))
    }
}
