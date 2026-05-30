#!/usr/bin/env python3
"""dedup.py — collapse byte-identical duplicate files inside the lattice REFERENCE
zones (never code/ or notes/ — those are repos). Keep one canonical per content
hash, remove the rest, log every removal. Dry-run by default; --apply to delete.

Canonical preference (kept copy): not in 4-archive, not a gdrive-* dupe, not in
0-inbox, then shallower path, then shorter path.
"""
import os, sys, hashlib
from collections import defaultdict
from pathlib import Path

ROOT = Path.home() / "lattice"
META = ROOT / "_meta"
ZONES = ["0-inbox", "1-projects", "2-areas", "3-resources", "4-archive"]  # NOT code/ notes/
APPLY = "--apply" in sys.argv[1:]

# Dedup only true human DOCUMENTS — never code, assets, UI icons, or caches.
# (images/audio/video are excluded: overwhelmingly app/UI/build assets, not "files".)
DOC_EXT = {"pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx",
           "epub", "mobi", "azw3", "djvu", "odt", "key", "pages", "numbers"}
# Never dedup inside these trees (repos / snapshots / code dumps must stay intact).
EXCLUDE_SEG = {".git", "node_modules", "devices", "gdrive-code-configs",
               "goodnotes-uni", ".Spotlight-V100", ".fseventsd",
               "beancount"}   # ledger references its filed docs by path — leave intact
# app/document bundles are atomic — never dedup files inside them
BUNDLE_SUFFIX = (".alfredpreferences", ".workflow", ".app", ".bundle",
                 ".photoslibrary", ".sparsebundle", ".key", ".pages", ".numbers")

def eligible(p: Path):
    if p.suffix.lower().lstrip(".") not in DOC_EXT:
        return False
    if EXCLUDE_SEG & set(p.parts):
        return False
    return not any(part.lower().endswith(BUNDLE_SUFFIX) for part in p.parts)

def sha(p, buf=1 << 20):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(buf), b""):
            h.update(chunk)
    return h.hexdigest()

def score(p: Path):
    s = str(p.relative_to(ROOT))
    pen = 0
    if s.startswith("0-inbox"):   pen += 200   # worst home for a canonical (unsorted)
    if s.startswith("4-archive"): pen += 100
    if "gdrive" in s:             pen += 50
    return (pen, len(p.parts), len(s))   # lower = better (kept)

# 1) group by size (cheap); only same-size files can be identical
bysize = defaultdict(list)
for z in ZONES:
    base = ROOT / z
    if not base.is_dir():
        continue
    for p in base.rglob("*"):
        if p.is_symlink() or not p.is_file():
            continue
        if not eligible(p):
            continue
        try:
            sz = p.stat().st_size
        except OSError:
            continue
        if sz > 0:
            bysize[sz].append(p)

# 2) hash only within size-collisions
groups = defaultdict(list)
for sz, ps in bysize.items():
    if len(ps) < 2:
        continue
    for p in ps:
        try:
            groups[(sz, sha(p))].append(p)
        except OSError:
            pass

removed = saved = 0
log = []
for (sz, h), ps in groups.items():
    if len(ps) < 2:
        continue
    ps.sort(key=score)
    canon = ps[0]
    for dup in ps[1:]:
        log.append(f"{dup.relative_to(ROOT)}\t==\t{canon.relative_to(ROOT)}")
        removed += 1; saved += sz
        if APPLY:
            dup.unlink()

META.mkdir(parents=True, exist_ok=True)
out = META / ("dedup.log" if APPLY else "dedup-proposed.log")
out.write_text("\n".join(log) + "\n")

# prune now-empty dirs (apply only)
if APPLY:
    for z in ZONES:
        for d in sorted((ROOT / z).rglob("*"), key=lambda x: -len(x.parts)):
            if d.is_dir() and not d.is_symlink():
                try:
                    d.rmdir()          # only succeeds if truly empty
                except OSError:
                    pass               # not empty (has .DS_Store / other) — leave it

print(f"{'APPLIED' if APPLY else 'DRY-RUN'}: {removed} duplicate files, "
      f"{saved/1e9:.2f} GB reclaimable, across {sum(1 for g in groups.values() if len(g)>1)} dup-groups")
print(f"log -> _meta/{out.name}")
if not APPLY and log:
    print("\nsample (duplicate  ==  kept canonical):")
    for l in log[:15]:
        print("  " + l.replace("\t", "  "))
