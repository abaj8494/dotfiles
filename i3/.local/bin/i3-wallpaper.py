#!/usr/bin/env python3
"""Per-i3-workspace wallpaper using the default Kali backgrounds.

Each workspace (by number) gets a wallpaper, updated on focus. A workspace can
be given a persistent OVERRIDE (see wallpaper-rotate) stored at
~/.cache/i3-wallpaper/ws-<num>; the override wins over the default mapping, so
rotating one workspace's wallpaper never affects the others.
"""
import glob
import json
import os
import subprocess
import time

BG_DIR = "/usr/share/backgrounds/kali-16x9"
STATE_DIR = os.path.expanduser("~/.cache/i3-wallpaper")

images = sorted(
    p for p in glob.glob(os.path.join(BG_DIR, "*"))
    if os.path.isfile(p) and p.lower().endswith((".jpg", ".jpeg", ".png"))
)


def override_for(num):
    try:
        p = open(os.path.join(STATE_DIR, f"ws-{num}")).read().strip()
        return p if p and os.path.isfile(p) else None
    except OSError:
        return None


def wallpaper_for(num):
    o = override_for(num)
    if o:
        return o
    if not images:
        return None
    return images[(int(num) - 1) % len(images)]


def set_wallpaper(num):
    path = wallpaper_for(num)
    if path:
        subprocess.run(["feh", "--no-fehbg", "--bg-fill", path], check=False)


def focused_num():
    out = subprocess.check_output(["i3-msg", "-t", "get_workspaces"])
    for ws in json.loads(out):
        if ws.get("focused"):
            return ws["num"]
    return 1


def main():
    while True:
        try:
            set_wallpaper(focused_num())
        except Exception:
            pass
        try:
            proc = subprocess.Popen(
                ["i3-msg", "-t", "subscribe", "-m", '["workspace"]'],
                stdout=subprocess.PIPE, text=True,
            )
            for line in proc.stdout:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if event.get("change") in ("focus", "init") and event.get("current"):
                    num = event["current"].get("num")
                    if num is not None and num >= 0:
                        set_wallpaper(num)
        except Exception:
            pass
        time.sleep(1)


if __name__ == "__main__":
    main()
