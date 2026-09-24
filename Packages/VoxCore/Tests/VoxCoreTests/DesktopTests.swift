import XCTest
@testable import VoxCore

final class DesktopParsingTests: XCTestCase {
    let parser = CommandParser(config: .test)

    func testOpenApp() {
        XCTAssertEqual(parser.parse("open Safari"), .desktop([.openApp("Safari")], unparsed: nil))
        XCTAssertEqual(parser.parse("launch visual studio code"),
                       .desktop([.openApp("visual studio code")], unparsed: nil))
    }

    func testOpenAppAndCreateNote() {
        XCTAssertEqual(
            parser.parse("open the notes app and create a note called Groceries"),
            .desktop([.openApp("notes"), .createNote("Groceries")], unparsed: nil))
    }

    func testCreateNoteKeepsItsOwnAnds() {
        XCTAssertEqual(parser.parse("create a note saying buy eggs and milk"),
                       .desktop([.createNote("buy eggs and milk")], unparsed: nil))
        XCTAssertEqual(parser.parse("new note"), .desktop([.createNote("")], unparsed: nil))
    }

    func testToolWinsOverAppUnlessSaidApp() {
        XCTAssertEqual(parser.parse("open claude"), .launch(tool: "claude", project: nil, prompt: nil))
        XCTAssertEqual(parser.parse("open the claude app"), .desktop([.openApp("claude")], unparsed: nil))
    }

    func testRunIsOnlyForTools() {
        XCTAssertEqual(parser.parse("run safari"), .unknownTool(spoken: "safari"))
    }

    func testSearch() {
        XCTAssertEqual(parser.parse("search for swift concurrency"),
                       .desktop([.webSearch("swift concurrency")], unparsed: nil))
        XCTAssertEqual(parser.parse("open safari and google ethiopian coffee"),
                       .desktop([.openApp("safari"), .webSearch("ethiopian coffee")], unparsed: nil))
    }

    func testGoToWebsiteVersusFocusTool() {
        XCTAssertEqual(parser.parse("go to github dot com"),
                       .desktop([.openURL("github dot com")], unparsed: nil))
        XCTAssertEqual(parser.parse("go to claude"), .focus(tool: "claude"))
    }

    func testTypeAndPress() {
        XCTAssertEqual(
            parser.parse("type hello world and press enter"),
            .desktop([.typeText("hello world"), .pressKey(KeyCombo(key: "return"))], unparsed: nil))
        XCTAssertEqual(parser.parse("type fish and chips"),
                       .desktop([.typeText("fish and chips")], unparsed: nil))
        XCTAssertEqual(parser.parse("press command shift t"),
                       .desktop([.pressKey(KeyCombo(key: "t", modifiers: [.command, .shift]))], unparsed: nil))
    }

    func testUnparsedFollowUpIsReported() {
        XCTAssertEqual(parser.parse("open safari and do a dance"),
                       .desktop([.openApp("safari")], unparsed: "do a dance"))
    }

    func testLaunchToolPromptIsNotSplitIntoDesktopCommands() {
        XCTAssertEqual(parser.parse("run freebuff and type a haiku"),
                       .launch(tool: "freebuff", project: nil, prompt: "type a haiku"))
    }
}

final class DesktopRoutingTests: XCTestCase {
    func testDesktopCommandsDontLock() {
        var router = SessionRouter(config: .test)
        XCTAssertEqual(router.handle("open safari"), [.desktop(.openApp("safari"))])
        XCTAssertEqual(router.mode, .idle)
    }

    func testWhileLockedDesktopNeedsPrefix() {
        var router = SessionRouter(config: .test)
        _ = router.handle("run freebuff")
        XCTAssertEqual(router.handle("open safari"), [.send(tool: "freebuff", text: "open safari")])
        XCTAssertEqual(router.handle("vox open safari"), [.desktop(.openApp("safari"))])
        XCTAssertEqual(router.mode, .locked(tool: "freebuff"))
    }

    func testDestructiveTypingNeedsConfirmation() {
        var router = SessionRouter(config: .test)
        let asked = router.handle("type rm -rf build and press enter")
        guard case .askConfirmation = asked.first else { return XCTFail("\(asked)") }
        XCTAssertEqual(router.handle("yes"),
                       [.desktop(.typeText("rm -rf build")), .desktop(.pressKey(KeyCombo(key: "return")))])
    }

    func testUnparsedGetsFeedback() {
        var router = SessionRouter(config: .test)
        XCTAssertEqual(router.handle("open safari and do a dance"),
                       [.desktop(.openApp("safari")), .feedback("Didn't understand \"do a dance\".")])
    }
}

