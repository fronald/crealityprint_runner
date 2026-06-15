#!/bin/bash
# Launcher wrapper to make AppImage works.
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
APPIMAGE="$(find "$SCRIPT_DIR" -maxdepth 1 -name 'CrealityPrint*.appimage' | sort -V | tail -1)"
EXTRACT_DIR="$SCRIPT_DIR/squashfs-root"
APPRUN="$EXTRACT_DIR/AppRun"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log()  { echo -e "${GREEN}::${NC} $*"; }
warn() { echo -e "${YELLOW}:: WARNING:${NC} $*"; }
err()  { echo -e "${RED}:: ERROR:${NC} $*" >&2; exit 1; }

# Extract...
if [ ! -f "$APPRUN" ]; then
    [ -f "$APPIMAGE" ] || err "AppImage not found: $APPIMAGE"
    log "Extracting AppImage (first run only)..."
    pushd "$SCRIPT_DIR" > /dev/null
    "$APPIMAGE" --appimage-extract
    popd > /dev/null
    log "Extracted to: $EXTRACT_DIR"
fi

# Patch AppRun like PR: https://github.com/CrealityOfficial/CrealityPrint/pull/539
if ! grep -q "EXT_LIB_PATH" "$APPRUN"; then
    log "Patching AppRun..."
    python3 - "$APPRUN" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

old = 'export LD_LIBRARY_PATH="$DIR/bin:$DIR/usr/lib"'
new = (
    '# Support for previously defined LD_LIBRARY_PATH.\n'
    'EXT_LIB_PATH=""\n'
    'if [ "x$LD_LIBRARY_PATH" != "x" ]; then\n'
    '    EXT_LIB_PATH=":$LD_LIBRARY_PATH"\n'
    'fi\n'
    'export LD_LIBRARY_PATH="$DIR/bin:$DIR/usr/lib$EXT_LIB_PATH"'
)

if old not in content:
    print("ERROR: target line not found in AppRun — patch skipped.", file=sys.stderr)
    sys.exit(0)

with open(path, 'w') as f:
    f.write(content.replace(old, new, 1))
print("Patch applied.")
PYEOF
fi

# Temp dir for linked shared objects
TMPROOT="$(mktemp -d /tmp/crealityprint-XXXXXXXX)"
TMPLIB="$TMPROOT/lib"
mkdir -p "$TMPLIB"

cleanup() { rm -rf "$TMPROOT"; }
trap cleanup EXIT

APP_LIBPATH="$EXTRACT_DIR/bin:$EXTRACT_DIR/usr/lib:$TMPLIB"

# Smart shared object (dependencies) search...
SEARCH_DIRS=(/usr/lib64 /usr/lib /lib64 /lib)

find_lib() {
    local wanted="$1"
    local base="$wanted"

    while true; do
        for dir in "${SEARCH_DIRS[@]}"; do
            [ -d "$dir" ] || continue
            local match
            # Highest version, please...
            match=$(find "$dir" -maxdepth 1 -name "${base}*" 2>/dev/null | sort -V | tail -1)
            [ -n "$match" ] && echo "$match" && return 0
        done
        # Ignore package version suffix
        [[ "$base" =~ \.[0-9]+$ ]] || break
        base="${base%.*}"
    done

    return 1
}

# Solve not found dependencies
log "Checking dependencies..."
missing=$(LD_LIBRARY_PATH="$APP_LIBPATH" ldd "$EXTRACT_DIR/bin/CrealityPrint" 2>/dev/null \
          | awk '/not found/ {print $1}')

if [ -z "$missing" ]; then
    log "All dependencies satisfied."
else
    for lib in $missing; do
        found=$(find_lib "$lib") || found=""
        if [ -n "$found" ]; then
            ln -sf "$found" "$TMPLIB/$lib"
            log "Linked: $lib -> $found"
        else
            warn "Not found on system: $lib"
        fi
    done
fi

# Exec patched
log "Starting CrealityPrint..."
export LD_LIBRARY_PATH="$TMPLIB"
"$APPRUN" "$@"
