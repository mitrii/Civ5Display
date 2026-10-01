# Civ5Display

[![build](https://github.com/mitrii/Civ5Display/actions/workflows/build.yml/badge.svg)](https://github.com/mitrii/Civ5Display/actions/workflows/build.yml)

**Play Sid Meier's Civilization V on any monitor on macOS — without moving the
menu bar.**

The Aspyr macOS build of Civ V always opens on, and snaps back to, the *main*
display (the one with the menu bar). This is a tiny, reversible fix that makes
the game believe a display of your choice is the main one. Your menu bar stays
exactly where it is.

Tested with Civilization V build 180925 (Steam App ID 8930) on macOS 27
(Apple Silicon, Rosetta) with a built-in Retina display and an external 1080p
monitor. Should work on Intel Macs too.

---

## The problem

Civ V on macOS is hard-wired to the main display:

* **Windowed mode doesn't help** — dragging the window to another screen makes
  it jump straight back.
* **The launcher's monitor picker is disabled** — Aspyr ships the app with
  `disableMultiMonitorSetup`, and the launcher never forwards a display choice
  to the game anyway.
* **Closing the MacBook lid** works only until the built-in display comes back,
  then the window jumps home again.
* **Moving the menu bar** (System Settings → Displays → Arrange) works, but it
  rearranges your whole desktop — and most people don't want that.

## How it works

The game asks CoreGraphics which display is "main":

```
CGDisplayIsMain(displayID)   CGMainDisplayID()
```

We ship a small dylib that **interposes** those two functions (via a
`__DATA,__interpose` section) and answers for the display you select. The change
is scoped to the Civ V process (matched by executable path), so nothing else on
your system is affected.

Injecting it is the only fiddly part. `DYLD_INSERT_LIBRARIES` would be enough,
**except** Steam launches the game through Aspyr's launcher, which overwrites
that variable with its own Steam-overlay libraries. So instead of relying on the
environment, we replace the game executable with a one-line wrapper that
*prepends* the dylib to whatever `DYLD_INSERT_LIBRARIES` already contains, then
runs the real binary:

```
Steam ─▶ Civilization V.app ─▶ Aspyr launcher ─▶ wrapper ─▶ Civilization V.bin
                                                    │
                                     DYLD_INSERT_LIBRARIES=libcivdisplay.dylib:…
```

The Steam overlay keeps working, and System Integrity Protection is not an
issue (the game is not a protected binary).

## Requirements

* macOS (Intel or Apple Silicon).
* Xcode or the Xcode Command Line Tools (`clang`).
* Civilization V installed through Steam.

## Install

1. Clone the repo:

   ```sh
   git clone https://github.com/mitrii/Civ5Display.git
   cd Civ5Display
   ```

2. Run the installer. It auto-detects the usual Steam location:

   ```sh
   ./install.sh
   ```

   If your library is elsewhere (external drive, custom path), point it at the
   bundle:

   ```sh
   CIV5_APP="/Volumes/Games/SteamLibrary/steamapps/common/Sid Meier's Civilization V/Civilization V.app" ./install.sh
   ```

3. Launch Civilization V from Steam. It should open on the external monitor and
   stay there when you drag it or open the laptop lid.

Prefer a prebuilt binary? Download `libcivdisplay.dylib` from the
[latest release](https://github.com/mitrii/Civ5Display/releases/latest) and pass
it to the installer:

```sh
CIV5_DYLIB=./libcivdisplay.dylib ./install.sh
```

## Choosing the monitor

The wrapper reads the environment variable `CIV5_DISPLAY`. Edit the line in
`Contents/MacOS/Civilization V` (or export the variable before launching):

| Value      | Meaning                                              |
|------------|------------------------------------------------------|
| `external` | first non-built-in display *(default)*               |
| `builtin`  | the built-in display                                 |
| `IPS225`   | first display whose product name contains this text  |
| `1`        | index into `CGGetActiveDisplayList` (0-based)        |

For example, to always use a monitor named "DELL U2720Q":

```sh
: "${CIV5_DISPLAY:=DELL U2720Q}"
```

List your displays and their names with:

```sh
system_profiler SPDisplaysDataType | grep -E "Display Type|Resolution|^        [A-Za-z]"
```

## Caveats

* **Steam → Verify integrity of game files** restores the original executable and
  removes the wrapper. Just run `./install.sh` again.
* The installer re-signs the app **ad-hoc**, replacing Aspyr's Developer ID
  signature. This is required to run a modified bundle and is fine locally.
* The interposer answers for a chosen display; the menu bar is untouched.
  `CGMainDisplayID()` is remapped too, which is what stops the game from
  snapping back on focus/display changes.

## Uninstall

```sh
APP="/path/to/Sid Meier's Civilization V/Civilization V.app"
rm -f "$APP/Contents/MacOS/Civilization V"
mv "$APP/Contents/MacOS/Civilization V.bin" "$APP/Contents/MacOS/Civilization V"
codesign --force --deep --sign - "$APP"
```

(or just use Steam → Verify integrity of game files).

## Build

```sh
make          # -> libcivdisplay.dylib (universal x86_64 + arm64)
make test     # builds a helper and prints how the interposer sees each display
```

The [GitHub Actions workflow](.github/workflows/build.yml) builds the dylib on
every push and attaches it to a release when you push a `v*` tag.

## Repository layout

```
src/civdisplay.c   the interposer (compiled to libcivdisplay.dylib)
src/wrapper.sh     the wrapper installed as Contents/MacOS/Civilization V
src/disptest.c     diagnostic helper (make test)
install.sh         build + install + re-sign
Makefile           local build
.github/workflows/build.yml   CI
```

## License

[MIT](LICENSE)
