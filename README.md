![App icon](/images/Icon.png)

# Idåsen Desk Controller — Mac (Apple Silicon)

A Mac status-bar app for controlling your [IKEA IDÅSEN (Linak) sit/stand desk](https://www.ikea.com/au/en/p/idasen-desk-sit-stand-black-beige-s79280979/).

This is a maintained fork of [DWilliames/idasen-desk-controller-mac](https://github.com/DWilliames/idasen-desk-controller-mac), modernized for Apple Silicon and current macOS, with bug fixes pulled in from several community forks.

[**⬇ Download the latest release**](https://github.com/marcobazzani/idasen-desk-controller-mac/releases/latest)

---

![Animated example](/images/example.gif)

![Preferences example](/images/preferences_example.png)

## Features

- Easy access from the macOS status bar
- View current desk height
- Save sit/stand height presets
- Move up/down without holding the button
- Automatic stand reminders on an hourly schedule
- Calibration offset for desks that report the wrong absolute height
- Launch at login (toggleable in Preferences)
- AppleScript support (Alfred / Shortcuts / your own scripts)

![Status-bar example](/images/status_bar_example.png)

## Requirements

- **Apple Silicon Mac** (M1 or later)
- **macOS 13 Ventura** or newer

The binary is ARM64-only; Intel Macs are no longer supported. If you need an Intel build, use the [upstream 1.0.x releases](https://github.com/DWilliames/idasen-desk-controller-mac/releases).

## Install

1. Download `Desk-Controller-vX.Y.Z.zip` from the [latest release](https://github.com/marcobazzani/idasen-desk-controller-mac/releases/latest).
2. Unzip and move `Desk Controller.app` to `/Applications`.
3. Releases are ad-hoc signed (not notarized) because there's no Apple Developer ID behind this fork. Remove the macOS quarantine attribute once:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/Desk Controller.app"
   ```

4. Launch the app. Grant Bluetooth permission when prompted.

## What's new in this fork

| Change | Source |
|---|---|
| Swift 6 / Swift Concurrency refactor, modern Sendable closures, redesigned UI | merged from [MartinRybergLaude](https://github.com/MartinRybergLaude/idasen-desk-controller-mac) |
| Position-offset bug fix (offset applied to UI + sit/stand button state + target height) | ported from [ashumeet](https://github.com/ashumeet/idasen-controller-mac) |
| AppleScript: `move "120cm"` / `move "55in"` / `move "80"` shortcut | ported from [akucharczyk](https://github.com/akucharczyk/idasen-controller-mac) |
| ARM64-only build, macOS 13.0 deployment target | this fork |
| GitHub Actions CI + automated `.zip` releases on tag | this fork |
| Replace `NSGlassEffectView` (macOS 26-only) with `NSVisualEffectView` | this fork |

### Not yet merged (PRs welcome)

- Manual Bluetooth device selection in Preferences ([varunyellina](https://github.com/varunyellina/idasen-desk-controller-mac))
- Unlimited favourite presets ([anant1811](https://github.com/anant1811/idasen-desk-controller-mac))
- Notifications + better desk name detection ([akucharczyk](https://github.com/akucharczyk/idasen-controller-mac))

Both of the first two conflict structurally with the Swift Concurrency refactor and need a careful manual port onto the new `@MainActor` shape.

## AppleScript

Talk to the app from AppleScript (great for an [Alfred](https://www.alfredapp.com) workflow or Shortcuts):

```applescript
tell application "Desk Controller"
    move "to-sit"
end tell
```

Commands:

| Command | Effect |
|---|---|
| `move "to-sit"` | Move to the saved sitting position |
| `move "to-stand"` | Move to the saved standing position |
| `move "up"` / `move "down"` | Nudge up or down |
| `move "120cm"` / `move "55in"` | Move to an absolute height (unit suffix) |
| `move "80"` | Move to 80 cm or 80 in depending on your Preferences |
| `move to "120cm"` | Same as `move "120cm"` — original syntax still works |

## Troubleshooting

- **App "is damaged and can't be opened"** — that's the quarantine attribute on an ad-hoc signed app. Run the `xattr -dr com.apple.quarantine ...` command from the install section.
- **Desk isn't discovered** — only one device can talk to the desk over Bluetooth at a time. Quit Linak's mobile/desktop "Desk Control" app and reconnect.
- **Renamed your desk?** The discovery heuristic still looks for the word "Desk" in the Bluetooth name.
- **Hard reset the desk**:
  1. Lower the desk all the way down.
  2. Hold the physical down button past the bottom; the desk will jog down/up.
  3. Hold the Bluetooth button on the physical controller for a few seconds until the LED blinks.

## Building from source

```sh
git clone https://github.com/marcobazzani/idasen-desk-controller-mac.git
cd idasen-desk-controller-mac
open "Desk Controller.xcodeproj"
```

Requires Xcode 16+ on an Apple Silicon Mac.

CLI build matching CI:

```sh
xcodebuild -project "Desk Controller.xcodeproj" -scheme "Desk Controller" \
  -configuration Release -derivedDataPath build \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build
```

## Credits

- Original app by [David Williames](https://github.com/DWilliames). If this is useful, send him a coffee via [PayPal](https://paypal.me/dtw/5) and follow him at [@davidwilliames](https://twitter.com/davidwilliames).
- Auto-stand feature originally by Johan Eklund ([meck](https://github.com/meck)), upstream PR #2.
- Modernization and fork-merge work in this repository by [@marcobazzani](https://github.com/marcobazzani).

## License

See [LICENSE.md](LICENSE.md).
