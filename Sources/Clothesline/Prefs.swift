import AppKit
import Carbon.HIToolbox

enum Shortcut: Int, CaseIterable, Identifiable {
    case shiftCmdV, ctrlOptV, ctrlShiftSpace

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .shiftCmdV: return "⇧⌘V"
        case .ctrlOptV: return "⌃⌥V"
        case .ctrlShiftSpace: return "⌃⇧Space"
        }
    }
    var keyCode: UInt32 {
        switch self {
        case .shiftCmdV, .ctrlOptV: return UInt32(kVK_ANSI_V)
        case .ctrlShiftSpace: return UInt32(kVK_Space)
        }
    }
    var modifiers: UInt32 {
        switch self {
        case .shiftCmdV: return UInt32(cmdKey | shiftKey)
        case .ctrlOptV: return UInt32(controlKey | optionKey)
        case .ctrlShiftSpace: return UInt32(controlKey | shiftKey)
        }
    }
}

/// Apps whose copies never go on the line (password managers by default).
let defaultIgnoredApps = [
    "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
    "com.apple.Passwords", "com.apple.keychainaccess", "com.lastpass.LastPass",
    "com.dashlane.dashlanephonefinal", "org.keepassxc.keepassxc",
]

@Observable @MainActor
final class Prefs {
    static let shared = Prefs()
    @ObservationIgnored private let d = UserDefaults.standard
    @ObservationIgnored var onShortcutChange: () -> Void = {}

    var paused: Bool { didSet { d.set(paused, forKey: "paused") } }
    var revealOnEdge: Bool { didSet { d.set(revealOnEdge, forKey: "revealOnEdge") } }
    var peekOnCopy: Bool { didSet { d.set(peekOnCopy, forKey: "peekOnCopy") } }
    var autoPaste: Bool { didSet { d.set(autoPaste, forKey: "autoPaste") } }
    var inboxCapacity: Int { didSet { d.set(inboxCapacity, forKey: "inboxCapacity") } }
    var historyLimit: Int { didSet { d.set(historyLimit, forKey: "historyLimit") } }
    var ignoredApps: [String] { didSet { d.set(ignoredApps, forKey: "ignoredApps") } }
    var shortcut: Shortcut {
        didSet { d.set(shortcut.rawValue, forKey: "shortcut"); onShortcutChange() }
    }
    var onboarded: Bool { didSet { d.set(onboarded, forKey: "onboarded") } }
    var pegSound: Bool { didSet { d.set(pegSound, forKey: "pegSound") } }
    var fairyLights: Bool { didSet { d.set(fairyLights, forKey: "fairyLights") } }
    /// Minutes before a secret-looking Inbox clip is removed; 0 keeps them.
    var secretMinutes: Int { didSet { d.set(secretMinutes, forKey: "secretMinutes") } }

    private init() {
        d.register(defaults: [
            "revealOnEdge": true, "peekOnCopy": true, "autoPaste": true,
            "inboxCapacity": 16, "historyLimit": 500, "ignoredApps": defaultIgnoredApps,
            "pegSound": true, "secretMinutes": 2, "fairyLights": true,
        ])
        paused = d.bool(forKey: "paused")
        revealOnEdge = d.bool(forKey: "revealOnEdge")
        peekOnCopy = d.bool(forKey: "peekOnCopy")
        autoPaste = d.bool(forKey: "autoPaste")
        inboxCapacity = d.integer(forKey: "inboxCapacity")
        historyLimit = d.integer(forKey: "historyLimit")
        ignoredApps = d.stringArray(forKey: "ignoredApps") ?? defaultIgnoredApps
        shortcut = Shortcut(rawValue: d.integer(forKey: "shortcut")) ?? .shiftCmdV
        onboarded = d.bool(forKey: "onboarded")
        pegSound = d.bool(forKey: "pegSound")
        fairyLights = d.bool(forKey: "fairyLights")
        secretMinutes = d.integer(forKey: "secretMinutes")
    }
}
