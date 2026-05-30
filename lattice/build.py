#!/usr/bin/env python3
"""
build.py — generate the ~/lattice overlay.

~/lattice is a NON-DESTRUCTIVE view of ~/Documents built entirely from RELATIVE
symlinks. Nothing under ~/Documents is ever modified, moved or renamed. Clean,
kebab-case names live on the symlinks; the messy originals stay put as targets.
`build.py --clean` removes ~/lattice and loses nothing.

Two kinds of links are produced:
  * folder-level links  — whole sub-trees mapped into the PARA structure
                          (see TOPLEVEL); fast, one symlink per source dir.
  * past-paper links    — every exam PDF is classified from its filename and
                          linked with a normalised name into
                          3-resources/past-papers/<subject>/<year-level>[/<stream>]/.

Usage:
  build.py            # dry-run (default): print the plan, touch nothing
  build.py --apply    # create dirs + relative symlinks (idempotent)
  build.py --clean    # rm -rf ~/lattice
  build.py --papers-only / --skel-only   # restrict scope
"""
from __future__ import annotations
import os, re, sys, shutil, subprocess
from pathlib import Path

HOME = Path.home()
DOCS = HOME / "Documents"
GDRIVE = DOCS / "Google Drive"          # holds the 0.–9. top categories
GD   = GDRIVE / "1. - goodnotes"        # holds the 10.–16. sub-categories
ROOT = HOME / "lattice"
META = ROOT / "_meta"

DRY = True            # default; flipped by --apply
SCOPE = "all"         # all | papers | skel
MODE = "symlink"      # symlink | copy   (copy = materialize real files via rsync)
RSYNC = "/opt/homebrew/bin/rsync"   # real rsync 3.x (macOS /usr/bin is openrsync)

# junk never worth copying (regenerable / caches); keeps the real copy lean
COPY_EXCLUDES = ["node_modules", ".venv", "venv", "__pycache__", "*.pyc",
                 ".mypy_cache", ".pytest_cache", ".next", "dist", "build", "target",
                 ".DS_Store", ".Trash", "Library/Caches", ".cache", "eln-cache",
                 "straight/build", "straight/repos", ".ollama/models",
                 "anaconda3", "miniconda3", ".fseventsd", ".Spotlight-V100"]
# per-destination extra excludes to prevent double-copying overlapping sources
ENTRY_EXCLUDES = {
    # content-org is re-homed at notes/; site build output is regenerable
    "code/sites/new-site": ["/content-org", "/public", "/resources/_gen"],
    # past papers + the sort pile are re-homed (clean-named) under 3-resources/past-papers
    "2-areas/teaching/resources": ["*past papers*", "sort"],
}

# ---------------------------------------------------------------------------
# folder-level mapping:  (source path, destination relative to ~/lattice)
# Conservative defaults — everything gets a home; symlinks are trivial to move.
# ---------------------------------------------------------------------------
TUI = GD / "11. - tuition"
RES = TUI / "112. - resources" / "1120. - high school"

