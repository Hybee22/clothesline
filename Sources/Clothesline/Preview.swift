import AppKit
import SwiftUI

/// The big version of a card, shown under the line when you hold the pointer on it (or press ⌥).
struct PreviewCard: View {
    let clip: Clip
    let store: Store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .padding(16)
        .frame(width: Layout.previewW, alignment: .leading)
        .background(Glass(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(scheme == .dark ? 0.16 : 0.7), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
    }

    private var header: some View {
        HStack(spacing: 7) {
            if let icon = AppIcons.icon(clip.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            }
            Text(AppIcons.name(clip.sourceBundleID) ?? kindName)
                .font(.system(size: 12, weight: .semibold))
            if detail != (AppIcons.name(clip.sourceBundleID) ?? kindName) {
                Text("·").foregroundStyle(.tertiary)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(clip.created.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var content: some View {
        switch clip.kind {
        case .image:
            if let b = clip.blob, let img = NSImage(contentsOf: store.blobURL(b)) ?? store.thumbnail(clip) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
        case .color:
            let ns = ColorParse.color(clip.text ?? "") ?? .gray
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: ns))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
                    .frame(width: 120, height: 120)
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    ForEach(ColorFormats.all(clip.text ?? ""), id: \.label) { f in
                        GridRow {
                            Text(f.label).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                            Text(f.value).font(.system(size: 11.5, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                }
            }
            Text("Right-click the card to copy it in another format.").font(.system(size: 10.5)).foregroundStyle(.secondary)
        case .files:
            let paths = clip.paths ?? []
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(paths.prefix(8).enumerated()), id: \.offset) { _, p in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable().frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((p as NSString).lastPathComponent).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                            Text(((p as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                if paths.count > 8 {
                    Text("and \(paths.count - 8) more").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        case .link:
            let u = URL(string: clip.text ?? "")
            Text(u?.host?.replacingOccurrences(of: "www.", with: "") ?? "")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(clip.text ?? "")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(8)
        case .text:
            if clip.isSecret {
                Label("Looks like a key, token or password, so it stays hidden here.", systemImage: "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hue: 0.02, saturation: 0.7, brightness: 0.85))
                Text(Secrets.mask(clip.text ?? ""))
                    .font(.system(size: 13, design: .monospaced))
                Text(Prefs.shared.secretMinutes > 0 && clip.lineID == nil
                     ? "It leaves the line \(Prefs.shared.secretMinutes) min after you copied it. Hang it on a line to keep it."
                     : "Click to copy it as usual.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            } else {
                let t = String((clip.text ?? "").prefix(4000))
                Text(clip.looksLikeCode ? t : t.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(clip.looksLikeCode ? .system(size: 11.5, design: .monospaced) : .system(size: 13))
                    .lineSpacing(2)
                    .lineLimit(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(clip.looksLikeCode ? 10 : 0)
                    .background {
                        if clip.looksLikeCode {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06))
                        }
                    }
                if clip.rich != nil {
                    Text("Formatted text · ⇧-click or ⇧↩ to paste it plain").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var kindName: String {
        switch clip.kind {
        case .text: return clip.isSecret ? "Secret" : clip.looksLikeCode ? "Code" : "Text"
        case .link: return "Link"
        case .files: return "Files"
        case .image: return "Image"
        case .color: return "Colour"
        }
    }

    private var detail: String {
        switch clip.kind {
        case .image:
            return clip.imageSize.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "Image"
        case .files:
            let n = clip.paths?.count ?? 0
            return n == 1 ? "1 file" : "\(n) items"
        case .color, .link: return kindName
        case .text:
            if clip.isSecret { return "Secret" }
            let t = clip.text ?? ""
            let lines = t.split(separator: "\n", omittingEmptySubsequences: false).count
            return "\(t.count) chars · \(lines) line\(lines == 1 ? "" : "s")"
        }
    }
}
