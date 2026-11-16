# Clothesline

A clipboard manager for macOS where everything you copy hangs on a line at the top of the screen.
The idea comes from [Tendedero](https://github.com/alejandrobujan/tendedero), which does this for screenshots; Clothesline is a separate implementation.

- **Show the line**: rest the pointer on the very top edge of the screen, or press **⇧⌘V** (changeable in Settings).
- **Lines**: Inbox gets every copy. Make your own lines (Work, Snippets, a project…) and drag a clip onto a line's tag to hang it there. Hung clips stay until you take them down.
- **Basket**: older Inbox clips drop into the basket at the right end. Click it, or start typing, to search everything you've copied.
- **Cards**: click to copy, double-click to paste into the app in front, drag onto any app or folder, right-click for more. Brush the pointer across them and they swing.
- **Preview**: hold the pointer on a card (or press ⌥) and it tips forward into a big card with the full text, the whole image, every file or every colour format.
- **Undo**: taking a card down shows *Undo* for a few seconds (or press ⌘Z).
- **Pick several**: ⌘-click cards to number them, then *Copy Together* (⌘C) or *Paste Together* (Return) joins them in the order you picked.
- **Plain text**: formatted text keeps its bold, links and so on when pasted back. Hold ⇧ (⇧-click, ⇧-double-click, ⇧Return) to leave the formatting out.
- **Reorder**: drag a card along the line (Inbox too). The others part to show where it will land.
- **Colours**: right-click a colour card → *Copy as* HEX, RGB, HSL, SwiftUI or Flutter.
- **Drop in**: drag files, text or images from other apps onto the line to hang them.
- **Keyboard** (after ⇧⌘V): ←/→ choose, Return pastes, 1–9 paste by number, Space copies, ⌫ deletes, Tab switches line, type to search, ⌥ previews, Esc closes.

Text, links, colours (`#FF7A59`, `rgb(…)`), images and files each get their own card. A soft peg click plays when a clip is hung (Settings can turn it off).

## Privacy

Everything stays in `~/Library/Application Support/Clothesline`. Nothing goes over the network. Clips that password managers mark as concealed or transient are never captured, and password-manager apps are skipped by default (Settings → Skipped apps). You can pause capturing from the menu-bar icon.

Text that looks like a key, token or password (`sk-…`, `ghp_…`, `glpat-…`, AWS keys, JWTs, private keys, `postgres://user:password@…`, `API_KEY=…`) is masked on its card and removed from the Inbox after 2 minutes (Settings → Secrets), and cleared from the clipboard too if it's still there. Hang it on a line to keep it.

Auto-paste (double-click / Return) needs Accessibility permission. Without it, clips are copied and you press ⌘V yourself. The app is ad-hoc signed, so after a rebuild macOS may ask for Accessibility again.

## Build

```bash
./build.sh              # builds, installs to /Applications and starts it
./build.sh --no-install # only builds build/Clothesline.app
```

Swift package (SwiftUI + AppKit), macOS 14+. The icon is drawn by `scripts/make-icon.swift`.

## Testing without touching your real clips

```bash
export CLOTHESLINE_DATA=/tmp/cl-test CLOTHESLINE_DEMO=1
swift build && .build/debug/Clothesline &
.build/debug/Clothesline --cmd keyboard   # show | keyboard | hide | search | next-line | demo-capture | demo-preview | demo-pick | demo-delete | undo | quit
```

`CLOTHESLINE_DATA` uses a separate folder; `CLOTHESLINE_DEMO=1` fills an empty one with sample clips. With `CLOTHESLINE_DATA` set, `--cmd` only talks to that test copy.

## Licence

MIT. See [LICENSE](LICENSE).