TOPLEVEL = [
    # --- peers (git / org-roam managed; not "filed") ---
    (DOCS / "new-site" / "content-org",            "notes"),
    (DOCS / "code-private",                         "code/private"),
    (DOCS / "code-others",                          "code/vendor"),
    (DOCS / "code-share",                           "code/shared"),
    (DOCS / "code-archived",                        "code/archived"),
    (DOCS / "new-site",                             "code/sites/new-site"),
    (DOCS / "io-site",                              "code/sites/io-site"),
    (DOCS / "luke-site",                            "code/sites/luke-site"),
    (DOCS / "frizzande",                            "code/sites/frizzande"),
    (DOCS / "abaj8494",                             "code/sites/abaj8494"),
    (DOCS / "abaj8494.github.io",                   "code/sites/abaj8494-github-io"),
    (DOCS / "FAT-FORT",                             "code/fat-fort"),
    (DOCS / "EnCroissant",                          "code/encroissant"),
    (DOCS / "scripts",                              "code/scripts"),
    (DOCS / "usr-local-bin",                        "code/usr-local-bin"),

    # --- 1-projects (active) ---
    (TUI / "111. - students" / "111.22 - Vivan Sharma", "1-projects/vivan-sharma"),

    # --- 2-areas (ongoing) ---
    (DOCS / "Finances",                             "2-areas/finance"),
    (DOCS / "trades",                               "2-areas/finance/trades"),
    (GDRIVE / "0. - bio",                           "2-areas/admin/bio"),
    (GDRIVE / "4. - custom",                        "2-areas/admin/tool-configs"),
    (GDRIVE / "2. - code",                          "2-areas/admin/gdrive-code-configs"),
    (GDRIVE / "3. - career",                        "2-areas/career"),
    (TUI / "110. - seminars",                       "2-areas/teaching/seminars"),
    (GD / "16. - seminars",                         "2-areas/teaching/seminars-elevate"),
    (RES,                                           "2-areas/teaching/resources"),
    (GD / "13. - music",                            "2-areas/music"),
    (GD / "14. - volunteer",                        "2-areas/volunteer"),
    (DOCS / "remarkable",                           "2-areas/devices/remarkable"),
    (DOCS / "remarkable-ferrari",                   "2-areas/devices/remarkable-ferrari"),
    (DOCS / "remarkable-porsche",                   "2-areas/devices/remarkable-porsche"),
    (DOCS / "remarkable-paper-pro",                 "2-areas/devices/remarkable-paper-pro"),
    (DOCS / "rm2-stuff-ref",                        "2-areas/devices/rm2-stuff-ref"),
    (DOCS / "kiyomi",                               "2-areas/people/kiyomi"),

    # --- 3-resources (reference) ---
    (GD / "12. - pkm",                              "3-resources/pkm"),
    (GD / "15. - art",                              "3-resources/art"),
    (GDRIVE / "8. - words",                         "3-resources/words"),
    (GDRIVE / "7. - media",                         "3-resources/media-gdrive"),
    (DOCS / "media",                                "3-resources/media"),
    (DOCS / "doc",                                  "3-resources/doc"),

    # --- 4-archive (dormant / superseded) ---
    (GD / "10. - uni",                              "4-archive/goodnotes-uni"),
    (DOCS / "uni",                                  "4-archive/uni"),
    (TUI / "111. - students",                       "4-archive/teaching/students"),
    (GDRIVE / "5. - finances",                      "4-archive/gdrive-finances"),
    (GDRIVE / "6. - backups",                       "4-archive/gdrive-backups"),
    (GDRIVE / "9. - archives",                      "4-archive/gdrive-archives"),
    (DOCS / "remarkable-paper-pro-move",            "4-archive/devices/remarkable-paper-pro-move"),

    # --- 0-inbox (unsorted / scratch — triage targets) ---
    (DOCS / "inbox",                                "0-inbox/old-inbox"),
    (DOCS / "temp",                                 "0-inbox/temp"),
    (DOCS / "deez",                                 "0-inbox/deez"),
]

# ---------------------------------------------------------------------------
# past-paper sources:  (source dir, subject, year-level, stream-or-None)
# ---------------------------------------------------------------------------
M = RES / "11200. - mathematics"
Y12 = M / "112006. - year 12"
Y11 = M / "112005. - year 11"
E = RES / "11201. - english"

PAPER_SOURCES = [
    (M / "112001. - year 7" / "1120010. - past papers",   "mathematics", "year-7",  None),
    (M / "112002. - year 8" / "1120020. - past papers",   "mathematics", "year-8",  None),
    (M / "112003. - year 9" / "1120030. - past papers",   "mathematics", "year-9",  None),
    (M / "112004. - year 10" / "1120040. - past papers",  "mathematics", "year-10", None),
    (Y11 / "1120050. - standard" / "11200500. - past papers",  "mathematics", "year-11", "standard"),
    (Y11 / "1120051. - advanced" / "11200510. - past papers",  "mathematics", "year-11", "advanced"),
    (Y11 / "1120052. - extension 1" / "11200520. - past papers","mathematics","year-11","extension-1"),
    (Y12 / "1120060. - standard 2" / "11200600. - past papers", "mathematics", "year-12", "standard-2"),
    (Y12 / "1120061. - advanced" / "11200610. - past papers",  "mathematics", "year-12", "advanced"),
    (Y12 / "1120062. - extension 1" / "11200620. - past papers","mathematics","year-12","extension-1"),
    (Y12 / "1120063. - extension 2" / "11200630. - past papers","mathematics","year-12","extension-2"),
    (E / "112011. - past papers",                          "english", "year-12", None),
    # staging piles: ylevel/stream are None -> parsed per-file from the filename
    (M / "sort",                                           "mathematics", None, None),
]

