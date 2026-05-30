#!/usr/bin/env bash
# shim.sh — cut one ~/Documents subtree over to lattice, gradually & reversibly:
#   1) re-sync ~/Documents/<src> -> ~/lattice/<dest>   (catch any drift since the copy)
#   2) rename the original to <src>.pre-lattice          (safety net; same FS = instant)
#   3) replace ~/Documents/<src> with a RELATIVE symlink -> ~/lattice/<dest>
# Legacy absolute paths (~/Documents/<src>/…) keep resolving via the shim; lattice is now
# the real home. Reverse anytime:  lattice unshim <src>
set -euo pipefail
RSYNC=/opt/homebrew/bin/rsync
DOCS="$HOME/Documents"; LAT="$HOME/lattice"
src="${1:?usage: shim <documents-subdir> <lattice-subdir>}"
dest="${2:?usage: shim <documents-subdir> <lattice-subdir>}"
S="$DOCS/$src"; D="$LAT/$dest"
[ -e "$S" ] || { echo "no such source: $S" >&2; exit 1; }
[ -d "$D" ] || { echo "lattice dest missing: $D (run 'lattice copy --apply' first)" >&2; exit 1; }
if [ -L "$S" ]; then echo "already shimmed: $src -> $(readlink "$S")"; exit 0; fi

echo "1/3 re-syncing $src -> lattice/$dest (catch drift)…"
extra=()
# SHIM_EXCLUDE is a SPACE-SEPARATED string (env-exportable; arrays don't survive exec)
for e in ${SHIM_EXCLUDE:-}; do extra+=(--exclude="$e"); done
"$RSYNC" -a \
  --exclude=node_modules --exclude=.venv --exclude=__pycache__ --exclude='*.pyc' \
  --exclude=.next --exclude=dist --exclude=build --exclude=target --exclude=.DS_Store \
  --exclude=.cache --exclude='straight/build' --exclude='straight/repos' "${extra[@]}" \
  "$S/" "$D/" || { rc=$?; if [ "$rc" -le 24 ]; then echo "  (rsync warnings rc=$rc — non-fatal, continuing)"; else echo "rsync failed rc=$rc" >&2; exit $rc; fi; }
# prune broken symlinks the re-sync may have introduced (e.g. off-device reMarkable refs)
find "$D" -type l ! -exec test -e {} \; -delete 2>/dev/null || true
echo "2/3 renaming original -> $src.pre-lattice (safety net)…"
mv "$S" "$DOCS/$src.pre-lattice"
# relative to the symlink's OWN parent dir (handles nested srcs like new-site/content-org)
rel=$(python3 -c 'import os,sys;print(os.path.relpath(sys.argv[1],sys.argv[2]))' "$D" "$(dirname "$S")")
ln -s "$rel" "$S"
echo "3/3 shimmed: ~/Documents/$src -> $rel"
if [ -e "$S" ]; then
  echo "resolves ✓  (original preserved at ~/Documents/$src.pre-lattice — remove once trusted)"
else
  echo "BROKEN — reverting"; rm -f "$S"; mv "$DOCS/$src.pre-lattice" "$S"; exit 1
fi
