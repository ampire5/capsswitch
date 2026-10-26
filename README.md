# capsswitch

Caps Lock switches between your two most recently used keyboard layouts — instantly.

macOS can switch layouts with Caps Lock, but it waits for the key to be released to tell a tap from a hold
(~150 ms, and the first letters land in the old layout), it can briefly turn Caps Lock on, and its
“to and from ABC” mode treats ABC specially. capsswitch replaces that with a single press:

- **Instant.** The switch happens on key down, in 1–25 ms.
- **The two most recent layouts**, like ⌃Space with “Select the previous input source”. Pick a third layout from the
  menu bar and Caps Lock toggles between it and the one before. The pair is remembered across restarts.
- **No Caps Lock state.** Caps Lock never turns on.
- **No permissions.** No Accessibility or Input Monitoring: capsswitch does not see your keystrokes.
- **One file**, ~100 lines of Swift: [`main.swift`](main.swift).

## Install

```sh
brew install ampire5/tap/capsswitch
brew services start capsswitch
```

Turn off **System Settings → Keyboard → Text Input → Input Sources → Edit… → “Use Caps Lock to switch to and from ABC”**
if it is on: with capsswitch running it no longer receives Caps Lock anyway, but it is cleaner off.

Requires the Xcode Command Line Tools (`xcode-select --install`) to build.

### Uninstall

```sh
brew services stop capsswitch     # also gives Caps Lock back
brew uninstall capsswitch
```

## The language indicator

macOS shows a small bubble with the current language next to the text cursor when the layout changes.

```sh
capsswitch indicator off   # hide it
capsswitch indicator on    # show it (the macOS default)
capsswitch indicator       # print the current setting
```

This is the system-wide `TSMLanguageIndicatorEnabled` preference; apps pick it up when they are relaunched.

## How it works

- `hidutil` remaps Caps Lock to F18 at the driver level, so the system never sees Caps Lock: no tap/hold delay and no
  Caps Lock state. The mapping is set when capsswitch starts and cleared when it stops.
- F18 is registered as a Carbon hot key, which needs no permissions.
- On F18, `TISSelectInputSource` selects the previous of the two most recent layouts. Layout changes made any other
  way (menu bar, ⌃Space) update the pair too. The pair is kept in the `com.github.ampire5.capsswitch` defaults domain,
  by input source ID and name — macOS sometimes re-registers third-party layouts (e.g. made with Ukelele) under a
  different ID.

Caveat: `hidutil`'s user key mapping is a single list, so capsswitch replaces any other `hidutil` remapping you set,
and clears it on exit. Karabiner-Elements does not use it and is unaffected.

Debugging: run `capsswitch -v` in a terminal (after `brew services stop capsswitch`) to log every switch and its time.

## License

MIT