KNOWN_SCHOOLS = [
    "north sydney girls", "north sydney boys", "sydney boys", "sydney girls",
    "sydney tech", "james ruse", "baulkham hills", "hornsby girls", "hornsby boys",
    "epping boys", "normanhurst", "fort street", "kings", "knox", "abbotsleigh",
    "ascham", "ravenswood", "pymble", "barker", "newington", "trinity", "girraween",
    "penrith", "caringbah", "st george", "blacktown", "hurlstone", "sefton",
]
SOL_MARKERS = ["solutions", "solution", "soln", "-sol", " sol", "handsoln",
               "sample solution", "marking guideline", "-mg", " mg", "answers", "worked"]
TYPE_WORDS = {
    "half-yearly": ["half yearly", "half-yearly", "halfyearly", "half year"],
    "yearly":      ["yearly"],
    "trial":       ["trial"],
    "hsc":         ["hsc"],
    "prelim":      ["prelim", "preliminary"],
    "notification":["notification", "notice"],
    "sample":      ["sample"],
}

def kebab(s: str) -> str:
    s = s.lower().replace("&", " and ").replace("—", "-").replace("–", "-")
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return re.sub(r"-+", "-", s).strip("-")

def collapse_ext(name: str):
    """'X.pdf.pdf' -> ('X','pdf');  drop ~backups handled by caller."""
    m = re.match(r"^(.*?)((?:\.[A-Za-z0-9]{1,5})+)$", name)
    if not m:
        return name, ""
    stem, exts = m.group(1), m.group(2).lower()
    parts = [p for p in exts.split(".") if p]
    ext = parts[-1] if parts else ""
    return stem, ext

def classify(filename: str, subject: str):
    """Return (clean_basename, facets) or None to skip."""
    if filename.startswith(".") or filename.lower() in ("icon\r", "icon"):
        return None
    if filename.endswith("~") or re.search(r"\.~\d+~$", filename):
        return None  # editor/Drive backup copies
    stem, ext = collapse_ext(filename)
    if ext not in ("pdf", "docx", "doc", "pptx", "ppt"):
        return None
    low = stem.lower()
    is_sol = any(mk in low for mk in SOL_MARKERS)

    ym = re.search(r"(19|20)\d{2}", stem)
    year = ym.group(0) if ym else None
    # coded form  NN-YYtT-...  (e.g. 08-19t2 / 09-18T4)
    cm = re.match(r"^\d{2}-(\d{2})[tT](\d)", stem)
    if cm and not year:
        year = "20" + cm.group(1)
    term = cm.group(2) if cm else None

    school = next((s for s in KNOWN_SCHOOLS if s in low), None)

    typ = None
    for canon, variants in TYPE_WORDS.items():
        if any(v in low for v in variants):
            typ = canon; break
    # assessment / task number: "Task 3", "Assessment Task 2", "AT1", "assess3"
    am = re.search(r"(?:assessment\s*task|assess(?:ment)?|task|\bat)\s*-?\s*([1-4])\b", low)
    if am:
        typ = f"assessment-{am.group(1)}"
    pm = re.search(r"(?:paper[-\s]?|[-\s]p)(\d)\b", low)
    paper = pm.group(1) if pm else None

    # year-level parsed from filename ("Year 8", "Yr 10", "Year 09")
    ylevel = None
    ylm = re.search(r"\b(?:year|yr)\s*0?(\d{1,2})\b", low)
    if ylm and 5 <= int(ylm.group(1)) <= 12:
        ylevel = f"year-{int(ylm.group(1))}"

    # stream parsed from filename (most-specific first)
    if   re.search(r"\b(?:ext(?:ension)?\s*2|x2|4\s*unit)\b", low):  stream = "extension-2"
    elif re.search(r"\b(?:ext(?:ension)?\s*1|x1|3\s*unit)\b", low):  stream = "extension-1"
    elif re.search(r"\b(?:advanced|adv|2\s*unit)\b", low):           stream = "advanced"
    elif re.search(r"\b(?:standard|general)\b", low):                stream = "standard"
    else:                                                            stream = None
    level = stream  # for english naming

    # --- term (NSW school year has 4 terms; half-yearly==T2, yearly==T4) ---
    tnum = term  # explicit tN from coded NN-YYtT filename wins
    if not tnum:
        if   am and am.group(1) in "1234":                           tnum = am.group(1)
        elif typ == "half-yearly" or re.search(r"\bhy\b", low):      tnum = "2"
        elif typ == "yearly":                                        tnum = "4"
        elif typ == "trial":                                         tnum = "3"
        elif typ in ("hsc", "prelim"):                               tnum = "4"
        else:
            tm = re.search(r"\bterm[-\s]?([1-4])\b", low) or re.search(r"\bt([1-4])\b", low)
            tnum = tm.group(1) if tm else None

    if not typ and tnum:            # avoid bare "2018--solutions"; carry the term
        typ = f"t{tnum}"
    parts = []
    if year:   parts.append(year)
    if school: parts.append(kebab(school))
    if level and subject == "english": parts.append(level)
    if typ:    parts.append(typ)
    if paper:  parts.append(f"paper-{paper}")
    if not parts:                       # nothing parsed -> kebab the original stem
        parts = [kebab(stem) or "paper"]
    base = "-".join(parts)
    if is_sol and not base.endswith("solutions"):
        base += "--solutions"
    return f"{base}.{ext}", dict(year=year, school=school, type=typ, sol=is_sol,
                                 term=tnum, ylevel=ylevel, stream=stream)

