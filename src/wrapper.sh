#!/bin/bash
# Installed by Civ5Display as "Contents/MacOS/Civilization V".
#
# Injects the display interposer and runs the real game binary. The target
# monitor is chosen by CIV5_DISPLAY, which you set in
#
#   ~/Library/Application Support/Civ5Display/config
#
# Values: external (default) | builtin | a display name like "IPS225" | a
# 0-based index from CGGetActiveDisplayList.

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
