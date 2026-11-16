import AppKit
import CryptoKit
import Foundation

enum ClipKind: String, Codable {
    case text, link, color, image, files
}

struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: ClipKind
    /// Text, link or colour string.
    var text: String?
    /// File paths for `.files`.
    var paths: [String]?
    /// Base name of the image in `blobs/` (`<blob>.png` full size, `<blob>.jpg` thumbnail).
    var blob: String?
    var imageSize: CGSize?
    var sourceBundleID: String?
    var created: Date = .now
    /// Set when the clip is hung on a line other than the Inbox.
    var lineID: UUID?
    var pinnedAt: Date?
    var hash: String
    /// Looks like a key, token or password: shown masked and removed after a while.
    var secret: Bool?
    /// Base name of the formatted copy in `blobs/` (`<rich>.rtf` and/or `<rich>.html`).
    var rich: String?

    var isSecret: Bool { secret == true }

    @MainActor var searchBlob: String {
        var s = kind.rawValue + " "
        switch kind {
        case .files: s += (paths ?? []).joined(separator: " ")
        default: s += text ?? ""
        }
        if let n = AppIcons.name(sourceBundleID) { s += " " + n }
        return s.lowercased()
    }

    var looksLikeCode: Bool {
        guard kind == .text, let t = text else { return false }
        let markers = ["{", "}", ";", "=>", "()", "</", "import ", "func ", "const ", "let ", "def ", "$ ", "npm ", "git "]
        let hits = markers.filter { t.contains($0) }.count
        return hits >= 2 || t.hasPrefix("    ") || t.hasPrefix("\t")
    }
}

struct Line: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var hue: Double
}

enum Hash {
    static func of(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func of(_ s: String) -> String { of(Data(s.utf8)) }
}

@Observable @MainActor
final class Store {
    static let inboxID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var clips: [Clip] = []   // newest first
    var lines: [Line] = []

    @ObservationIgnored let dir: URL
    @ObservationIgnored let blobsDir: URL
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private let thumbs = NSCache<NSString, NSImage>()

    init() {
        if let custom = ProcessInfo.processInfo.environment["CLOTHESLINE_DATA"] {
            dir = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Clothesline", isDirectory: true)
        }
        blobsDir = dir.appendingPathComponent("blobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: blobsDir, withIntermediateDirectories: true)
    }

    private struct Saved: Codable {
        var clips: [Clip]
        var lines: [Line]
    }

    private var fileURL: URL { dir.appendingPathComponent("clothesline.json") }

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            clips = saved.clips
            lines = saved.lines
        } else {
            lines = [Line(name: "Work", hue: 0.58), Line(name: "Snippets", hue: 0.36)]
            save()
        }
    }

    func save() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        let saved = Saved(clips: clips, lines: lines)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Queries

    var inboxCapacity: Int { Prefs.shared.inboxCapacity }

    func clips(on line: UUID) -> [Clip] {
        if line == Store.inboxID {
            return Array(clips.lazy.filter { $0.lineID == nil }.prefix(inboxCapacity))
        }
        return clips.filter { $0.lineID == line }
            .sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
    }

    func count(on line: UUID) -> Int {
        line == Store.inboxID ? min(inboxCapacity, clips.filter { $0.lineID == nil }.count)
                              : clips.filter { $0.lineID == line }.count
    }

    /// Unpinned clips that no longer fit on the Inbox line.
    var basketCount: Int { max(0, clips.filter { $0.lineID == nil }.count - inboxCapacity) }

    func line(_ id: UUID?) -> Line? { lines.first { $0.id == id } }

    func contains(hash: String) -> Bool { clips.contains { $0.hash == hash } }

    // MARK: Changes

    /// Adds a clip, or brings an identical one back to the front of the Inbox.
    @discardableResult
    func add(_ clip: Clip) -> Clip {
        if let i = clips.firstIndex(where: { $0.hash == clip.hash }) {
            var existing = clips.remove(at: i)
            if existing.lineID == nil { existing.created = .now }
            if let b = clip.blob, b != existing.blob { removeBlob(b) }
            if let r = clip.rich, r != existing.rich {
                if existing.rich == nil { existing.rich = r } else { removeRich(r) }
            }
            clips.insert(existing, at: 0)
            save()
            return existing
        }
        clips.insert(clip, at: 0)
        prune()
        save()
        return clip
    }