# term-folder names carry fuzzy-match aliases in parentheses
TERM_FOLDERS = {"1": "t1", "2": "t2 (half-yearly, hy)",
                "3": "t3 (trial)", "4": "t4 (yearly, hsc)"}
def term_folder(tnum):
    return TERM_FOLDERS.get(tnum, "unknown-term")

# ---------------------------------------------------------------------------
def rel_symlink(target: Path, link: Path, plan: list):
    if not target.exists():
        plan.append(("MISSING-SRC", link, target)); return
    rel = os.path.relpath(target, link.parent)
    if link.is_symlink() or link.exists():
        try:
            if link.is_symlink() and os.readlink(link) == rel:
                return  # already correct
        except OSError:
            pass
        if not DRY:
            if link.is_symlink() or link.is_file():
                link.unlink()
            elif link.is_dir():
                return  # never clobber a real dir
    plan.append(("link", link, rel))
    if not DRY:
        link.parent.mkdir(parents=True, exist_ok=True)
        os.symlink(rel, link)

def map_into_lattice(real: Path):
    """Where does an absolute Documents path land inside lattice? (longest match)."""
    best = None
    for s, d in TOPLEVEL:
        if s.is_symlink():
            continue
        try:
            rel = real.relative_to(s)
        except ValueError:
            continue
        if best is None or len(str(s)) > best[0]:
            best = (len(str(s)), ROOT / d / rel)
    return best[1] if best else None

def copy_tree(src: Path, dest: Path, extra, plan):
    """rsync a whole tree as real files (preserving symlinks; relativised later)."""
    if src.is_symlink():
        # don't duplicate the target; re-point dest into the target's lattice home
        real = Path(os.path.realpath(src))
        mapped = map_into_lattice(real)
        if mapped is None:
            plan.append(("skip-syslink", dest, real)); return   # e.g. -> /usr/local/bin
        plan.append(("symlink-src", dest, mapped))
        if not DRY:
            dest.parent.mkdir(parents=True, exist_ok=True)
            if dest.is_symlink() or dest.exists():
                dest.unlink() if dest.is_symlink() or dest.is_file() else None
            os.symlink(os.path.relpath(mapped, dest.parent), dest)
        return
    if not src.exists():
        plan.append(("MISSING-SRC", dest, src)); return
    plan.append(("copytree", dest, src))
    cmd = [RSYNC, "-a"]
    for e in COPY_EXCLUDES + list(extra):
        cmd.append(f"--exclude={e}")
    if DRY:
        cmd.append("-n")
    cmd += [f"{src}/", f"{dest}/"]
    if not DRY:
        if dest.is_symlink():          # never rsync THROUGH a leftover overlay symlink
            dest.unlink()              # (that would write into ~/Documents!)
        dest.mkdir(parents=True, exist_ok=True)
    subprocess.run(cmd, check=False,
                   stdout=subprocess.DEVNULL if not DRY else None)

def copy_file(target: Path, link: Path, plan):
    """Copy one file to a clean-named destination (real file)."""
    if not target.exists():
        plan.append(("MISSING-SRC", link, target)); return
    if link.exists() and link.stat().st_size == target.stat().st_size:
        return  # already copied (idempotent)
    plan.append(("copyfile", link, target))
    if not DRY:
        link.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, link)