final class KeyComboTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(KeyCombo.parse("enter"), KeyCombo(key: "return"))
        XCTAssertEqual(KeyCombo.parse("the escape key"), KeyCombo(key: "escape"))
        XCTAssertEqual(KeyCombo.parse("cmd+s"), KeyCombo(key: "s", modifiers: [.command]))
        XCTAssertEqual(KeyCombo.parse("control option down arrow"),
                       KeyCombo(key: "down", modifiers: [.control, .option]))
        XCTAssertEqual(KeyCombo.parse("command one"), KeyCombo(key: "1", modifiers: [.command]))
    }

    func testRejectsNonsense() {
        XCTAssertNil(KeyCombo.parse("command"))
        XCTAssertNil(KeyCombo.parse("a b"))
        XCTAssertNil(KeyCombo.parse("the big red button please"))
    }

    func testDescription() {
        XCTAssertEqual(KeyCombo(key: "t", modifiers: [.shift, .command]).description, "shift+command+t")
    }
}

final class WebAddressTests: XCTestCase {
    func testSpokenAddresses() {
        XCTAssertEqual(WebAddress.url(fromSpoken: "github dot com")?.absoluteString, "https://github.com")
        XCTAssertEqual(WebAddress.url(fromSpoken: "GitHub.com.")?.absoluteString, "https://github.com")
        XCTAssertEqual(WebAddress.url(fromSpoken: "docs.swift.org slash documentation")?.absoluteString,
                       "https://docs.swift.org/documentation")
        XCTAssertEqual(WebAddress.url(fromSpoken: "http://example.com")?.absoluteString, "http://example.com")
    }

    func testRejectsNonAddresses() {
        XCTAssertNil(WebAddress.url(fromSpoken: "claude"))
        XCTAssertNil(WebAddress.url(fromSpoken: "the store"))
        XCTAssertNil(WebAddress.url(fromSpoken: "javascript:alert(1)"))
    }

    func testSearchURLEncodes() {
        XCTAssertEqual(WebAddress.searchURL(for: "c++ & swift").absoluteString,
                       "https://www.google.com/search?q=c%2B%2B%20%26%20swift")
    }
}

final class AppCatalogTests: XCTestCase {
    let catalog = AppCatalog.test

    func testExactAndSpokenForms() {
        XCTAssertEqual(catalog.find("safari")?.name, "Safari")
        XCTAssertEqual(catalog.find("the Notes app")?.name, "Notes")
        XCTAssertEqual(catalog.find("text edit")?.name, "TextEdit")
        XCTAssertEqual(catalog.find("vs code")?.name, "Visual Studio Code")
        XCTAssertEqual(catalog.find("chrome")?.name, "Google Chrome")
        XCTAssertEqual(catalog.find("settings")?.name, "System Settings")
    }

    func testPrefix() {
        XCTAssertEqual(catalog.find("visual studio")?.name, "Visual Studio Code")
        XCTAssertEqual(catalog.find("anti gravity")?.name, "Antigravity")
    }

    func testNoMatch() {
        XCTAssertNil(catalog.find("photoshop"))
        XCTAssertNil(catalog.find("x"))
    }

    func testScanFindsAppBundles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["Foo Bar.app", "Baz.app", "notes.txt"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(name),
                                                    withIntermediateDirectories: true)
        }
        let scanned = AppCatalog.scan(directories: [dir])
        XCTAssertTrue(scanned.names.contains("Foo Bar"))
        XCTAssertTrue(scanned.names.contains("Baz"))
        XCTAssertFalse(scanned.names.contains("notes"))
    }
}

final class DesktopEngineTests: XCTestCase {
    @MainActor
    func testOpenAppThenNote() async {
        let desktop = FakeDesktop()
        let engine = VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: FakeTmuxRunner()),
                               apps: .test, desktop: desktop, pause: { _ in })
        let events = await engine.handle("open notes and create a note called groceries")
        XCTAssertEqual(events.map(\.kind), [.success, .success])
        XCTAssertEqual(desktop.calls, [.openApp("Notes.app"), .createNote("groceries")])
    }

    @MainActor
    func testUnknownAppWarnsAndDoesNothing() async {
        let desktop = FakeDesktop()
        let engine = VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: FakeTmuxRunner()),
                               apps: .test, desktop: desktop, pause: { _ in })
        let events = await engine.handle("open photoshop")
        XCTAssertEqual(events.first?.kind, .warning)
        XCTAssertEqual(desktop.calls, [])
    }

    @MainActor
    func testSearchAndKeys() async {
        let desktop = FakeDesktop()
        let engine = VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: FakeTmuxRunner()),
                               apps: .test, desktop: desktop, pause: { _ in })
        _ = await engine.handle("search for addis ababa weather")
        _ = await engine.handle("type hi and press enter")
        XCTAssertEqual(desktop.calls, [
            .openURL("https://www.google.com/search?q=addis%20ababa%20weather"),
            .typeText("hi"),
            .pressKey("return")
        ])
    }

    func testNoDesktopControllerIsAnError() async {
        let engine = VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: FakeTmuxRunner()),
                               pause: { _ in })
        let events = await engine.handle("open safari")
        XCTAssertEqual(events.first?.kind, .error)
    }
}

final class MoreDesktopCommandTests: XCTestCase {
    let parser = CommandParser(config: .test)

