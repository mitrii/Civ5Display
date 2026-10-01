#!/usr/bin/env bash
#
# install.sh - install the Civ5Display interposer for Civilization V on macOS.
#
# By default it DOWNLOADS the prebuilt libcivdisplay.dylib from GitHub Releases,
# installs a small wrapper as the game executable, and re-signs the app ad-hoc.
set -euo pipefail

REPO="mitrii/Civ5Display"
ASSET="libcivdisplay.dylib"
INSTALL_DIR="$HOME/Library/Application Support/Civ5Display"
DYLIB="$INSTALL_DIR/libcivdisplay.dylib"
CONFIG="$INSTALL_DIR/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"

BUILD=0
LOCAL_DYLIB="${CIV5_DYLIB:-}"
VERSION="${CIV5_VERSION:-latest}"

usage() {
  cat <<'USAGE'
install.sh - install the Civ5Display interposer for Civilization V on macOS.

Usage:
  ./install.sh                                   download latest prebuilt dylib
  CIV5_APP="/path/to/Civilization V.app" ./install.sh
  ./install.sh --dylib ./libcivdisplay.dylib     use a local dylib
  ./install.sh --version v1.0.0                  a specific release
  ./install.sh --build                           build from source (needs src/)
  ./install.sh --list                            list display names and exit

Environment:
  CIV5_APP       path to "Civilization V.app"
  CIV5_DYLIB     path to a local libcivdisplay.dylib
  CIV5_VERSION   release tag to download (default: latest)
USAGE
}

list_displays() {
  echo "Displays detected by macOS. Use the NAME (e.g. IPS225) in the config:"
  echo
  system_profiler SPDisplaysDataType 2>/dev/null \
    | grep -E '^        [A-Za-z].*:$' \
    | sed 's/^        /  - /; s/:$//' || true
  echo
  echo "Names are matched as a substring (case-insensitive)."
}

while [ $# -gt 0 ]; do
  case "$1" in
    --build)   BUILD=1; shift ;;
    --dylib)   LOCAL_DYLIB="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --list)    list_displays; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# --- locate the game -------------------------------------------------------
# Note: keep the apostrophe out of a ${VAR:-default} expansion (bash chokes on it).
DEFAULT_APP="$HOME/Library/Application Support/Steam/steamapps/common/Sid Meier's Civilization V/Civilization V.app"
APP="${CIV5_APP:-$DEFAULT_APP}"

if [ ! -d "$APP" ]; then
  cat >&2 <<MSG
Civilization V.app was not found at:
  $APP

Find it via Steam (right-click the game > Manage > Browse local files) and run:
  CIV5_APP="/path/to/Civilization V.app" $0
MSG
  exit 1
fi

MACOS_DIR="$APP/Contents/MacOS"
GAME_BIN="$MACOS_DIR/Civilization V"
GAME_REAL="$MACOS_DIR/Civilization V.bin"

echo "==> Game:    $APP"
echo "==> Install: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# --- obtain the dylib ------------------------------------------------------
if [ "$BUILD" = "1" ]; then
  echo "==> Building libcivdisplay.dylib from source"
  if [ ! -f "$SCRIPT_DIR/src/civdisplay.c" ]; then
    echo "src/civdisplay.c not found (run --build from a cloned repo)" >&2
    exit 1
  fi
  if command -v xcrun >/dev/null 2>&1; then
    CC=(xcrun --sdk macosx clang)
  elif command -v clang >/dev/null 2>&1; then
    CC=(clang)
  else
    echo "clang not found. Install the Xcode Command Line Tools: xcode-select --install" >&2
    exit 1
  fi
  "${CC[@]}" -dynamiclib -O2 -o "$DYLIB" "$SCRIPT_DIR/src/civdisplay.c" \
    -framework ApplicationServices -framework IOKit -framework CoreFoundation \
    -arch x86_64 -arch arm64
elif [ -n "$LOCAL_DYLIB" ]; then
  echo "==> Using local dylib: $LOCAL_DYLIB"
  cp "$LOCAL_DYLIB" "$DYLIB"
elif [ -f "$SCRIPT_DIR/$ASSET" ]; then
  echo "==> Using dylib next to this script: $SCRIPT_DIR/$ASSET"
  cp "$SCRIPT_DIR/$ASSET" "$DYLIB"
else
  if [ "$VERSION" = "latest" ]; then
    URL="https://github.com/$REPO/releases/latest/download/$ASSET"
  else
    URL="https://github.com/$REPO/releases/download/$VERSION/$ASSET"
  fi
  echo "==> Downloading $URL"
  curl -fL --retry 3 -o "$DYLIB" "$URL"
fi

if ! file "$DYLIB" | grep -q "Mach-O"; then
  echo "Not a Mach-O dynamic library:" >&2
  file "$DYLIB" >&2
  exit 1
fi

# --- monitor config --------------------------------------------------------
if [ ! -f "$CONFIG" ]; then
  echo "==> Writing default config: $CONFIG"
  cat > "$CONFIG" <<'CONF'
# Which monitor should Civilization V use?
# Edit the value, then relaunch the game.
#
#   external   first non-built-in display            (default)
#   builtin    the built-in display
#   IPS225     first display whose name contains this text
#   1          index from CGGetActiveDisplayList (0-based)
#
# List display names with:  install.sh --list
#
CIV5_DISPLAY=external
CONF
fi

# --- install the wrapper ---------------------------------------------------
echo "==> Installing wrapper"
if [ ! -f "$GAME_REAL" ]; then
  cp -p "$GAME_BIN" "$GAME_REAL"
fi
if [ -f "$SCRIPT_DIR/src/wrapper.sh" ]; then
  sed "s|__DYLIB_PATH__|$DYLIB|" "$SCRIPT_DIR/src/wrapper.sh" > "$GAME_BIN"
else
  cat > "$GAME_BIN" <<'WRAPPER'
#!/bin/bash
# Installed by Civ5Display as "Contents/MacOS/Civilization V".
# Target monitor is set in ~/Library/Application Support/Civ5Display/config
# (CIV5_DISPLAY: external | builtin | a display name | a 0-based index).
CONFIG="$HOME/Library/Application Support/Civ5Display/config"
[ -f "$CONFIG" ] && . "$CONFIG"
: "${CIV5_DISPLAY:=external}"
export CIV5_DISPLAY
EXTRA="__DYLIB_PATH__"
if [ -n "$DYLD_INSERT_LIBRARIES" ]; then
  export DYLD_INSERT_LIBRARIES="$EXTRA:$DYLD_INSERT_LIBRARIES"
else
  export DYLD_INSERT_LIBRARIES="$EXTRA"
fi
exec "$(dirname "$0")/Civilization V.bin" "$@"
WRAPPER
  sed -i '' "s|__DYLIB_PATH__|$DYLIB|" "$GAME_BIN"
fi
chmod +x "$GAME_BIN"

# --- re-sign ---------------------------------------------------------------
echo "==> Re-signing (ad-hoc)"
codesign --force --deep --sign - "$APP" >/dev/null

echo
echo "Done. Launch Civilization V from Steam."
echo
echo "To choose the monitor, edit:"
echo "  $CONFIG"
echo "Run '$0 --list' to see display names."
