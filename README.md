# Clothesline

A clipboard manager for macOS where everything you copy hangs on a line at the top of the screen.
The idea comes from [Tendedero](https://github.com/alejandrobujan/tendedero), which does this for screenshots; Clothesline is a separate implementation.

- **Show the line**: rest the pointer on the very top edge of the screen, or press **⇧⌘V** (changeable in Settings).
- **Lines**: Inbox gets every copy. Make your own lines (Work, Snippets, a project…) and drag a clip onto a line's tag to hang it there. Hung clips stay until you take them down.
- **Basket**: older Inbox clips drop into the basket at the right end. Click it, or start typing, to search everything you've copied.
- **Cards**: click to copy, double-click to paste into the app in front, drag onto any app or folder, right-click for more. Brush the pointer across them and they swing.
- **Drop in**: drag files, text or images from other apps onto the line to hang them.
- **Keyboard** (after ⇧⌘V): ←/→ choose, Return pastes, 1–9 paste by number, Space copies, ⌫ deletes, Tab switches line, type to search, Esc closes.

Text, links, colours (`#FF7A59`, `rgb(…)`), images and files each get their own card.

## Privacy

Everything stays in `~/Library/Application Support/Clothesline`. Nothing goes over the network. Clips that password managers mark as concealed or transient are never captured, and password-manager apps are skipped by default (Settings → Skipped apps). You can pause capturing from the menu-bar icon.

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
.build/debug/Clothesline --cmd keyboard   # show | keyboard | hide | search | next-line | demo-capture | quit
```

`CLOTHESLINE_DATA` uses a separate folder; `CLOTHESLINE_DEMO=1` fills an empty one with sample clips. With `CLOTHESLINE_DATA` set, `--cmd` only talks to that test copy.

## Licence

MIT. See [LICENSE](LICENSE).