    func hang(_ id: UUID, on line: UUID) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        var c = clips.remove(at: i)
        if line == Store.inboxID {
            c.lineID = nil
            c.pinnedAt = nil
            c.created = .now
        } else {
            c.lineID = line
            c.pinnedAt = .now
        }
        clips.insert(c, at: 0)
        save()
    }

    func delete(_ id: UUID) {
        guard let removed = remove(id) else { return }
        purgeFiles(removed.0)
    }

    /// Takes a clip out but keeps its files, so it can be put back.
    func remove(_ id: UUID) -> (Clip, Int)? {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return nil }
        let c = clips.remove(at: i)
        save()
        return (c, i)
    }

    func restore(_ clip: Clip, at index: Int) {
        guard !clips.contains(where: { $0.id == clip.id }) else { return }
        clips.insert(clip, at: min(index, clips.count))
        save()
    }

    func purgeFiles(_ c: Clip) {
        // Another clip may share the files (same image copied twice is deduplicated, but be safe).
        if let b = c.blob, !clips.contains(where: { $0.blob == b }) { removeBlob(b) }
        if let r = c.rich, !clips.contains(where: { $0.rich == r }) { removeRich(r) }
    }

    /// Puts `id` just before `target` on a line (or at the end when `target` is nil).
    func move(_ id: UUID, before target: UUID?, on line: UUID) {
        if line == Store.inboxID {
            // The Inbox follows the order of `clips`, so move it there.
            let shown = clips(on: line).map(\.id).filter { $0 != id }
            guard let from = clips.firstIndex(where: { $0.id == id }) else { return }
            var c = clips.remove(at: from)
            c.lineID = nil
            c.pinnedAt = nil
            let anchor = target ?? shown.last
            var at = anchor.flatMap { a in clips.firstIndex { $0.id == a } } ?? clips.count
            if target == nil, anchor != nil { at += 1 }
            clips.insert(c, at: min(at, clips.count))
            save()
            return
        }
        var order = clips(on: line).map(\.id).filter { $0 != id }
        let at = target.flatMap { t in order.firstIndex(of: t) } ?? order.count
        order.insert(id, at: at)
        let now = Date()
        for (n, cid) in order.enumerated() {
            guard let i = clips.firstIndex(where: { $0.id == cid }) else { continue }
            clips[i].lineID = line
            clips[i].pinnedAt = now.addingTimeInterval(-Double(n))
        }
        save()
    }

    /// Inbox secrets older than `age`. Secrets you hung on a line yourself stay.
    func expiredSecrets(olderThan age: TimeInterval) -> [Clip] {
        let cutoff = Date().addingTimeInterval(-age)
        return clips.filter { $0.isSecret && $0.lineID == nil && $0.created < cutoff }
    }

    func clearBasket() {
        let unpinned = clips.filter { $0.lineID == nil }
        for c in unpinned.dropFirst(inboxCapacity) { delete(c.id) }
    }

    @discardableResult
    func addLine(named name: String) -> Line {
        let used = Set(lines.map { Int($0.hue * 12) })
        let hue = (0..<12).map { Double($0) / 12 }.first { !used.contains(Int($0 * 12)) } ?? Double.random(in: 0...1)
        let l = Line(name: name, hue: hue)
        lines.append(l)
        save()
        return l
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { lines[i].name = n }
        save()
    }

    func deleteLine(_ id: UUID) {
        for i in clips.indices where clips[i].lineID == id {
            clips[i].lineID = nil
            clips[i].pinnedAt = nil
        }
        lines.removeAll { $0.id == id }
        save()
    }

    private func prune() {
        let limit = Prefs.shared.historyLimit
        var unpinnedSeen = 0
        var drop: [UUID] = []
        for c in clips where c.lineID == nil {
            unpinnedSeen += 1
            if unpinnedSeen > limit { drop.append(c.id) }
        }
        for id in drop { delete(id) }
    }

    // MARK: Images

    func blobURL(_ blob: String) -> URL { blobsDir.appendingPathComponent(blob + ".png") }
    func thumbURL(_ blob: String) -> URL { blobsDir.appendingPathComponent(blob + ".jpg") }
    func rtfURL(_ rich: String) -> URL { blobsDir.appendingPathComponent(rich + ".rtf") }
    func htmlURL(_ rich: String) -> URL { blobsDir.appendingPathComponent(rich + ".html") }

    private func removeRich(_ r: String) {
        try? FileManager.default.removeItem(at: rtfURL(r))
        try? FileManager.default.removeItem(at: htmlURL(r))
    }

    func thumbnail(_ clip: Clip) -> NSImage? {
        guard let b = clip.blob else { return nil }
        if let img = thumbs.object(forKey: b as NSString) { return img }
        let img = NSImage(contentsOf: thumbURL(b)) ?? NSImage(contentsOf: blobURL(b))
        if let img { thumbs.setObject(img, forKey: b as NSString) }
        return img
    }

    private func removeBlob(_ b: String) {
        try? FileManager.default.removeItem(at: blobURL(b))
        try? FileManager.default.removeItem(at: thumbURL(b))
        thumbs.removeObject(forKey: b as NSString)
    }
}

@MainActor
enum AppIcons {
    private static var icons: [String: NSImage] = [:]
    private static var names: [String: String] = [:]

    static func icon(_ bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let i = icons[bundleID] { return i }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let i = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = i
        return i
    }

    static func name(_ bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        if let n = names[bundleID] { return n }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let n = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        names[bundleID] = n
        return n
    }
}

func ago(_ date: Date) -> String {
    let s = Int(Date().timeIntervalSince(date))
    if s < 45 { return "now" }
    if s < 3600 { return "\(max(1, s / 60))m" }
    if s < 86400 { return "\(s / 3600)h" }
    if s < 86400 * 7 { return "\(s / 86400)d" }
    let f = DateFormatter()
    f.dateFormat = "d MMM"
    return f.string(from: date)
}