def materialize(target, link, plan):
    (copy_file if MODE == "copy" else rel_symlink)(target, link, plan)

def relativize_symlinks():
    """Rewrite any absolute symlink inside ~/lattice to a relative one, so the
    lattice root location no longer matters (portability)."""
    fixed = 0
    for link in ROOT.rglob("*"):
        if link.is_symlink():
            tgt = os.readlink(link)
            # only internal (home) targets; leave /usr /opt /System absolute
            if os.path.isabs(tgt) and tgt.startswith(str(HOME)):
                newrel = os.path.relpath(tgt, link.parent)
                if not DRY:
                    link.unlink(); os.symlink(newrel, link)
                fixed += 1
    return fixed

def build_skeleton(plan):
    for d in ["0-inbox", "1-projects", "2-areas", "3-resources",
              "3-resources/past-papers", "4-archive", "code", "_meta"]:
        p = ROOT / d
        plan.append(("dir", p, ""))
        if not DRY:
            p.mkdir(parents=True, exist_ok=True)

def build_toplevel(plan):
    for src, dest in TOPLEVEL:
        if MODE == "copy":
            copy_tree(src, ROOT / dest, ENTRY_EXCLUDES.get(dest, []), plan)
        else:
            rel_symlink(src, ROOT / dest, plan)

NATIVE = DOCS / "past-papers"   # clean, backed-up home for NEW papers (add-paper writes here)

def build_papers(plan, stats):
    seen = {}   # dest dir -> set(names) for collision handling
    # 1:1 link the native store (names already clean; preserve sub-paths)
    if NATIVE.is_dir():
        for f in sorted(NATIVE.rglob("*")):
            if f.is_file() and not f.name.startswith("."):
                rel = f.relative_to(NATIVE)
                dest = ROOT / "3-resources" / "past-papers" / rel
                seen.setdefault(dest.parent, set()).add(dest.name)
                materialize(f, dest, plan)
                stats["papers"] += 1
    for src, subject, src_ylevel, src_stream in PAPER_SOURCES:
        if not src.is_dir():
            stats["missing_src"].append(str(src)); continue
        staging = src_ylevel is None   # parse ylevel/stream from each filename
        for f in sorted(src.rglob("*")):
            if not f.is_file():
                continue
            res = classify(f.name, subject)
            if res is None:
                continue
            clean, facets = res
            if staging:
                ylevel = facets.get("ylevel")
                stream = facets.get("stream")
                if not ylevel:   # extension 2 only exists in year 12
                    ylevel = "year-12" if stream == "extension-2" else "unknown-year-level"
            else:
                ylevel, stream = src_ylevel, src_stream
            base = ROOT / "3-resources" / "past-papers" / subject / ylevel
            if stream:
                base = base / stream
            dest_dir = base / term_folder(facets["term"])
            names = seen.setdefault(dest_dir, set())
            # collision -> -2, -3 ...
            stem, dot, ext = clean.rpartition(".")
            final = clean; n = 2
            while final in names:
                final = f"{stem}-{n}.{ext}"; n += 1
            names.add(final)
            materialize(f, dest_dir / final, plan)
            stats["papers"] += 1
            if not facets["year"] and not facets["school"] and not facets["type"]:
                stats["unparsed"].append(f"{subject}/{ylevel}: {f.name}")

def write_index(stats):
    """Generate _meta/past-papers-index.org from the built overlay."""
    pp = ROOT / "3-resources" / "past-papers"
    rows = []
    if pp.is_dir():
        for link in sorted(pp.rglob("*")):
            if not link.is_file():        # real file (copy mode) or resolvable symlink
                continue
            relp = link.relative_to(pp)
            parts = relp.parts[:-1]   # subject / year-level [/ stream] / term-folder
            term = parts[-1] if parts else ""
            rest = parts[:-1]
            subject = rest[0] if len(rest) > 0 else ""
            ylevel  = rest[1] if len(rest) > 1 else ""
            stream  = rest[2] if len(rest) > 2 else ""
            name = link.name
            sol = "yes" if "--solutions" in name else ""
            ym = re.match(r"(\d{4})", name)
            year = ym.group(1) if ym else ""
            rows.append((subject, ylevel, stream, term, year, sol, name,
                         os.path.relpath(link, META)))
    lines = [
        ":PROPERTIES:",
        ":ID:       past-papers-index",
        ":END:",
        "#+title: Past Papers — Index",
        "#+startup: overview",
        f"#+caption: {len(rows)} papers — regenerate with `lattice index`",
        "",
        "| Subject | Year level | Stream | Term | Year | Sol | File |",
        "|-+-+-+-+-+-+-|",
    ]
    for r in rows:
        subj, yl, st, term, yr, sol, name, link = r
        lines.append(f"| {subj} | {yl} | {st} | {term} | {yr} | {sol} | [[file:{link}][{name}]] |")
    if not DRY:
        META.mkdir(parents=True, exist_ok=True)
        (META / "past-papers-index.org").write_text("\n".join(lines) + "\n")
        if stats["unparsed"]:
            (META / "papers-unparsed.log").write_text("\n".join(stats["unparsed"]) + "\n")
    return len(rows)

