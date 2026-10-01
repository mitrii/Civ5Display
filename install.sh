#!/usr/bin/env bash
#
# install.sh - install the Civilization V display interposer on macOS.
#
# Usage:
#   ./install.sh                                             # auto-detect Steam install
#   CIV5_APP="/path/to/Civilization V.app" ./install.sh
#   CIV5_DYLIB="/path/to/libcivdisplay.dylib" ./install.sh   # use a prebuilt dylib
#
# It builds (or reuses) libcivdisplay.dylib, installs a small wrapper as the
# game executable, and re-signs the app ad-hoc.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/Library/Application Support/Civ5Display"
DYLIB="$INSTALL_DIR/libcivdisplay.dylib"

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

# --- build or reuse the dylib ---------------------------------------------
if [ -n "${CIV5_DYLIB:-}" ]; then
  echo "==> Using prebuilt dylib: $CIV5_DYLIB"
  cp "$CIV5_DYLIB" "$DYLIB"
else
  echo "==> Building libcivdisplay.dylib"
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
fi

# --- install the wrapper ---------------------------------------------------
echo "==> Installing wrapper"
if [ ! -f "$GAME_REAL" ]; then
  cp -p "$GAME_BIN" "$GAME_REAL"
fi
sed "s|__DYLIB_PATH__|$DYLIB|" "$SCRIPT_DIR/src/wrapper.sh" > "$GAME_BIN"
chmod +x "$GAME_BIN"

# --- re-sign ---------------------------------------------------------------
echo "==> Re-signing (ad-hoc)"
codesign --force --deep --sign - "$APP" >/dev/null

echo
echo "Done. Launch Civilization V from Steam."
echo "Choose the monitor with CIV5_DISPLAY inside:"
echo "  $GAME_BIN"
