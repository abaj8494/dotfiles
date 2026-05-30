#!/usr/bin/env bash
# add-paper.sh — file an exam paper into the backed-up canonical store and the overlay.
#
# The real file is MOVED into ~/Documents/past-papers/<subject>/<year-level>[/<stream>]/
# (which restic backs up), with a normalised kebab name; then the overlay is rebuilt so a
# relative symlink appears under ~/lattice/3-resources/past-papers/...  Idempotent.
#
# Usage:  lattice add /path/to/file.pdf
#         (prompts for subject / year-level / stream / year / school / type / solutions)
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
SRC="${1:-}"
[ -n "$SRC" ] && [ -f "$SRC" ] || { echo "usage: lattice add <file>" >&2; exit 2; }
STORE="$HOME/Documents/past-papers"

kebab() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/&/ and /g; s/[^a-z0-9]+/-/g; s/-+/-/g; s/^-|-$//g'; }
ask()   { local p="$1" d="${2:-}" a; read -r -p "$p${d:+ [$d]}: " a; printf '%s' "${a:-$d}"; }

ext="${SRC##*.}"; ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
echo "Filing: $(basename "$SRC")"
subject=$(kebab "$(ask 'subject (mathematics/english/science/...)' mathematics)")
ylevel=$(kebab "$(ask 'year level (year-7..year-12)' year-12)")
stream=$(kebab "$(ask 'stream (advanced/extension-1/extension-2/standard or blank)' '')")
year=$(ask 'year (YYYY)')
school=$(kebab "$(ask 'school (e.g. epping-boys, north-sydney-girls)' '')")
type=$(kebab "$(ask 'exam type (trial/half-yearly/yearly/hsc/assessment-1/...)' trial)")
term=$(ask 'term 1-4 (blank = infer: half-yearly=2, yearly=4, trial=3, hsc=4)' '')
sol=$(ask 'is this a solutions copy? (y/N)' n)

# infer term from type when not given
if [ -z "$term" ]; then case "$type" in
  half-yearly|hy) term=2;; yearly) term=4;; trial) term=3;; hsc|prelim) term=4;;
  assessment-1) term=1;; assessment-2) term=2;; assessment-3) term=3;; assessment-4) term=4;;
esac; fi
case "$term" in
  1) tf="t1";; 2) tf="t2 (half-yearly, hy)";; 3) tf="t3 (trial)";; 4) tf="t4 (yearly, hsc)";;
  *) tf="unknown-term";;
esac

name="$year"; [ -n "$school" ] && name="$name-$school"; [ -n "$type" ] && name="$name-$type"
case "$sol" in y|Y|yes) name="$name--solutions";; esac
dest_dir="$STORE/$subject/$ylevel"; [ -n "$stream" ] && dest_dir="$dest_dir/$stream"
dest_dir="$dest_dir/$tf"
mkdir -p "$dest_dir"
dest="$dest_dir/$name.$ext"
n=2; while [ -e "$dest" ]; do dest="$dest_dir/$name-$n.$ext"; n=$((n+1)); done

mv -i "$SRC" "$dest"
echo "stored -> ${dest#$HOME/}"
python3 "$HERE/build.py" --apply >/dev/null
link="$HOME/lattice/3-resources/past-papers/$subject/$ylevel${stream:+/$stream}/$tf/$(basename "$dest")"
echo "linked -> ${link#$HOME/}"
echo "indexed. ($(grep -c '^| ' "$HOME/lattice/_meta/past-papers-index.org" 2>/dev/null || echo '?') rows)"
