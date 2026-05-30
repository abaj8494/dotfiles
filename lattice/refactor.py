#!/usr/bin/env python3
"""refactor.py — strip opaque decimal prefixes from lattice dirs -> descriptive
kebab-case (e.g. '11200. - mathematics' -> 'mathematics', '111.22 - Vivan Sharma'
-> 'vivan-sharma'). Bottom-up so parent renames don't invalidate child paths.
Skips code/, notes/, beancount, .git, app bundles, device snapshots.

  refactor.py            # dry-run (default)
  refactor.py --apply    # perform the renames
"""
import os, re, sys
from pathlib import Path

ROOT = Path.home() / "lattice"
ZONES = ["2-areas", "3-resources", "4-archive"]   # never code/ or notes/
APPLY = "--apply" in sys.argv
SKIP_SEG = {".git", "node_modules", ".Spotlight-V100", ".fseventsd", "beancount", "backups",
            "firmware", "gdrive-code-configs"}  # code/LaTeX archive — meaningful internal ordering
SKIP_SUFFIX = (".alfredpreferences", ".workflow", ".app", ".bundle", ".photoslibrary", ".plugin")
# the Johnny-Decimal org scheme ONLY: leading digits/dots, then ' - ' (spaces
# REQUIRED around the dash), then the name. This deliberately does NOT match
# content-internal numbering like '6.07-sorting', '2021-04-26-x', or '11-12'.
DECIMAL = re.compile(r'^[0-9][0-9.]*\s+-\s+(.+)$')

def kebab(s):
    s = s.strip().lower().replace("&", " and ")
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return re.sub(r"-+", "-", s).strip("-")

def protected(p: Path):
    rel = p.relative_to(ROOT).parts
    if SKIP_SEG & set(rel):
        return True
    return any(part.lower().endswith(SKIP_SUFFIX) for part in rel)

dirs = []
for z in ZONES:
    base = ROOT / z
    if not base.is_dir():
        continue
    for p in base.rglob("*"):
        if p.is_dir() and not p.is_symlink() and not protected(p):
            dirs.append(p)
dirs.sort(key=lambda p: len(p.parts), reverse=True)   # deepest first

renames, collisions = [], []
seen_targets = set()
for p in dirs:
    m = DECIMAL.match(p.name)
    if not m:
        continue
    new = kebab(m.group(1))
    if not new or new == p.name:
        continue
    dst = p.parent / new
    if dst.exists() or dst in seen_targets:   # pre-existing OR another same-batch rename
        collisions.append((p, dst))
        continue
    seen_targets.add(dst)
    renames.append((p, dst))

for src, dst in renames:
    if APPLY:
        src.rename(dst)

print(f"{'APPLIED' if APPLY else 'DRY-RUN'}: {len(renames)} dir renames, {len(collisions)} collisions")
print("\nsample (current -> new basename):")
for src, dst in renames[:40]:
    print(f"  {src.relative_to(ROOT)}  ->  {dst.name}")
if collisions:
    print(f"\nCOLLISIONS (skipped — need manual/merge):")
    for s, d in collisions[:30]:
        print(f"  {s.relative_to(ROOT)}  ->  {d.name} (already exists)")
