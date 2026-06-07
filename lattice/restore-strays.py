#!/usr/bin/env python3
"""restore-strays.py — restore genuine WORK that the migration dropped, from the
content-hash audit's loss list, WITHOUT clobbering newer lattice files.

Rules (considerate of work, hostile to junk/dupes):
  * Map each lost origin file to its lattice home (pre-lattice dirs -> their PARA homes;
    unknown Google-Drive orphans -> 0-inbox/recovered/<rel> for manual triage).
  * RESTORE only if the lattice destination PATH IS ABSENT (never overwrite a file that
    already exists in lattice — that version is newer/curated).
  * SKIP junk/regenerable/intentional: .claude/settings, /tmp/, /public/, content/ (ox-hugo
    output), build state (.ninja_log, *stats.json, search-index.json, roam-graph.json),
    .git internals, compiled binaries, the .delta.~1~/.~2~ duplicate snapshots, and
    static|public/doc/career (user is removing career from the public site).

  restore-strays.py            # dry-run: print RESTORE / SKIP / ALREADY-PRESENT
  restore-strays.py --apply
"""
import os, sys, shutil, re
from pathlib import Path

HOME=Path.home(); DOCS=HOME/"Documents"; ROOT=HOME/"lattice"
APPLY="--apply" in sys.argv
REPORT_LOSS=ROOT/"_meta"/"audit-report.txt"

# origin-prefix -> lattice destination base
PREFIX=[
    ("new-site.pre-lattice/content-org", ROOT/"notes"),
    ("new-site.pre-lattice",             ROOT/"code/sites/new-site"),
    ("code-private.pre-lattice",         ROOT/"code/private"),
    ("code-others.pre-lattice",          ROOT/"code/vendor"),
    ("code-archived.pre-lattice",        ROOT/"code/archived"),
    ("remarkable.pre-lattice",           ROOT/"2-areas/devices/remarkable"),
    ("rm2-stuff-ref.pre-lattice",        ROOT/"2-areas/devices/rm2-stuff-ref"),
    ("Finances.pre-lattice",             ROOT/"2-areas/finance"),
    ("Google Drive/.delta/90. - vince",  ROOT/"4-archive/legacy/delta-vince"),
    # teaching-resource sibling dirs the migration never mapped (only "1120. - high school" was)
    ("Google Drive/1. - goodnotes/11. - tuition/112. - resources/1121. - primary",      ROOT/"2-areas/teaching/resources/primary"),
    ("Google Drive/1. - goodnotes/11. - tuition/112. - resources/1122. - applications", ROOT/"2-areas/teaching/resources/applications"),
    ("Google Drive/1. - goodnotes/11. - tuition/112. - resources/1123. - alchemy",      ROOT/"2-areas/teaching/resources/alchemy"),
]
# skip entirely (junk / regenerable / intentional removals / duplicate snapshots)
SKIP_RE = re.compile(
    r"(^|/)\.claude/settings|(^|/)tmp/|(^|/)public/|(^|/)content/|"
    r"\.ninja_log$|hugo_stats\.json$|search-index\.json$|roam-graph\.json$|"
    r"(^|/)\.git(/|$)|/doc/career/|"
    r"Google Drive/\.delta\.~[12]~/|Google Drive/print/temp/|"
    r"(^|/)\.DS_Store$|(^|/)state\.json$|"
    r"\.(pyc|html|onetoc2|log|ninja|so|xml)$"   # regenerable junk / caches
)
# science already recovered separately
SCIENCE_RE = re.compile(r"11202\. - science")

def lattice_dest(rel):
    for pfx, base in PREFIX:
        if rel == pfx or rel.startswith(pfx+"/"):
            sub = rel[len(pfx):].lstrip("/")
            return base/sub if sub else base
    # unknown Google-Drive orphan -> quarantine for manual filing
    if rel.startswith("Google Drive/"):
        return ROOT/"0-inbox/recovered"/rel
    return None

def main():
    lines=[l for l in REPORT_LOSS.read_text().splitlines()]
    # take the full-list section, strip the (buggy) size column -> rel paths
    rels=[]; f=False
    for l in lines:
        if l.startswith("=== full list"): f=True; continue
        if f and l.strip():
            rels.append(re.sub(r"^\s+\S+\s+","",l))

    restore=[]; skip=[]; present=[]; nohome=[]
    for rel in rels:
        if SKIP_RE.search(rel) or SCIENCE_RE.search(rel):
            skip.append(rel); continue
        dst=lattice_dest(rel)
        if dst is None:
            nohome.append(rel); continue
        if dst.exists():
            present.append(rel)             # lattice already has it (newer/curated) -> leave
        else:
            src=DOCS/rel
            if src.is_file():
                restore.append((rel,dst))
            else:
                skip.append(rel)

    print(f"{'APPLY' if APPLY else 'DRY-RUN'}: restore={len(restore)} "
          f"already-present(left)={len(present)} skip-junk={len(skip)} no-home={len(nohome)}\n")
    print("=== RESTORE (genuinely absent work) — by destination area ===")
    from collections import Counter
    c=Counter(str(d).replace(str(ROOT)+"/","").split("/")[0]+"/"+
              (str(d).replace(str(ROOT)+"/","").split("/")[1] if len(str(d).replace(str(ROOT)+"/","").split("/"))>1 else "")
              for _,d in restore)
    for area,n in c.most_common():
        print(f"  {n:>4}  {area}")
    print("\n  sample (first 30):")
    for rel,dst in restore[:30]:
        print(f"    {rel}  ->  {str(dst).replace(str(HOME),'~')}")
    if nohome:
        print(f"\n=== NO-HOME (would go to 0-inbox/recovered): {len(nohome)} ===")
        for r in nohome[:20]: print(f"    {r}")

    if APPLY:
        n=0
        for rel,dst in restore:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(DOCS/rel, dst); n+=1
        print(f"\nrestored {n} files")

if __name__=="__main__":
    main()
