#!/bin/bash
# Installed as "Contents/MacOS/Civilization V". Adds the display interposer to
# DYLD_INSERT_LIBRARIES (preserving any Steam overlay libraries already set) and
# runs the real game binary.
#
# CIV5_DISPLAY selects which monitor the game treats as "main":
#   external   first non-built-in display            (default)
#   builtin    the built-in display
#   IPS225     any display whose name contains this
#   1          index from CGGetActiveDisplayList (0-based)
: "${CIV5_DISPLAY:=external}"
export CIV5_DISPLAY
EXTRA="__DYLIB_PATH__"
if [ -n "$DYLD_INSERT_LIBRARIES" ]; then
  export DYLD_INSERT_LIBRARIES="$EXTRA:$DYLD_INSERT_LIBRARIES"
else
  export DYLD_INSERT_LIBRARIES="$EXTRA"
fi
exec "$(dirname "$0")/Civilization V.bin" "$@"
