#!/usr/bin/env python3
"""Interactive Brother DS-940DW scanner → single multi-page PDF.

Usage:  scan-doc.py [OUTPUT_DIR] [--duplex] [--append PATH]

Prompts for a filename (no extension), then loops: press Enter to run
one ADF pass (every sheet currently loaded becomes one page in the
output PDF), 'q' to finish and assemble. Defaults OUTPUT_DIR to the
current working directory so this is safe to invoke from a vterm
rooted in whatever buffer the user was editing.

At the filename prompt, type 'a' (or 'append') to instead append to
an existing PDF — the script will ask for its path (with tab
completion) and overwrite the original with the appended result at
the end via an atomic rename.  You can also skip the prompt by passing
--append PATH on the command line.

Stdlib-only for the scanner side; pymupdf for the final merge.
Reuses ~/.cache/receipt-ocr-scanner.json so discovery is instant after
the first successful run by either this script or receipt-ocr's scan.py.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import readline
import select
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
import tempfile
import shutil

SCANNER_NAME_MATCH = "DS-940DW"
ENDPOINT_CACHE = Path("~/.cache/receipt-ocr-scanner.json").expanduser()


MODE_TO_ESCL = {
    "bw": "BlackAndWhite1",
    "gray": "Grayscale8",
    "color": "RGB24",
}

# Scan-region width in escl:ThreeHundredthsOfInches (1/300"). 2550 = 8.5".
# Shared by build_scan_xml and the raw-1bit decoder so the pixel width it
# derives (REGION_WIDTH_UNITS * dpi / 300) always matches what we asked for.
REGION_WIDTH_UNITS = 2550


def build_scan_xml(duplex: bool, dpi: int, mode: str) -> bytes:
    # Scan-region Height is in 1/300" (escl:ThreeHundredthsOfInches). Simplex
    # can image the DS-940DW's full AdfSimplexInputCaps MaxHeight — 36600 =
    # 122" — so an arbitrarily long sheet (fold-out manual page, long receipt)
    # scans in one pass instead of being cut off. AdfDuplex caps at 4200 = 14",
    # so duplex passes must stay there.
    #
    # Duplex MUST be pinned explicitly. With no <scan:Duplex> element the
    # scanner falls back to its duplex default, which re-imposes the 14" cap
    # and silently jams / truncates anything longer (this is why long docs
    # weren't working). So always emit it: false for simplex — which is what
    # unlocks the full 122" — and true for duplex.
    height = 4200 if duplex else 36600
    duplex_elt = "  <scan:Duplex>%s</scan:Duplex>\n" % ("true" if duplex else "false")
    color_mode = MODE_TO_ESCL[mode]
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<scan:ScanSettings xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm"'
        ' xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03">\n'
        "  <pwg:Version>2.63</pwg:Version>\n"
        "  <pwg:ScanRegions>\n"
        "    <pwg:ScanRegion>\n"
        "      <pwg:ContentRegionUnits>escl:ThreeHundredthsOfInches</pwg:ContentRegionUnits>\n"
        f"      <pwg:Height>{height}</pwg:Height>\n"
        f"      <pwg:Width>{REGION_WIDTH_UNITS}</pwg:Width>\n"
        "      <pwg:XOffset>0</pwg:XOffset>\n"
        "      <pwg:YOffset>0</pwg:YOffset>\n"
        "    </pwg:ScanRegion>\n"
        "  </pwg:ScanRegions>\n"
        "  <pwg:InputSource>Feeder</pwg:InputSource>\n"
        f"  <scan:ColorMode>{color_mode}</scan:ColorMode>\n"
        "  <scan:DocumentFormatExt>application/pdf</scan:DocumentFormatExt>\n"
        f"{duplex_elt}"
        f"  <scan:XResolution>{dpi}</scan:XResolution>\n"
        f"  <scan:YResolution>{dpi}</scan:YResolution>\n"
        "</scan:ScanSettings>\n"
    ).encode()


def load_cached_endpoint() -> str | None:
    if not ENDPOINT_CACHE.exists():
        return None
    try:
        data = json.loads(ENDPOINT_CACHE.read_text())
    except (json.JSONDecodeError, OSError):
        return None
    return data.get("base_url") if isinstance(data, dict) else None


def save_cached_endpoint(base_url: str) -> None:
    if "localhost" in base_url:
        return
    ENDPOINT_CACHE.parent.mkdir(parents=True, exist_ok=True)
    ENDPOINT_CACHE.write_text(json.dumps({"base_url": base_url}, indent=2) + "\n")


def probe_endpoint(base_url: str, timeout: float = 4.0) -> bool:
    try:
        with urllib.request.urlopen(
            f"{base_url}/eSCL/ScannerStatus", timeout=timeout
        ) as resp:
            return 200 <= resp.status < 300
    except (urllib.error.URLError, TimeoutError, OSError):
        return False


def find_instance(timeout_s: float = 20.0) -> str:
    proc = subprocess.Popen(
        ["dns-sd", "-B", "_uscan._tcp"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    pattern = re.compile(r"_uscan\._tcp\.\s+(.+?)\s*$")
    deadline = time.time() + timeout_s
    try:
        while time.time() < deadline:
            remaining = max(0.05, min(0.5, deadline - time.time()))
            ready, _, _ = select.select([proc.stdout], [], [], remaining)
            if not ready:
                continue
            line = proc.stdout.readline()
            if not line:
                continue
            m = pattern.search(line.rstrip())
            if m and SCANNER_NAME_MATCH in m.group(1):
                return m.group(1)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            proc.kill()
    raise RuntimeError(
        f"no _uscan._tcp advert for *{SCANNER_NAME_MATCH}* in {timeout_s:.0f}s — "
        "is the scanner powered on and on the LAN / plugged in?"
    )


def resolve_endpoint(instance: str, timeout_s: float = 6.0) -> tuple[subprocess.Popen, str]:
    proc = subprocess.Popen(
        ["dns-sd", "-L", instance, "_uscan._tcp", "local"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    pattern = re.compile(r"can be reached at\s+(\S+?):(\d+)")
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        line = proc.stdout.readline()
        if not line:
            time.sleep(0.05)
            continue
        m = pattern.search(line)
        if m:
            host = m.group(1).rstrip(".")
            port = m.group(2)
            return proc, f"http://{host}:{port}"
    proc.terminate()
    raise RuntimeError(f"timed out resolving {instance}")


def post_scan(base: str, duplex: bool, dpi: int, mode: str) -> str:
    req = urllib.request.Request(
        f"{base}/eSCL/ScanJobs",
        data=build_scan_xml(duplex, dpi, mode),
        method="POST",
        headers={"Content-Type": "text/xml"},
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        loc = resp.headers.get("Location")
    if not loc:
        raise RuntimeError("scan job POST returned no Location header")
    return loc.lstrip("/")


def save_raw_1bit(body: bytes, tmpdir: Path, idx: int, dpi: int) -> Path | None:
    """Decode a headerless 1-bit ADF raster into a 1-bit PNG, or None.

    In bw mode (escl:BlackAndWhite1) the DS-940DW ignores the
    application/pdf DocumentFormatExt and streams raw packed 1-bit
    pixels with no container — first bytes look like 0xff runs (the
    white margin), which sniff_and_name can't fingerprint. We know the
    geometry: width is the fixed scan region (REGION_WIDTH_UNITS in
    1/300") scaled to the active dpi, rows are byte-padded, so
    height = len / stride. PWG bi-level packs 1=black; PIL '1' uses
    1=white, hence the per-byte bitwise-NOT before frombytes. Returns
    the PNG path on success, or None if the body doesn't fit the raster
    shape (so the caller can fall back to .bin and preserve the bytes).
    """
    width_px = round(REGION_WIDTH_UNITS * dpi / 300)
    stride = (width_px + 7) // 8
    if width_px <= 0 or len(body) < stride * 2 or len(body) % stride != 0:
        return None
    try:
        from PIL import Image
    except ImportError:
        return None
    height = len(body) // stride
    img = Image.frombytes("1", (width_px, height), body.translate(_BIT_INVERT))
    path = tmpdir / f"page-{idx:04d}.png"
    img.save(path)
    return path


# Per-byte bitwise-NOT table: flips PWG 1=black raster into PIL 1=white.
_BIT_INVERT = bytes(255 - i for i in range(256))


def sniff_and_name(body: bytes, tmpdir: Path, idx: int, dpi: int) -> Path:
    """Save body to tmpdir with an extension matching its magic bytes.

    The Brother scanner is asked for application/pdf but will happily
    return JPEG for some pages, or — in bw mode — a headerless raw 1-bit
    raster (decoded via save_raw_1bit). Mirrors scan.py's behavior.
    """
    if body[:3] == b"\xff\xd8\xff":
        ext = ".jpg"
    elif body[:4] == b"%PDF":
        ext = ".pdf"
    else:
        raw = save_raw_1bit(body, tmpdir, idx, dpi)
        if raw is not None:
            return raw
        ext = ".bin"  # unknown — let merge diagnose by content
    path = tmpdir / f"page-{idx:04d}{ext}"
    path.write_bytes(body)
    return path


def fetch_all_pages(
    base: str, job_path: str, tmpdir: Path, next_idx: int, dpi: int
) -> list[Path]:
    """Drain /NextDocument until 404; save each page with its real extension."""
    out: list[Path] = []
    while True:
        try:
            with urllib.request.urlopen(
                f"{base}/{job_path}/NextDocument", timeout=120
            ) as resp:
                body = resp.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                break
            raise
        except urllib.error.URLError:
            break
        out.append(sniff_and_name(body, tmpdir, next_idx + len(out), dpi))
    return out


def rotate_180(path: Path) -> bool:
    """Rotate one page (JPEG/PNG via sips, PDF via pymupdf) 180° in place.

    eSCL only exposes a boolean Duplex flag — short-edge bind (top-bound
    notebooks like spirax) needs every back page flipped client-side so
    reading order matches a long-edge flip. Returns True on success.
    """
    suf = path.suffix.lower()
    if suf in {".jpg", ".jpeg", ".png"}:
        try:
            subprocess.run(
                ["sips", "-r", "180", str(path), "--out", str(path)],
                check=True,
                capture_output=True,
            )
            return True
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            print(f"\n  WARN: sips rotate failed for {path.name}: {e}")
            return False
    if suf == ".pdf":
        try:
            import pymupdf
            staged = path.with_suffix(path.suffix + ".rot")
            with pymupdf.open(path) as doc:
                for page in doc:
                    page.set_rotation((page.rotation + 180) % 360)
                doc.save(staged)
            os.replace(staged, path)
            return True
        except Exception as e:
            print(f"\n  WARN: pymupdf rotate failed for {path.name}: {e}")
            return False
    return False


def adf_state(base: str) -> str | None:
    try:
        with urllib.request.urlopen(f"{base}/eSCL/ScannerStatus", timeout=4) as resp:
            xml = resp.read().decode("utf-8", "replace")
    except Exception:
        return None
    m = re.search(r"<scan:AdfState>\s*([^<\s]+)", xml)
    return m.group(1) if m else None


def cancel_all_jobs(base: str) -> int:
    killed = 0
    try:
        with urllib.request.urlopen(f"{base}/eSCL/ScannerStatus", timeout=4) as resp:
            xml = resp.read().decode("utf-8", "replace")
    except Exception:
        return 0
    for job in set(re.findall(r"<pwg:JobUri>\s*([^<\s]+)", xml)):
        try:
            req = urllib.request.Request(f"{base}{job}", method="DELETE")
            urllib.request.urlopen(req, timeout=4).read()
            killed += 1
        except Exception:
            pass
    return killed


def slugify(name: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9._-]+", "-", name).strip("-.")
    return s or "scan"


def prompt_existing_pdf(start_dir: Path) -> Path | None:
    """Prompt for an existing PDF path with tab completion.

    Relative paths resolve against start_dir so the attach-dir workflow
    ('cd' into the dir, hit C-c s, type 'a', type the basename) works
    without full absolute paths. Returns None if the user bails out.
    """
    prev_completer = readline.get_completer()
    prev_delims = readline.get_completer_delims()
    readline.set_completer_delims(" \t\n")
    # libedit vs GNU readline have different bind syntax on macOS.
    if "libedit" in (readline.__doc__ or ""):
        readline.parse_and_bind("bind ^I rl_complete")
    else:
        readline.parse_and_bind("tab: complete")

    def _completer(text: str, state: int):
        raw = os.path.expanduser(text)
        # Let glob resolve relative entries against start_dir.
        base = raw if os.path.isabs(raw) else str(start_dir / raw)
        matches = glob.glob(base + "*")
        trimmed: list[str] = []
        for m in matches:
            # Return paths in the same form the user typed: if they
            # started with an absolute/~ path, keep absolute; if they
            # typed a relative chunk, strip the start_dir prefix.
            disp = m
            if not os.path.isabs(raw):
                try:
                    disp = os.path.relpath(m, start_dir)
                except ValueError:
                    pass
            if os.path.isdir(m):
                disp += "/"
            trimmed.append(disp)
        trimmed.sort()
        return trimmed[state] if state < len(trimmed) else None

    readline.set_completer(_completer)
    try:
        try:
            raw = input("append to> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return None
        if not raw:
            return None
        path = Path(os.path.expanduser(raw))
        if not path.is_absolute():
            path = start_dir / path
        path = path.resolve()
        if not path.is_file():
            print(f"  not a file: {path}")
            return None
        if path.suffix.lower() != ".pdf":
            print(f"  not a .pdf: {path.name}")
            return None
        return path
    finally:
        readline.set_completer(prev_completer)
        readline.set_completer_delims(prev_delims)


def prompt_compress(merged_size_kb: int) -> str | None:
    """Show rough size estimates per gs level and prompt for a choice.

    Estimates are typical ratios for 300 dpi color/grayscale Brother JPEGs
    fed through pdfwrite — they're indicative, not measured. Returns the
    chosen level name or None if the user declines.
    """
    mb = merged_size_kb / 1024
    print(f"\nmerged PDF: {merged_size_kb} KB ({mb:.1f} MB)")
    print("compress with Ghostscript? rough size estimates:")
    # (level, divisor, blurb) — divisor is a typical shrink factor.
    ests = [
        ("screen",   30, "~72 dpi  (smallest, fuzzy)"),
        ("ebook",    15, "~150 dpi (good for notes)"),
        ("printer",   3, "~300 dpi (near-lossless)"),
        ("prepress",  2, "~300 dpi (lightest touch)"),
    ]
    for level, divisor, blurb in ests:
        est_mb = mb / divisor
        marker = "*" if level == "ebook" else " "
        print(f"  {marker} {level:<9} {blurb:<32} ≈ {est_mb:.1f} MB")
    print("    none      keep merged as-is")
    while True:
        try:
            raw = input("compress> [ebook] ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print()
            return None
        if not raw:
            return "ebook"
        if raw in ("n", "no", "none", "skip", "keep"):
            return None
        if raw in ("screen", "ebook", "printer", "prepress"):
            return raw
        print(f"  unknown: {raw!r}; pick: screen / ebook / printer / prepress / none")


def gs_compress(src: Path, dst: Path, level: str) -> None:
    """Run Ghostscript to shrink `src` → `dst` at the given preset.

    Levels (gs's standard PDFSETTINGS): screen ~72dpi (smallest, fuzzy),
    ebook ~150dpi (default; good for notes), printer/prepress ~300dpi
    (near-lossless). Re-encodes embedded JPEGs at lower quality and
    downsamples bitmaps. Raises CalledProcessError on gs failure or
    FileNotFoundError if gs isn't installed.
    """
    subprocess.run(
        [
            "gs", "-q",
            "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.4",
            f"-dPDFSETTINGS=/{level}",
            "-dNOPAUSE", "-dBATCH",
            f"-sOutputFile={dst}",
            str(src),
        ],
        check=True,
        capture_output=True,
    )


def merge_pdfs(pages: list[Path], out_path: Path) -> None:
    """Merge a mix of PDF and JPEG pages into a single PDF at out_path."""
    import pymupdf
    doc = pymupdf.open()
    try:
        for p in pages:
            suf = p.suffix.lower()
            if suf == ".pdf":
                with pymupdf.open(p) as src:
                    doc.insert_pdf(src)
            elif suf in {".jpg", ".jpeg", ".png"}:
                # Convert image → 1-page PDF via pymupdf, then splice in.
                img = pymupdf.open(p)
                try:
                    pdf_bytes = img.convert_to_pdf()
                finally:
                    img.close()
                with pymupdf.open(stream=pdf_bytes, filetype="pdf") as src:
                    doc.insert_pdf(src)
            else:
                raise RuntimeError(
                    f"{p.name}: unknown format (first bytes: {p.read_bytes()[:4]!r})"
                )
        doc.save(out_path)
    finally:
        doc.close()


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Interactive DS-940DW → multi-page PDF.")
    ap.add_argument(
        "output_dir",
        nargs="?",
        default=".",
        help="Directory to save the output PDF (default: cwd).",
    )
    ap.add_argument(
        "-d", "--duplex",
        action="store_true",
        help="Scan both sides of each sheet in a single ADF pass (toggle in-session with 'd').",
    )
    ap.add_argument(
        "--edge",
        choices=("long", "short"),
        default="long",
        help="Duplex bind edge: 'long' (book-style; default) or 'short' "
             "(top-bound notebooks like spirax — every back page is rotated 180° "
             "after fetch). Only takes effect when --duplex is on.",
    )
    ap.add_argument(
        "-a", "--append",
        metavar="PATH",
        help="Skip the filename prompt and append new pages to an existing PDF at PATH.",
    )
    ap.add_argument(
        "--dpi",
        type=int,
        default=300,
        choices=(100, 150, 200, 300, 400, 600),
        help="Scan resolution (default 300; 200 is a good size/quality tradeoff, 150 for small text-only).",
    )
    ap.add_argument(
        "--mode",
        choices=("bw", "gray", "color"),
        default="gray",
        help="Color mode: 'bw' (1-bit, smallest — clean printed text only), "
             "'gray' (8-bit grayscale, default), 'color' (24-bit RGB, largest).",
    )
    ap.add_argument(
        "--compress",
        nargs="?",
        const="ebook",
        choices=("screen", "ebook", "printer", "prepress"),
        default=None,
        help="Skip the post-merge compress prompt and apply this gs level "
             "directly. Bare flag = 'ebook' (~150 dpi). Levels: "
             "screen (~72 dpi, smallest), ebook, printer/prepress (~300 dpi). "
             "Without this flag the script prompts interactively after merging. "
             "Requires gs on PATH; falls back to the uncompressed merge on failure.",
    )
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    out_dir = Path(args.output_dir).expanduser().resolve()
    if not out_dir.is_dir():
        print(f"not a directory: {out_dir}", file=sys.stderr)
        return 2
    duplex = args.duplex
    edge = args.edge
    dpi = args.dpi
    mode = args.mode
    append_target: Path | None = None
    if args.append:
        p = Path(args.append).expanduser()
        if not p.is_absolute():
            p = out_dir / p
        p = p.resolve()
        if not p.is_file() or p.suffix.lower() != ".pdf":
            print(f"--append target is not a PDF file: {p}", file=sys.stderr)
            return 2
        append_target = p

    proc: subprocess.Popen | None = None
    cached = load_cached_endpoint()
    if cached and probe_endpoint(cached):
        base = cached
        print(f"scanner: {base}  (cached)")
    else:
        if cached:
            print(f"cached endpoint {cached} unreachable; browsing Bonjour…")
        else:
            print(f"browsing Bonjour for *{SCANNER_NAME_MATCH}*…")
        instance = find_instance()
        print(f"found:   {instance}")
        proc, base = resolve_endpoint(instance)
        save_cached_endpoint(base)
        print(f"scanner: {base}")

    print(f"output:  {out_dir}")
    default_name = datetime.now().strftime("%Y%m%d-%H%M%S")

    if append_target is None:
        try:
            raw = input(
                f"filename (blank = {default_name}, 'a' = append to existing)> "
            ).strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return 1
        if raw.lower() in {"a", "append"}:
            append_target = prompt_existing_pdf(out_dir)
            if append_target is None:
                print("no target chosen; aborting.")
                return 1
        else:
            stem = slugify(raw) if raw else default_name
            final = out_dir / f"{stem}.pdf"
            if final.exists():
                print(f"  {final.name} already exists — will save as a suffixed sibling.")

    pages: list[Path] = []
    tmp = Path(tempfile.mkdtemp(prefix="scan-doc-"))
    orig_page_count = 0

    if append_target is not None:
        # Snapshot the existing file as our first "page" (it's a full PDF
        # with N pages — pymupdf.insert_pdf happily splices them all).
        snapshot = tmp / "page-0000.pdf"
        shutil.copy2(append_target, snapshot)
        try:
            import pymupdf
            with pymupdf.open(snapshot) as src:
                orig_page_count = src.page_count
        except Exception as e:
            print(f"  cannot open {append_target}: {e}")
            return 2
        pages.append(snapshot)
        final = append_target
        print(
            f"append:  {append_target}  ({orig_page_count} existing page(s))"
        )

    print("load page(s) into ADF, press Enter to scan.")
    print("  commands: 'q' finish, 'u' undo last, 'x' abort, 'd' toggle duplex,")
    print("            'e' toggle edge (long/short — for top-bound notebooks),")
    print("            'r' set dpi (100/150/200/300/400/600), 'm' set mode (bw/gray/color)")

    # In append mode pages[0] is a snapshot of the existing PDF (worth
    # N pages) — everything from new_floor onward is freshly scanned and
    # undo/counters should only consider those.
    new_floor = 1 if append_target is not None else 0

    def new_count() -> int:
        return max(0, len(pages) - new_floor)

    def prompt_label() -> str:
        duplex_str = f"duplex={'on/' + edge if duplex else 'off'}"
        settings = f"{dpi}dpi/{mode} | {duplex_str}"
        if append_target is not None:
            return (
                f"[+{new_count()} new | {orig_page_count} existing | {settings}]> "
            )
        return f"[{len(pages)} pg | {settings}]> "

    keep_tmp = False
    try:
        while True:
            try:
                cmd = input(prompt_label()).strip().lower()
            except (EOFError, KeyboardInterrupt):
                print()
                cmd = "q"
            if cmd in {"q", "quit", "done"}:
                break
            if cmd in {"x", "abort"}:
                print("aborted — discarding all scanned pages.")
                return 1
            if cmd == "u":
                if len(pages) <= new_floor:
                    print("  nothing to undo")
                    continue
                dropped = pages.pop()
                try:
                    dropped.unlink()
                except OSError:
                    pass
                print(f"  undone — {new_count()} new page(s) remain")
                continue
            if cmd == "d":
                duplex = not duplex
                print(f"  duplex is now {'ON' if duplex else 'OFF'}")
                continue
            if cmd == "e":
                edge = "short" if edge == "long" else "long"
                hint = "" if duplex else "  (no effect until duplex is ON)"
                print(f"  edge is now {edge}{hint}")
                continue
            if cmd == "r":
                try:
                    raw = input(f"  dpi (current {dpi}, choices 100/150/200/300/600)> ").strip()
                except (EOFError, KeyboardInterrupt):
                    print()
                    continue
                if not raw:
                    continue
                try:
                    new_dpi = int(raw)
                except ValueError:
                    print(f"  not an integer: {raw!r}")
                    continue
                if new_dpi not in (100, 150, 200, 300, 400, 600):
                    print(f"  unsupported dpi: {new_dpi}")
                    continue
                dpi = new_dpi
                print(f"  dpi is now {dpi}")
                continue
            if cmd == "m":
                try:
                    raw = input(f"  mode (current {mode}, choices bw/gray/color)> ").strip().lower()
                except (EOFError, KeyboardInterrupt):
                    print()
                    continue
                if not raw:
                    continue
                if raw not in MODE_TO_ESCL:
                    print(f"  unknown mode: {raw!r}")
                    continue
                mode = raw
                print(f"  mode is now {mode}")
                continue
            # Empty or anything else → scan.
            try:
                print("  posting job…", end=" ", flush=True)
                job = post_scan(base, duplex, dpi, mode)
                print("pulling…", end=" ", flush=True)
                new_pages = fetch_all_pages(base, job, tmp, len(pages), dpi)
            except urllib.error.HTTPError as e:
                print(f"\n  HTTP {e.code}: {e.reason}")
                if e.code == 409:
                    state = adf_state(base)
                    if state and "Empty" in state:
                        print("  ADF is empty — load paper and retry")
                    else:
                        n = cancel_all_jobs(base)
                        print(f"  ADF state={state}; cleared {n} stuck job(s) — retry")
                elif e.code in {400, 415} and duplex:
                    print("  scanner rejected the request with duplex on — "
                          "try 'd' to disable and scan each side manually")
                continue
            except (urllib.error.URLError, RuntimeError) as e:
                print(f"\n  ERROR: {e}")
                continue
            if not new_pages:
                print("no pages returned (ADF empty?)")
                continue
            rotated = 0
            if duplex and edge == "short" and len(new_pages) > 1:
                # eSCL returns front, back, front, back... — flip every back
                # page so a top-edge bind reads upright after the merge.
                for i, p in enumerate(new_pages, 1):
                    if i % 2 == 0 and rotate_180(p):
                        rotated += 1
            total_kb = sum(p.stat().st_size for p in new_pages) // 1024
            pages.extend(new_pages)
            kinds = {p.suffix.lstrip(".") for p in new_pages}
            kind_str = "/".join(sorted(kinds)) or "pdf"
            rot_str = f", rotated {rotated} back page(s)" if rotated else ""
            print(f"ok — added {len(new_pages)} page(s) [{kind_str}], {total_kb} KB{rot_str}")

        if append_target is not None and new_count() == 0:
            print("no new pages scanned; target file left untouched.")
            return 0
        if append_target is None and not pages:
            print("no pages scanned; nothing saved.")
            return 0

        if append_target is None and final.exists():
            ts = datetime.now().strftime("%H%M%S")
            final = final.with_name(f"{final.stem}-{ts}.pdf")
            print(f"  existing file kept; saving as {final.name}")

        # Write to a sibling temp file, then atomic-rename. In append mode
        # this means the target is overwritten only after the merged file
        # exists and is closed; a crash mid-merge leaves the original intact.
        staging = final.parent / f".{final.stem}.scan-doc.{os.getpid()}.pdf"
        raw_merged: Path | None = None
        try:
            print("merging…", end=" ", flush=True)
            merge_pdfs(pages, staging)
            print(f"{staging.stat().st_size // 1024} KB")

            # CLI --compress wins; otherwise prompt at the tty (skip silently
            # if stdin is piped, since there's no one to answer).
            level: str | None = args.compress
            if level is None and sys.stdin.isatty():
                level = prompt_compress(staging.stat().st_size // 1024)

            if level:
                # Move merged out of the way, gs into staging.
                raw_merged = staging.with_suffix(".raw.pdf")
                os.replace(staging, raw_merged)
                raw_kb = raw_merged.stat().st_size // 1024
                print(f"  running gs /{level}…", end=" ", flush=True)
                try:
                    gs_compress(raw_merged, staging, level)
                except FileNotFoundError:
                    print("\n  WARN: gs not on PATH; keeping uncompressed merge")
                    os.replace(raw_merged, staging)
                    raw_merged = None
                except subprocess.CalledProcessError as e:
                    err = (e.stderr or b"").decode("utf-8", "replace").strip()
                    print(f"\n  WARN: gs failed ({e.returncode}); keeping uncompressed merge")
                    if err:
                        print(f"    {err.splitlines()[-1]}")
                    os.replace(raw_merged, staging)
                    raw_merged = None
                else:
                    new_kb = staging.stat().st_size // 1024
                    ratio = raw_kb / new_kb if new_kb else 0
                    print(f"{new_kb} KB ({ratio:.1f}× smaller)")
                    raw_merged.unlink()
                    raw_merged = None

            os.replace(staging, final)
        except Exception as e:
            for tmp_path in (staging, raw_merged):
                if tmp_path and tmp_path.exists():
                    try:
                        tmp_path.unlink()
                    except OSError:
                        pass
            recovery = Path.home() / ".cache" / "scan-doc-failed" / (
                datetime.now().strftime("%Y%m%d-%H%M%S")
            )
            recovery.mkdir(parents=True, exist_ok=True)
            for p in pages:
                shutil.copy2(p, recovery / p.name)
            print(f"\nMERGE FAILED: {e}")
            print(f"raw pages preserved in: {recovery}")
            if append_target is not None:
                print(f"original target left intact: {append_target}")
            keep_tmp = True
            return 1

        total_kb = final.stat().st_size // 1024
        if append_target is not None:
            print(
                f"saved {final}  ({orig_page_count} existing + {new_count()} "
                f"new = {orig_page_count + new_count()} page(s), {total_kb} KB)"
            )
        else:
            print(f"saved {final}  ({len(pages)} page(s), {total_kb} KB)")
        return 0
    finally:
        if not keep_tmp:
            shutil.rmtree(tmp, ignore_errors=True)
        else:
            print(f"temp dir retained: {tmp}")
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()


if __name__ == "__main__":
    sys.exit(main())
