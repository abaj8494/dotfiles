#!/usr/bin/env python3
"""zoxide-reroute.py — migrate every ~/Documents zoxide entry to its ~/lattice
counterpart, preserving frecency rank/ordering.

For each stored Documents path we compute its lattice home two ways:
  1. realpath() — catches the P2 shims (Documents/<x> is a symlink INTO lattice);
  2. build.map_into_lattice() — the TOPLEVEL longest-prefix map, for the
     P4-pending dirs that are still real copies (uni, media, doc, Google Drive, ...).
The computed target is migrated ONLY if it actually exists under ~/lattice. Anything
whose target was renamed/dissolved by the refactor (no clean 1:1 home) is DROPPED and
reported — never silently mis-pointed.

Migration = re-add the lattice path via `zoxide import --from z --merge` carrying the
old score as the rank (time=now, so all land in the same recency bucket → ordering
preserved), then `zoxide remove` the Documents path.

  zoxide-reroute.py           # dry-run: print migrate / drop plan
  zoxide-reroute.py --apply   # back up db.zo, import lattice entries, remove Documents
"""
import os, re, sys, time, shutil, subprocess
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build  # noqa: E402  — uses TOPLEVEL + map_into_lattice (has __main__ guard)

HOME = Path.home()
DOCS = HOME / "Documents"
ROOT = HOME / "lattice"
APPLY = "--apply" in sys.argv
def _data_dir():
    if os.environ.get("_ZO_DATA_DIR"):
        return Path(os.environ["_ZO_DATA_DIR"])
    # zoxide uses the platform data-local dir: macOS = Application Support.
    for c in (HOME / "Library/Application Support/zoxide",
              HOME / ".local/share/zoxide"):
        if (c / "db.zo").exists():
            return c
    return HOME / ".local/share/zoxide"


DATA_DIR = _data_dir()
DB = DATA_DIR / "db.zo"


def current_entries():
    out = subprocess.run(["zoxide", "query", "--list", "--score"],
                         capture_output=True, text=True, check=True).stdout
    rows = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        score_str, _, path = line.partition(" ")
        rows.append((float(score_str), path.strip()))
    return rows


# post-refactor relocations that build.TOPLEVEL predates (dirs were moved by
# refactor.py after the map was written). Longest-prefix wins, like TOPLEVEL.
OVERRIDES = [
    (DOCS / "kiyomi", ROOT / "2-areas/devices/kiyomi-backups"),  # people→devices
    (DOCS / "deez",   ROOT / "3-resources/doc/frisbee/deez"),    # →doc/frisbee
]


def lattice_target(path: str):
    """Return an existing ~/lattice Path for a Documents entry, or None."""
    p = Path(path)
    if p == DOCS:
        return ROOT                                   # bare Documents → lattice root
    # 0) explicit post-refactor overrides (longest prefix)
    for src, dest in sorted(OVERRIDES, key=lambda o: -len(str(o[0]))):
        try:
            rel = p.relative_to(src)
        except ValueError:
            continue
        tgt = dest / rel
        if tgt.exists():
            return tgt
        break
    # *.pre-lattice originals: map as if the live (shimmed) dir
    if ".pre-lattice" in path:
        m = build.map_into_lattice(Path(path.replace(".pre-lattice", "", 1)))
        if m is not None and m.exists() and ROOT in m.parents:
            return m
    rp = Path(os.path.realpath(path))
    # 1) shim case: realpath resolves through the symlink into lattice
    if rp != p and ROOT in rp.parents and rp.exists():
        return rp
    # 2) real-copy case: longest-prefix TOPLEVEL map
    mapped = build.map_into_lattice(p)
    if mapped is not None and mapped.exists() and ROOT in mapped.parents:
        return mapped
    return None


def main():
    rows = current_entries()
    docs = [(s, p) for s, p in rows if p == str(DOCS) or p.startswith(str(DOCS) + os.sep)]

    migrate = {}          # lattice_path -> summed score
    pairs = []            # (docs_path, lattice_path, score)
    drops = []            # (docs_path, score)
    for score, path in docs:
        tgt = lattice_target(path)
        if tgt is None:
            drops.append((score, path))
            continue
        migrate[str(tgt)] = migrate.get(str(tgt), 0.0) + score
        pairs.append((path, str(tgt), score))

    print(f"{'APPLY' if APPLY else 'DRY-RUN'}: {len(docs)} Documents entries → "
          f"{len(migrate)} lattice targets, {len(drops)} dropped (no 1:1 home)\n")

    print("MIGRATE (old Documents score → lattice path):")
    for path, tgt, score in sorted(pairs, key=lambda r: -r[2]):
        print(f"  {score:7.1f}  {path.replace(str(HOME),'~')}")
        print(f"           → {tgt.replace(str(HOME),'~')}")
    if drops:
        print("\nDROPPED (renamed/dissolved by refactor, or not yet in lattice — "
              "rebuild frecency by navigating the new tree):")
        for score, path in sorted(drops, key=lambda r: -r[0]):
            print(f"  {score:7.1f}  {path.replace(str(HOME),'~')}")

    if not APPLY:
        print("\n(dry-run — db untouched. re-run with --apply)")
        return

    # --- back up the db ---
    if DB.exists():
        bk = DB.with_suffix(".zo.pre-reroute")
        if not bk.exists():
            shutil.copy2(DB, bk)
            print(f"\nbackup -> {bk}")
        else:
            print(f"\nbackup already exists -> {bk} (kept)")

    # --- import lattice entries, preserving the displayed score ---
    # time=now puts every entry in zoxide's "<1h" bucket (×4 frecency multiplier),
    # so we store rank=score/4 to make the *displayed* score equal the old one.
    now = int(time.time())
    zfile = DATA_DIR / "reroute.z"
    with open(zfile, "w") as fh:
        for tgt, score in migrate.items():
            fh.write(f"{tgt}|{score / 4.0}|{now}\n")
    subprocess.run(["zoxide", "import", "--from", "z", "--merge", str(zfile)], check=True)
    zfile.unlink()
    print(f"imported {len(migrate)} lattice entries (merged)")

    # --- remove every Documents entry ---
    removed = 0
    for _, path in docs:
        r = subprocess.run(["zoxide", "remove", path], capture_output=True, text=True)
        if r.returncode == 0:
            removed += 1
    print(f"removed {removed}/{len(docs)} Documents entries")


if __name__ == "__main__":
    main()
