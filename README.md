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
* Civilization V installed through Steam.
* Only for building from source: Xcode or the Xcode Command Line Tools (`clang`).

---

## Install

### Option 1 — automatic (recommended)

`install.sh` downloads the prebuilt `libcivdisplay.dylib` from the latest
release, installs the wrapper and re-signs the app:

```sh
curl -fsSL https://raw.githubusercontent.com/mitrii/Civ5Display/main/install.sh -o install.sh
bash install.sh
```

If your game is not in the default Steam location:

```sh
CIV5_APP="/Volumes/Games/SteamLibrary/steamapps/common/Sid Meier's Civilization V/Civilization V.app" bash install.sh
```

Other options:

```sh
bash install.sh --version v1.0.0            # a specific release
bash install.sh --dylib ./libcivdisplay.dylib   # a dylib you already have
bash install.sh --build                     # compile from source (needs src/)
```

Or clone the repo and run it from there (`./install.sh`).

### Option 2 — manual

Do it yourself with the prebuilt binary from the release.

**1. Download the dylib**

```sh
mkdir -p "$HOME/Library/Application Support/Civ5Display"
curl -fL -o "$HOME/Library/Application Support/Civ5Display/libcivdisplay.dylib" \
  https://github.com/mitrii/Civ5Display/releases/latest/download/libcivdisplay.dylib
```

**2. Back up the real game executable**

```sh
APP="/path/to/Sid Meier's Civilization V/Civilization V.app"
cp -p "$APP/Contents/MacOS/Civilization V" "$APP/Contents/MacOS/Civilization V.bin"
```

**3. Replace the executable with the wrapper**

```sh
cat > "$APP/Contents/MacOS/Civilization V" <<'EOF'
#!/bin/bash
# Inject the display interposer, preserving any Steam overlay libs already set.
: "${CIV5_DISPLAY:=external}"
export CIV5_DISPLAY
EXTRA="$HOME/Library/Application Support/Civ5Display/libcivdisplay.dylib"
if [ -n "$DYLD_INSERT_LIBRARIES" ]; then
  export DYLD_INSERT_LIBRARIES="$EXTRA:$DYLD_INSERT_LIBRARIES"
else
  export DYLD_INSERT_LIBRARIES="$EXTRA"
fi
exec "$(dirname "$0")/Civilization V.bin" "$@"
EOF
chmod +x "$APP/Contents/MacOS/Civilization V"
```

**4. Re-sign the app (ad-hoc)**

```sh
codesign --force --deep --sign - "$APP"
```

**5. Launch Civilization V from Steam.** It should open on the external monitor
and stay there when you drag it or open the laptop lid.

---

## Choosing a different monitor

By default the game uses the **first external (non-built-in) display**. If you
have more than one external monitor and want a specific one, you set it in a
small config file — you never need to touch the game files.

**Step 1 — find the monitor's name**

```sh
./install.sh --list
```

or, without the installer:

```sh
system_profiler SPDisplaysDataType | grep -E '^        [A-Za-z].*:$'
```

You'll get something like this (the first one is usually the built-in display):

```
  - Color LCD
  - IPS225
  - DELL U2720Q
```

**Step 2 — put that name in the config file**

The installer creates this file:

```
~/Library/Application Support/Civ5Display/config
```

Open it in a text editor:

```sh
open -e "$HOME/Library/Application Support/Civ5Display/config"
```

and change the `CIV5_DISPLAY` line. For example, to always use the
"DELL U2720Q":

```ini
CIV5_DISPLAY=DELL U2720Q
```

Save the file.

**Step 3 — relaunch Civilization V from Steam.** Done.

### Allowed values for `CIV5_DISPLAY`

| Value           | What it selects                                             |
|-----------------|-------------------------------------------------------------|
| `external`      | first non-built-in display *(default)*                      |
| `builtin`       | the built-in display                                        |
| `DELL U2720Q`   | first display whose name contains this text (case-insensitive) |
| `1`             | index from `CGGetActiveDisplayList` (0-based)               |

> The name is matched as a **substring**, so `IPS` also matches `IPS225`.
> Prefer the name; the numeric index is rarely needed.

### Alternative: set it inside the wrapper

If you'd rather not use the config file, edit the same line directly in the
wrapper `<App>/Contents/MacOS/Civilization V`:

```sh
: "${CIV5_DISPLAY:=DELL U2720Q}"
```

An environment variable exported before launching works too.

## Caveats

* **Steam → Verify integrity of game files** restores the original executable and
  removes the wrapper. Just re-run `install.sh`.
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

---

## Build from source

Only needed if you want to compile the dylib yourself instead of using the
prebuilt one.

**Quick way** (from a clone of this repo):

```sh
make          # -> libcivdisplay.dylib (universal x86_64 + arm64)
make test     # builds a helper and prints how the interposer sees each display
```

**Manual way:**

```sh
git clone https://github.com/mitrii/Civ5Display.git
cd Civ5Display
xcrun --sdk macosx clang -dynamiclib -O2 -o libcivdisplay.dylib src/civdisplay.c \
  -framework ApplicationServices -framework IOKit -framework CoreFoundation \
  -arch x86_64 -arch arm64
```

Then either install it with the installer:

```sh
CIV5_DYLIB=./libcivdisplay.dylib ./install.sh
```

or use it in the manual install steps above.

The [GitHub Actions workflow](.github/workflows/build.yml) builds the dylib on
every push and attaches it to a release when you push a `v*` tag.

## Repository layout

```
src/civdisplay.c   the interposer (compiled to libcivdisplay.dylib)
src/wrapper.sh     the wrapper installed as Contents/MacOS/Civilization V
src/disptest.c     diagnostic helper (make test)
install.sh         download/build + install + re-sign
Makefile           local build
.github/workflows/build.yml   CI
```

## License

[MIT](LICENSE)
