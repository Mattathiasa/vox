import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Hold to talk, release to run. A quick tap opens the panel for typing.
    /// (Keeps the old "togglePanel" id so an existing custom shortcut survives.)
    static let talk = Self("togglePanel", default: .init(.space, modifiers: [.option]))
}

@MainActor
enum Hotkeys {
    static func register(onPress: @escaping @MainActor () -> Void,
                         onRelease: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .talk) {
            Task { @MainActor in onPress() }
        }
        KeyboardShortcuts.onKeyUp(for: .talk) {
            Task { @MainActor in onRelease() }
        }
    }
}