    func testCloseAndQuitApps() {
        XCTAssertEqual(parser.parse("close safari"), .desktop([.quitApp("safari")], unparsed: nil))
        XCTAssertEqual(parser.parse("quit the notes app"), .desktop([.quitApp("notes")], unparsed: nil))
        XCTAssertEqual(parser.parse("close the claude app"), .desktop([.quitApp("claude")], unparsed: nil))
    }

    func testCloseToolStillKillsSession() {
        XCTAssertEqual(parser.parse("close freebuff"), .kill(tool: "freebuff"))
    }

    func testNamedShortcuts() {
        XCTAssertEqual(parser.parse("close tab"),
                       .desktop([.pressKey(KeyCombo(key: "w", modifiers: [.command]))], unparsed: nil))
        XCTAssertEqual(parser.parse("close this window"),
                       .desktop([.pressKey(KeyCombo(key: "w", modifiers: [.command]))], unparsed: nil))
        XCTAssertEqual(parser.parse("copy"),
                       .desktop([.pressKey(KeyCombo(key: "c", modifiers: [.command]))], unparsed: nil))
        XCTAssertEqual(parser.parse("scroll down"), .desktop([.pressKey(KeyCombo(key: "pagedown"))], unparsed: nil))
        XCTAssertEqual(parser.parse("exit full screen"),
                       .desktop([.pressKey(KeyCombo(key: "f", modifiers: [.control, .command]))], unparsed: nil))
    }

    func testShortcutsOnlyAsWholeClause() {
        // "go back to claude" is not the "go back" shortcut.
        XCTAssertEqual(parser.parse("back to claude"), .focus(tool: "claude"))
        XCTAssertEqual(parser.parse("save and close tab"), .desktop([
            .pressKey(KeyCombo(key: "s", modifiers: [.command])),
            .pressKey(KeyCombo(key: "w", modifiers: [.command]))
        ], unparsed: nil))
    }

    func testSwitchToAndHideApps() {
        XCTAssertEqual(parser.parse("switch to safari"), .desktop([.focusApp("safari")], unparsed: nil))
        XCTAssertEqual(parser.parse("go to notes"), .desktop([.focusApp("notes")], unparsed: nil))
        XCTAssertEqual(parser.parse("switch to claude"), .focus(tool: "claude"))
        XCTAssertEqual(parser.parse("hide slack"), .desktop([.hideApp("slack")], unparsed: nil))
        XCTAssertEqual(parser.parse("switch to safari and new tab"),
                       .desktop([.focusApp("safari"), .pressKey(KeyCombo(key: "t", modifiers: [.command]))],
                                unparsed: nil))
    }

    func testVolume() {
        XCTAssertEqual(parser.parse("volume up"), .desktop([.volume(.up)], unparsed: nil))
        XCTAssertEqual(parser.parse("turn down the volume"), .desktop([.volume(.down)], unparsed: nil))
        XCTAssertEqual(parser.parse("mute"), .desktop([.volume(.mute)], unparsed: nil))
        XCTAssertEqual(parser.parse("set volume to 30%"), .desktop([.volume(.set(30))], unparsed: nil))
        XCTAssertEqual(parser.parse("volume 70 percent"), .desktop([.volume(.set(70))], unparsed: nil))
    }

    func testCancelAndHelp() {
        XCTAssertEqual(parser.parse("never mind"), .cancel)
        XCTAssertEqual(parser.parse("what can you do"), .help)
    }

    func testKeyComboPageKeys() {
        XCTAssertEqual(KeyCombo.parse("page down"), KeyCombo(key: "pagedown"))
        XCTAssertEqual(KeyCombo.parse("command page up"), KeyCombo(key: "pageup", modifiers: [.command]))
    }

    func testEveryNamedShortcutUsesASendableKey() {
        let letters = Set("abcdefghijklmnopqrstuvwxyz0123456789".map(String.init))
        for entry in KeyCombo.named {
            XCTAssertTrue(letters.contains(entry.combo.key) || KeyCombo.specialKeys.contains(entry.combo.key),
                          "\(entry.phrases[0]) uses unknown key \(entry.combo.key)")
        }
    }

    @MainActor
    func testEngineQuitHideVolume() async {
        let desktop = FakeDesktop()
        desktop.running = ["Safari.app"]
        let engine = VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: FakeTmuxRunner()),
                               apps: .test, desktop: desktop, pause: { _ in })
        let quit = await engine.handle("close safari")
        XCTAssertEqual(quit.first?.message, "Quit Safari.")
        let notRunning = await engine.handle("quit notes")
        XCTAssertEqual(notRunning.first?.message, "Notes isn't running.")
        _ = await engine.handle("set volume to 25")
        XCTAssertEqual(desktop.calls.last, .volume(.set(25)))
    }

    func testRouterCancelAndHelp() {
        var router = SessionRouter(config: .test)
        XCTAssertEqual(router.handle("cancel"), [.feedback("OK.")])
        XCTAssertEqual(router.handle("help"), [.feedback(SessionRouter.helpText)])
    }
}
