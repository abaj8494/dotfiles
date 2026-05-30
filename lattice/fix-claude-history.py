#!/usr/bin/env python3
"""fix-claude-history.py — after the Documents->lattice shim migration, Claude Code
keys session history by the RESOLVED cwd, so sessions recorded under old Documents
paths are orphaned from `/resume` (which now reads the lattice slug). This relocates
each orphaned session dir to its lattice slug.

Slug = every non-alphanumeric char of the absolute cwd -> '-'.
Only remaps dirs whose recorded cwd resolves (via the shims) to a DIFFERENT real path.
The current goodnotes session (not shimmed) is left untouched.

  fix-claude-history.py           # dry-run
  fix-claude-history.py --apply   # move sessions (tar backup first)

Note: ~/.claude.json prompt-history rekey is reported but NOT modified here — that file
is rewritten by the live session on exit, so editing it now would be clobbered. Run the
reported rekey separately when no Claude session is active (or accept it self-heals).
"""
import json, os, sys, shutil, glob, re, subprocess
HOME = os.path.expanduser("~")
PROJ = os.path.join(HOME, ".claude", "projects")
APPLY = "--apply" in sys.argv

def slug(p): return re.sub(r'[^A-Za-z0-9]', '-', p)

def session_cwd(d):
    # recurse: top-level *.jsonl may already be moved; subagents/*.jsonl carry cwd too
    for f in glob.glob(os.path.join(d, "**", "*.jsonl"), recursive=True):
        try:
            with open(f) as fh:
                for line in fh:
                    o = json.loads(line)
                    if isinstance(o, dict) and o.get("cwd"):
                        return o["cwd"]
        except Exception:
            pass
    return None

moves = []   # (src, dst, n, cwd, realpath)
for d in sorted(glob.glob(os.path.join(PROJ, "*"))):
    if not os.path.isdir(d):
        continue
    cwd = session_cwd(d)
    if not cwd:
        continue
    rp = os.path.realpath(cwd)
    if rp == cwd or not os.path.exists(rp):
        continue                       # not shimmed, or path no longer exists -> leave
    dst = os.path.join(PROJ, slug(rp))
    if os.path.abspath(d) == os.path.abspath(dst):
        continue
    n = len(glob.glob(os.path.join(d, "**", "*.jsonl"), recursive=True))
    moves.append((d, dst, n, cwd, rp))

print(f"{'APPLY' if APPLY else 'DRY-RUN'}: {len(moves)} session dirs to remap, "
      f"{sum(m[2] for m in moves)} sessions")
for d, dst, n, cwd, rp in sorted(moves, key=lambda m: -m[2])[:20]:
    print(f"  {n:>3}  {os.path.basename(d).replace('aayushbajaj','aj')}")
    print(f"       -> {os.path.basename(dst).replace('aayushbajaj','aj')}")

if APPLY:
    bk = os.path.join(HOME, ".claude", "projects.pre-lattice.tar.gz")
    if not os.path.exists(bk):                 # keep the ORIGINAL backup, don't overwrite
        subprocess.run(["tar", "czf", bk, "-C", os.path.dirname(PROJ), "projects"], check=False)
        print(f"backup -> {bk}")
    else:
        print(f"backup already exists -> {bk} (kept)")

    def move_into(src, dst):
        """Move every entry of src into dst, merging directories recursively."""
        cnt = 0
        for name in os.listdir(src):
            s = os.path.join(src, name); t = os.path.join(dst, name)
            if os.path.exists(t):
                if os.path.isdir(s) and os.path.isdir(t):
                    cnt += move_into(s, t)
                    if not os.listdir(s):
                        os.rmdir(s)
                # else: target file already there (same UUID) — skip
            else:
                shutil.move(s, t); cnt += 1
        return cnt

    moved = 0
    for d, dst, n, cwd, rp in moves:
        os.makedirs(dst, exist_ok=True)
        moved += move_into(d, dst)
        if os.path.isdir(d) and not os.listdir(d):
            os.rmdir(d)
    print(f"moved {moved} entries (sessions + subagent dirs) into their lattice slugs")