def main():
    global DRY, SCOPE, MODE
    args = sys.argv[1:]
    if "--apply" in args: DRY = False
    if "--copy" in args: MODE = "copy"
    if "--clean" in args:
        if ROOT.exists():
            print(f"removing {ROOT}")
            if "--apply" in args or input(f"rm -rf {ROOT}? [y/N] ").lower() == "y":
                shutil.rmtree(ROOT)
        return
    if "--papers-only" in args: SCOPE = "papers"
    if "--skel-only" in args: SCOPE = "skel"

    if "--index-only" in args:
        DRY = False
        n = write_index({"papers": 0, "unparsed": [], "missing_src": []})
        print(f"index regenerated: {n} papers")
        return

    # prune broken symlinks left behind when a source disappears (everything is local,
    # so a dangling link genuinely means the target is gone)
    if not DRY and ROOT.exists():
        pruned = 0
        for link in ROOT.rglob("*"):
            if link.is_symlink() and not link.exists():
                link.unlink(); pruned += 1
        if pruned:
            print(f"pruned {pruned} broken symlinks")

    plan, stats = [], {"papers": 0, "unparsed": [], "missing_src": []}
    build_skeleton(plan)
    if SCOPE in ("all", "skel"):
        build_toplevel(plan)
    if SCOPE in ("all", "papers"):
        build_papers(plan, stats)
    n_index = write_index(stats)
    rel_fixed = relativize_symlinks() if (MODE == "copy" and not DRY) else 0
    # copy hygiene: drop symlinks that dangle after a partial copy (excluded
    # node_modules, off-device reMarkable refs, …); log them for audit.
    pruned_broken = 0
    if MODE == "copy" and not DRY:
        blog = []
        for link in ROOT.rglob("*"):
            if link.is_symlink() and not link.exists():
                blog.append(f"{link.relative_to(ROOT)} -> {os.readlink(link)}")
                link.unlink(); pruned_broken += 1
        if blog:
            META.mkdir(parents=True, exist_ok=True)
            (META / "pruned-broken-symlinks.log").write_text("\n".join(blog) + "\n")

    links   = [p for p in plan if p[0] == "link"]
    trees   = [p for p in plan if p[0] == "copytree"]
    files   = [p for p in plan if p[0] == "copyfile"]
    missing = [p for p in plan if p[0] == "MISSING-SRC"]
    verb = "DRY-RUN" if DRY else "APPLIED"
    if MODE == "copy":
        print(f"{verb} [copy]: {len(trees)} trees, {len(files)} paper-files, "
              f"{stats['papers']} papers, {n_index} indexed, "
              f"{rel_fixed} symlinks relativised, {pruned_broken} broken-pruned, "
              f"{len(missing)} missing-source")
    else:
        print(f"{verb}: {len(links)} symlinks, {stats['papers']} papers, {n_index} indexed, "
              f"{len(missing)} missing-source, {len(stats['unparsed'])} unparsed-names")
    if missing:
        print("\nMISSING SOURCES (skipped):")
        for _, link, tgt in missing[:40]:
            print(f"  {link.relative_to(ROOT)}  <-  {tgt}")
    if DRY:
        sample = (trees or files or links)[:25]
        print("\nsample:")
        for kind, link, ref in sample:
            arrow = "<=rsync=" if kind == "copytree" else ("<=cp=" if kind == "copyfile" else "->")
            print(f"  {link.relative_to(ROOT)}  {arrow}  {ref}")
        print("\n(dry-run — nothing written. re-run with --apply)")

if __name__ == "__main__":
    main()
