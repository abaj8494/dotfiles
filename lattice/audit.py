#!/usr/bin/env python3
"""audit.py — find every ORIGINAL file (under ~/Documents) whose CONTENT is absent
from ~/lattice, i.e. genuinely deleted or never-copied by the migration.

Content-hash based (md5), so renames don't register as losses: a file that was
kebab-renamed or reclassified (past-papers) shares its hash with the lattice copy and
is therefore considered present. Only content that exists in an original but NOWHERE
in lattice is reported.

"Originals" = every real file under ~/Documents that is NOT a shim symlink into lattice.
That spans both the *.pre-lattice pre-shim originals and the not-yet-migrated real dirs
(uni, media, Google Drive, ...). Junk that the migration intentionally skips
(node_modules, build output, caches, .git internals, .DS_Store) is excluded on both sides.

Output: ~/lattice/_meta/audit-report.txt  (summary + full loss list, grouped)
"""
import os, sys, hashlib, time
from pathlib import Path
from collections import defaultdict

HOME = Path.home(); DOCS = HOME/"Documents"; ROOT = HOME/"lattice"
META = ROOT/"_meta"; REPORT = META/"audit-report.txt"
DEDUP = META/"dedup-proposed.log"

EXCLUDE_DIRS = {"node_modules",".venv","venv","__pycache__",".mypy_cache",".pytest_cache",
  ".next","dist","build","target",".Trash",".cache","eln-cache",".git",
  "anaconda3","miniconda3",".fseventsd",".Spotlight-V100",".DocumentRevisions-V100",
  "straight"}
EXCLUDE_FILES = {".DS_Store",".localized"}

def hash_file(p):
    h = hashlib.md5()
    try:
        with open(p,"rb") as f:
            for chunk in iter(lambda: f.read(1<<20), b""):
                h.update(chunk)
        return h.hexdigest()
    except OSError:
        return None

def walk_real(root):
    for dirpath, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for fn in files:
            if fn in EXCLUDE_FILES:
                continue
            p = Path(dirpath)/fn
            if p.is_symlink():
                continue
            yield p

def log(msg):
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)

def main():
    t0 = time.time()
    log("hashing lattice ...")
    lat = set(); n = 0
    for p in walk_real(ROOT):
        h = hash_file(p)
        if h:
            lat.add(h); n += 1
            if n % 20000 == 0:
                log(f"  lattice {n} files, {len(lat)} unique hashes")
    log(f"lattice done: {n} files, {len(lat)} unique hashes ({time.time()-t0:.0f}s)")

    log("scanning originals under ~/Documents (skipping shim symlinks) ...")
    origin_roots = [c for c in sorted(DOCS.iterdir())
                    if not c.is_symlink() and c.name != "lattice"]
    absent = []; scanned = 0
    for r in origin_roots:
        files = [r] if r.is_file() else list(walk_real(r))
        for p in files:
            scanned += 1
            h = hash_file(p)
            if h is None:
                continue
            if h not in lat:
                try: sz = p.stat().st_size
                except OSError: sz = 0
                absent.append((str(p.relative_to(DOCS)), sz))
        log(f"  scanned {r.name}: running total absent={len(absent)} / scanned={scanned}")

    # group for the report
    by_top = defaultdict(lambda: [0,0])      # top-level -> [count, bytes]
    by_ext = defaultdict(lambda: [0,0])
    for rel, sz in absent:
        top = rel.split(os.sep,1)[0]
        ext = (os.path.splitext(rel)[1].lower() or "<none>")
        by_top[top][0]+=1; by_top[top][1]+=sz
        by_ext[ext][0]+=1; by_ext[ext][1]+=sz

    def hsz(b):
        for u in "B KB MB GB TB":
            if b < 1024: return f"{b:.1f}{u.strip()}"
            b/=1024
        return f"{b:.1f}PB"

    META.mkdir(parents=True, exist_ok=True)
    with open(REPORT,"w") as f:
        f.write(f"LATTICE MIGRATION AUDIT — content absent from ~/lattice\n")
        f.write(f"generated {time.strftime('%Y-%m-%d %H:%M')}  ({time.time()-t0:.0f}s)\n")
        f.write(f"originals scanned: {scanned} files | lattice unique hashes: {len(lat)}\n")
        f.write(f"GENUINELY ABSENT (in a Documents original, content nowhere in lattice): "
                f"{len(absent)} files, {hsz(sum(s for _,s in absent))}\n\n")
        f.write("=== by top-level origin dir ===\n")
        for top,(c,b) in sorted(by_top.items(), key=lambda kv:-kv[1][1]):
            f.write(f"  {c:>6}  {hsz(b):>9}  {top}\n")
        f.write("\n=== by extension ===\n")
        for ext,(c,b) in sorted(by_ext.items(), key=lambda kv:-kv[1][1])[:30]:
            f.write(f"  {c:>6}  {hsz(b):>9}  {ext}\n")
        f.write("\n=== full list (path under ~/Documents, size) ===\n")
        for rel, sz in sorted(absent):
            f.write(f"  {hsz(sz):>9}  {rel}\n")
    log(f"REPORT WRITTEN -> {REPORT}  ({len(absent)} absent files)")

if __name__ == "__main__":
    main()
