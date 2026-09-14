#!/usr/bin/env bash
##
## build.sh — headless web export into dist/.
##
## Needs Godot 4.7.2 and the matching web export templates; on the hub those
## come from `nathandunn/hub-orchestrator/scripts/godot-install.sh`. Nothing
## here needs a display.
##
## The engine template is a 38 MB .wasm, which is what Godot ships and not
## something a project can trim. So the three big artefacts are committed
## *only* in their gzipped form (10 MB all in) and nginx is configured with
## `gzip_static always; gunzip on;` — every real browser sends
## `Accept-Encoding: gzip` and gets the .gz straight off disk, and the handful
## that do not get it decompressed on the way out. `Content-Type` still comes
## from the un-suffixed path, so `.wasm` is still served as `application/wasm`.
##
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"

command -v "$GODOT" >/dev/null || { echo "godot not on PATH - run hub-orchestrator/scripts/godot-install.sh" >&2; exit 1; }
echo "engine: $($GODOT --headless --version)"

rm -rf dist build
mkdir -p dist

# .godot/ has to exist and be current or the export writes a pack with stale
# (or missing) script bytecode
$GODOT --headless --import >/dev/null 2>&1 || true
$GODOT --headless --export-release "Web" dist/index.html

##
## Boot the pack that was just written, headless, for 150 frames of the real
## main scene. There is no browser on the build host, so this is the closest
## thing to running the export: it proves the pack is complete and that every
## script in it compiled, which is the failure this catches - a script that
## parses in the project but was left out of, or mis-remapped in, the pack
## fails at `engine.startGame` in the browser and nowhere else.
##
echo "verifying the exported pack…"
$GODOT --headless --main-pack dist/index.pck --quit-after 150

# pre-compress the big three; keep only the .gz
for f in dist/index.wasm dist/index.js dist/index.pck; do
  [ -f "$f" ] || continue
  gzip -9 -f "$f"
done

printf '%-34s %10s\n' "artefact" "bytes"
for f in dist/*; do printf '%-34s %10s\n' "$(basename "$f")" "$(stat -c%s "$f")"; done
echo
echo "total: $(du -sh dist | cut -f1)"
