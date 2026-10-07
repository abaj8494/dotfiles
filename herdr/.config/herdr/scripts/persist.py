#!/usr/bin/env python3
"""herdr-resurrect + herdr-continuum.

What herdr already does by itself:
  * the server outlives the client, so detaching loses nothing (tmux parity);
  * ~/.config/herdr/session.json rebuilds workspaces/tabs/panes across a server
    restart or reboot (the Homebrew launchd agent restarts the server) — but
    each pane in that file carries only a cwd, so **programs do not come back**;
  * [session] resume_agents_on_restore puts officially-integrated agent panes
    back into their conversations.

What this adds — the tmux-resurrect half:
  * snapshots you take (and roll back to) on demand, independent of the
    server's own state file, so `herdr server stop` or a corrupt session.json
    is survivable;
  * relaunching the *programs* each pane was running (@resurrect-processes);
  * `nvim -S` when the pane's cwd has a Session.vim (@resurrect-strategy-nvim);
  * agent panes restored as a typed-but-not-executed resume command, so a
    restore never silently spawns a fleet of agents. For claude the exact
    conversation is pinned (`claude --resume <id>`): the id comes from the
    command line if it was started with --resume, otherwise from matching the
    process start time against ~/.claude/session-env/<id> (created at session
    start) and preferring the id whose transcript lives under the pane's cwd.
    `claude --continue` alone is wrong whenever two agents share a directory.
  * `restore --into-live` for the reboot path: herdr's own session.json has
    already rebuilt the workspaces (bare shells), so instead of skipping them
    as "already open" it matches saved workspaces to live ones by label, tabs
    by order, panes by tree order, and types each program into its pane —
    leaving alone any pane that is no longer a bare shell (e.g. an agent that
    [session] resume_agents_on_restore already brought back).
  * named sessions: every `herdr --session NAME` server has its own socket
    (~/.config/herdr/sessions/NAME/herdr.sock) and its own workspaces, so
    `--session NAME` targets one and `save --all-sessions` walks them all
    (default server first). Session snapshots are suffixed `@NAME`.

The continuum half is com.aayushbajaj.herdr-snapshot.plist, which runs
`persist.py save --auto` every 60s (@continuum-save-interval '1'). Auto-restore
is deliberately absent, exactly like @continuum-restore 'off' in tmux.conf.

    persist.py [--session NAME] save [--auto] [--all-sessions] [--name NAME]
    persist.py [--session NAME] restore [--name NAME] [--dry-run] [--force|--into-live]
    persist.py list
    persist.py [--session NAME] show [--name NAME]

Layout fidelity comes from the socket API's layout.export / layout.apply pair
(protocol 17), which round-trips the whole split tree — nesting, directions and
ratios — in one call. Those two methods have no `herdr` CLI subcommand, so this
speaks the line-delimited JSON protocol on $HERDR_SOCKET_PATH directly.

Programs are *typed into the pane's shell* rather than passed as layout.apply's
`command`, for two reasons: the server spawns commands with a bare
PATH=/usr/bin:/bin:/usr/sbin:/sbin (so `lf`, `lazygit`, `nvim` from Homebrew
aren't even findable), and a shell-backed pane survives quitting the program,
the way a resurrected tmux pane does.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import api  # noqa: E402  (sibling module: raw socket client)

HOME = os.path.expanduser("~")
HERDR = os.environ.get("HERDR_BIN_PATH") or "/opt/homebrew/bin/herdr"
SNAP_DIR = os.path.join(HOME, ".config", "herdr", "snapshots")
KEEP_AUTO = 10          # rolling autosave history; auto.json is newest
SESSIONS_DIR = os.path.join(HOME, ".config", "herdr", "sessions")
DEFAULT_SOCKET = os.path.join(HOME, ".config", "herdr", "herdr.sock")
CLAUDE_SESSION_ENV = os.path.join(HOME, ".claude", "session-env")
CLAUDE_PROJECTS = os.path.join(HOME, ".claude", "projects")

# Programs worth bringing back, keyed on argv0 — tmux-resurrect's default list
# plus what actually gets used here. Extend without editing this file by
# listing one name per line in ~/.config/herdr/resurrect-processes; a leading
# "-" removes an entry.
DEFAULT_PROCESSES = {
    "nvim", "vim", "vi", "emacs", "emacsclient",
    "lf", "lazygit", "gitui", "tig",
    "htop", "btop", "top", "glances", "macmon", "mactop", "bpytop",
    "less", "man", "tail", "watch",
    "ssh", "mosh", "ncdu", "ranger", "yazi",
    "irb", "python", "python3", "ipython", "node", "R", "julia",
    "ollama", "mutt", "neomutt", "aerc", "weechat", "irssi",
    "make", "npm", "pnpm", "yarn", "bun", "cargo", "grc", "fava",
}

# Agent CLIs: restored typed-but-not-run. See restore_pane().
AGENT_PROCESSES = {
    "claude", "codex", "opencode", "gemini", "cursor", "droid", "amp",
    "copilot", "kimi", "kilo", "hermes", "qoder", "qodercli", "pi", "omp",
    "aider", "goose",
}

# Agents that can pick a previous conversation back up.
AGENT_RESUME = {
    "claude": "claude --continue",
    "codex": "codex resume --last",
    "opencode": "opencode --continue",
}


class HerdrError(RuntimeError):
    pass


# --------------------------------------------------------------------- api --

def cli(*args: str) -> dict:
    """`herdr <noun> <verb>` -> parsed .result."""
    proc = subprocess.run([HERDR, *args], capture_output=True, text=True)
    if proc.returncode != 0:
        raise HerdrError(f"herdr {' '.join(args)}: {proc.stderr.strip() or proc.stdout.strip()}")
    out = proc.stdout.strip()
    if not out:
        return {}
    try:
        payload = json.loads(out)
    except json.JSONDecodeError as exc:
        raise HerdrError(f"herdr {' '.join(args)}: non-JSON reply: {out[:200]}") from exc
    if "error" in payload:
        raise HerdrError(f"herdr {' '.join(args)}: {payload['error']}")
    return payload.get("result", {})


def sock(method: str, params: dict) -> dict:
    """Raw socket call, for the methods the CLI doesn't expose (layout.*)."""
    try:
        return api.call(method, params)
    except api.HerdrApiError as exc:
        raise HerdrError(str(exc)) from exc


def server_running() -> bool:
    # Ask over the socket that use_session() selected: `herdr status server`
    # is not proven to honour HERDR_SOCKET_PATH, `herdr workspace list` is.
    try:
        cli("workspace", "list")
    except HerdrError:
        return False
    return True


CURRENT_SESSION = [""]      # set by use_session(); "" is the default server


def session_socket(name: str) -> str:
    return os.path.join(SESSIONS_DIR, name, "herdr.sock") if name else DEFAULT_SOCKET


def use_session(name: str) -> None:
    """Point both the `herdr` CLI and the raw socket client at one server."""
    path = session_socket(name)
    os.environ["HERDR_SOCKET_PATH"] = path
    api.SOCKET = path
    CURRENT_SESSION[0] = name


def live_sessions() -> list:
    """Names of sessions whose server answers; "" is the default server."""
    names = [""]
    try:
        names += sorted(d for d in os.listdir(SESSIONS_DIR)
                        if os.path.exists(os.path.join(SESSIONS_DIR, d, "herdr.sock")))
    except FileNotFoundError:
        pass
    alive = []
    for name in names:
        use_session(name)
        if server_running():
            alive.append(name)
    return alive


def snap_name(base: str, session: str) -> str:
    return f"{base}@{session}" if session and "@" not in base else base


def wait_for_prompt(pane_id: str, tries: int = 25) -> None:
    """`pane run` is send-keys: type before the shell reads the pty and the
    keystrokes are lost. A rendered prompt proves it's listening.

    `pane wait-output` does this properly — note the pane id is a leading
    positional, `--pane <id>` is rejected — with a polling fallback.
    """
    waited = subprocess.run(
        [HERDR, "pane", "wait-output", pane_id, "--match", "❯", "--timeout", "5000"],
        capture_output=True, text=True)
    if waited.returncode == 0:
        return

    for _ in range(tries):
        # `pane read` prints screen text, not JSON, so it bypasses cli().
        proc = subprocess.run([HERDR, "pane", "read", pane_id], capture_output=True, text=True)
        if proc.returncode == 0 and proc.stdout.strip():
            return
        time.sleep(0.2)


def load_process_list() -> set:
    procs = set(DEFAULT_PROCESSES)
    try:
        with open(os.path.join(HOME, ".config", "herdr", "resurrect-processes")) as fh:
            for line in fh:
                name = line.strip()
                if not name or name.startswith("#"):
                    continue
                procs.discard(name[1:]) if name.startswith("-") else procs.add(name)
    except FileNotFoundError:
        pass
    return procs


# -------------------------------------------------------------------- save --

def pane_command(pane_id: str):
    """(argv0, command line, process record) of a pane's foreground process."""
    try:
        info = cli("pane", "process-info", "--pane", pane_id)
    except HerdrError:
        return "", "", {}
    procs = info.get("process_info", {}).get("foreground_processes") or []
    if not procs:
        return "", "", {}
    proc = procs[-1]                     # deepest process wins (nvim under a wrapper)
    argv = proc.get("argv") or []
    if not argv:
        return "", "", {}
    argv0 = os.path.basename(argv[0]).lstrip("-")
    return argv0, proc.get("cmdline") or " ".join(shlex.quote(a) for a in argv), proc


def process_start_time(pid: int):
    env = dict(os.environ, LC_ALL="C")   # pin lstart's format regardless of locale
    out = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)],
                         capture_output=True, text=True, env=env).stdout.strip()
    try:
        return time.mktime(time.strptime(out, "%a %b %d %H:%M:%S %Y"))
    except ValueError:
        return None


def claude_session_id(proc: dict, cwd: str):
    """The conversation id a running claude belongs to, or None."""
    argv = proc.get("argv") or []
    for flag in ("--resume", "-r"):
        if flag in argv:
            i = argv.index(flag)
            if i + 1 < len(argv) and not argv[i + 1].startswith("-"):
                return argv[i + 1]
    start = process_start_time(proc.get("pid") or 0) if proc.get("pid") else None
    if start is None:
        return None
    born = {}
    try:
        for sid in os.listdir(CLAUDE_SESSION_ENV):
            try:
                born[sid] = os.stat(os.path.join(CLAUDE_SESSION_ENV, sid)).st_birthtime
            except OSError:
                continue
    except OSError:
        return None
    cands = [sid for sid, b in born.items() if abs(b - start) <= 300]
    if not cands:
        return None
    slug = (cwd or "").replace("/", "-")

    def transcript_mtime(sid: str) -> float:
        try:
            return os.path.getmtime(os.path.join(CLAUDE_PROJECTS, slug, sid + ".jsonl"))
        except OSError:
            return -1.0

    cands.sort(key=lambda sid: (transcript_mtime(sid), -abs(born[sid] - start)))
    best = cands[-1]
    if transcript_mtime(best) < 0 and len(cands) > 1:
        return None                      # several sessions started together, none in this cwd
    return best


def claude_resume_command(proc: dict, session_id: str) -> str:
    """Original flags, minus any resume/continue, plus --resume <id>."""
    argv = proc.get("argv") or ["claude"]
    keep, skip = [], False
    for arg in argv[1:]:
        if skip:
            skip = False
            continue
        if arg in ("--resume", "-r"):
            skip = True
            continue
        if arg in ("--continue", "-c"):
            continue
        keep.append(arg)
    return " ".join(shlex.quote(a) for a in ["claude", *keep, "--resume", session_id])


def walk_tree(node: dict):
    """Yield every pane node in a layout tree, in creation order."""
    if node.get("type") == "pane":
        yield node
    elif node.get("type") == "split":
        yield from walk_tree(node.get("first", {}))
        yield from walk_tree(node.get("second", {}))


def strip_ids(node: dict) -> dict:
    """A tree for layout.apply: keep shape/cwd, drop ids from the dead server."""
    if node.get("type") == "pane":
        out = {"type": "pane"}
        if node.get("cwd"):
            out["cwd"] = node["cwd"]
        return out
    return {
        "type": "split",
        "direction": node.get("direction", "right"),
        "ratio": node.get("ratio", 0.5),
        "first": strip_ids(node.get("first", {})),
        "second": strip_ids(node.get("second", {})),
    }


def snapshot() -> dict:
    workspaces = cli("workspace", "list").get("workspaces", [])
    tabs = cli("tab", "list").get("tabs", [])
    panes = cli("pane", "list").get("panes", [])

    panes_by_tab: dict = {}
    for pane in panes:
        panes_by_tab.setdefault(pane["tab_id"], []).append(pane)

    out_workspaces = []
    for ws in workspaces:
        out_tabs = []
        for tab in [t for t in tabs if t["workspace_id"] == ws["workspace_id"]]:
            tab_panes = panes_by_tab.get(tab["tab_id"], [])
            if not tab_panes:
                continue
            try:
                layout = sock("layout.export", {"pane_id": tab_panes[0]["pane_id"]}).get("layout", {})
            except HerdrError:
                layout = {}
            root = layout.get("root")
            if not root:
                continue
            programs = {}
            for node in walk_tree(root):
                pid = node.get("pane_id")
                if not pid:
                    continue
                argv0, cmdline, proc = pane_command(pid)
                if argv0:
                    programs[pid] = {"argv0": argv0, "cmdline": cmdline, "cwd": node.get("cwd")}
                    if argv0 == "claude":
                        cwd = proc.get("cwd") or node.get("cwd") or ""
                        sid = claude_session_id(proc, cwd)
                        if sid:
                            programs[pid]["resume"] = claude_resume_command(proc, sid)
            out_tabs.append({
                "label": tab.get("label", ""),
                "focused": tab.get("focused", False),
                "root": root,
                "programs": programs,
            })
        if out_tabs:
            out_workspaces.append({
                "label": ws.get("label", ""),
                "focused": ws.get("focused", False),
                "tabs": out_tabs,
            })

    return {
        "version": 2,
        "saved_at": int(time.time()),
        "saved_at_iso": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "session": os.environ.get("HERDR_SOCKET_PATH", "") and CURRENT_SESSION[0],
        "workspaces": out_workspaces,
    }


def cmd_save(args) -> int:
    if args.all_sessions:
        sessions = live_sessions()
        if not sessions:
            print("no herdr server is running; nothing to save", file=sys.stderr)
            return 0 if args.auto else 1
        rc = 0
        for name in sessions:
            use_session(name)
            rc |= save_one(args, name)
        return rc
    return save_one(args, args.session)


def save_one(args, session: str) -> int:
    if not server_running():
        print("herdr server is not running; nothing to save", file=sys.stderr)
        return 0 if args.auto else 1

    os.makedirs(SNAP_DIR, exist_ok=True)
    snap = snapshot()
    if not snap["workspaces"]:
        print("no workspaces; refusing to write an empty snapshot", file=sys.stderr)
        return 0 if args.auto else 1

    name = snap_name(args.name or ("auto" if args.auto else "last"), session)
    path = os.path.join(SNAP_DIR, f"{name}.json")

    if args.auto:
        # Rotate, continuum-style, so one bad state can't wipe every good one.
        for i in range(KEEP_AUTO - 1, 0, -1):
            src = os.path.join(SNAP_DIR, f"{name}-{i}.json")
            if os.path.exists(src):
                os.replace(src, os.path.join(SNAP_DIR, f"{name}-{i + 1}.json"))
        if os.path.exists(path):
            os.replace(path, os.path.join(SNAP_DIR, f"{name}-1.json"))
        stale = os.path.join(SNAP_DIR, f"{name}-{KEEP_AUTO + 1}.json")
        if os.path.exists(stale):
            os.remove(stale)

    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(snap, fh, indent=1)
    os.replace(tmp, path)

    panes = sum(len(list(walk_tree(t["root"]))) for w in snap["workspaces"] for t in w["tabs"])
    print(f"saved {len(snap['workspaces'])} workspaces / {panes} panes -> {path}")
    return 0


# ----------------------------------------------------------------- restore --

def restore_pane(pane_id: str, program: dict, processes: set, dry: bool) -> None:
    argv0, cmdline = program.get("argv0", ""), program.get("cmdline", "")
    if not argv0 or argv0 in ("zsh", "bash", "sh", "fish", "login"):
        return

    if argv0 in AGENT_PROCESSES:
        # Typed, not run. Restoring a workspace should never spawn agents
        # unattended — and herdr's own resume_agents_on_restore already covers
        # the server-restart path for integrated agents.
        text = program.get("resume") or AGENT_RESUME.get(argv0, cmdline)
        print(f"    {pane_id}: type (no enter) '{text}'")
        if not dry:
            wait_for_prompt(pane_id)
            cli("pane", "send-text", pane_id, text)
        return

    if argv0 not in processes:
        return

    cmd = cmdline
    cwd = program.get("cwd") or ""
    if argv0 in {"nvim", "vim"} and cwd and os.path.exists(os.path.join(cwd, "Session.vim")):
        cmd = f"{argv0} -S"              # @resurrect-strategy-nvim 'session'
    print(f"    {pane_id}: run '{cmd}'")
    if not dry:
        wait_for_prompt(pane_id)
        cli("pane", "run", pane_id, cmd)


def cmd_restore(args) -> int:
    if not server_running():
        print("herdr server is not running", file=sys.stderr)
        return 1

    path = os.path.join(SNAP_DIR, f"{snap_name(args.name, args.session)}.json")
    try:
        with open(path) as fh:
            snap = json.load(fh)
    except FileNotFoundError:
        print(f"no snapshot at {path} (try `persist.py list`)", file=sys.stderr)
        return 1
    if snap.get("version") != 2:
        print(f"{path}: unsupported snapshot version {snap.get('version')}", file=sys.stderr)
        return 1

    processes = load_process_list()
    dry = args.dry_run
    if args.into_live:
        print(f"restoring programs from {path} ({snap.get('saved_at_iso', '?')}) into live panes")
        return restore_into_live(snap, processes, dry)
    live = {w.get("label") for w in cli("workspace", "list").get("workspaces", [])}

    print(f"restoring {path} ({snap.get('saved_at_iso', '?')})")
    for ws in snap["workspaces"]:
        label = ws["label"]
        if label in live and not args.force:
            print(f"  = {label} (already open, skipping)")
            continue

        first_panes = list(walk_tree(ws["tabs"][0]["root"]))
        root_cwd = (first_panes[0].get("cwd") if first_panes else None) or HOME
        if not os.path.isdir(root_cwd):
            root_cwd = HOME

        print(f"  + {label}  ({len(ws['tabs'])} tabs)")
        if dry:
            for tab in ws["tabs"]:
                names = ", ".join(p.get("cwd", "?") for p in walk_tree(tab["root"]))
                print(f"    tab '{tab['label']}': {names}")
                for saved_id, program in tab["programs"].items():
                    restore_pane(saved_id, program, processes, dry)
            continue

        created = cli("workspace", "create", "--cwd", root_cwd, "--label", label, "--no-focus")
        ws_id = created["workspace"]["workspace_id"]

        for index, tab in enumerate(ws["tabs"]):
            tree = strip_ids(tab["root"])
            if index == 0:
                # layout.apply on an existing tab replaces it in place.
                applied = sock("layout.apply", {"tab_id": created["tab"]["tab_id"], "root": tree})
                new_tab_id = applied["layout"]["tab_id"]
                if tab.get("label"):
                    cli("tab", "rename", new_tab_id, tab["label"])
            else:
                applied = sock("layout.apply",
                               {"workspace_id": ws_id, "tab_label": tab.get("label") or "", "root": tree})

            # Both trees have identical shape, so zipping them maps saved pane
            # ids onto the ones that were just created.
            pane_map = {old.get("pane_id"): new.get("pane_id")
                        for old, new in zip(walk_tree(tab["root"]), walk_tree(applied["layout"]["root"]))}

            for saved_id, program in tab["programs"].items():
                new_id = pane_map.get(saved_id)
                if new_id:
                    restore_pane(new_id, program, processes, dry)

    return 0


SHELLS = {"", "zsh", "bash", "sh", "fish", "login"}


def restore_into_live(snap: dict, processes: set, dry: bool) -> int:
    """Type saved programs into panes that herdr has already rebuilt."""
    live_ws = cli("workspace", "list").get("workspaces", [])
    live_tabs = cli("tab", "list").get("tabs", [])
    live_panes = cli("pane", "list").get("panes", [])
    by_label: dict = {}
    for ws in live_ws:
        by_label.setdefault(ws.get("label"), []).append(ws)

    used, rc = set(), 0
    for ws in snap["workspaces"]:
        label = ws["label"]
        cands = [w for w in by_label.get(label, []) if w["workspace_id"] not in used]
        if not cands:
            print(f"  - {label}: not open (plain restore creates it)")
            rc = 1
            continue
        live = cands[0]
        used.add(live["workspace_id"])
        tabs = sorted((t for t in live_tabs if t["workspace_id"] == live["workspace_id"]),
                      key=lambda t: t.get("number", 0))
        print(f"  = {label}  ({len(ws['tabs'])} saved tabs, {len(tabs)} live)")
        for saved_tab, live_tab in zip(ws["tabs"], tabs):
            panes = [p for p in live_panes if p["tab_id"] == live_tab["tab_id"]]
            if not panes:
                continue
            try:
                root = sock("layout.export", {"pane_id": panes[0]["pane_id"]})["layout"]["root"]
                live_order = [n.get("pane_id") for n in walk_tree(root)]
            except (HerdrError, KeyError):
                live_order = [p["pane_id"] for p in panes]
            saved_order = [n.get("pane_id") for n in walk_tree(saved_tab["root"])]
            pane_map = dict(zip(saved_order, live_order))
            for saved_id, program in saved_tab["programs"].items():
                new_id = pane_map.get(saved_id)
                if not new_id:
                    continue
                argv0, _, _ = pane_command(new_id)
                if argv0 not in SHELLS:
                    print(f"    {new_id}: busy ({argv0}), leaving alone")
                    continue
                restore_pane(new_id, program, processes, dry)
    return rc


# -------------------------------------------------------------------- misc --

def cmd_list(_args) -> int:
    try:
        names = sorted(f for f in os.listdir(SNAP_DIR) if f.endswith(".json"))
    except FileNotFoundError:
        print("no snapshots yet")
        return 0
    for name in names:
        try:
            with open(os.path.join(SNAP_DIR, name)) as fh:
                snap = json.load(fh)
        except (json.JSONDecodeError, OSError):
            print(f"{name[:-5]:<12} (unreadable)")
            continue
        panes = sum(len(list(walk_tree(t["root"]))) for w in snap["workspaces"] for t in w["tabs"])
        labels = ", ".join(w["label"] for w in snap["workspaces"])
        print(f"{name[:-5]:<12} {snap.get('saved_at_iso', '?'):<26} "
              f"{len(snap['workspaces'])}w/{panes}p  {labels}")
    return 0


def cmd_show(args) -> int:
    with open(os.path.join(SNAP_DIR, f"{snap_name(args.name, args.session)}.json")) as fh:
        json.dump(json.load(fh), sys.stdout, indent=2)
    print()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="herdr resurrect/continuum")
    parser.add_argument("--session", default="",
                        help="named `herdr --session NAME` server (default: the default server)")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_save = sub.add_parser("save")
    p_save.add_argument("--auto", action="store_true", help="rotating autosave (launchd)")
    p_save.add_argument("--all-sessions", action="store_true",
                        help="snapshot every live server, one file per session")
    p_save.add_argument("--name")
    p_save.set_defaults(func=cmd_save)

    p_restore = sub.add_parser("restore")
    p_restore.add_argument("--name", default="auto")
    p_restore.add_argument("--dry-run", action="store_true")
    p_restore.add_argument("--force", action="store_true",
                           help="recreate workspaces even if one with that label is open")
    p_restore.add_argument("--into-live", action="store_true",
                           help="type programs into already-open workspaces (post-reboot)")
    p_restore.set_defaults(func=cmd_restore)

    sub.add_parser("list").set_defaults(func=cmd_list)

    p_show = sub.add_parser("show")
    p_show.add_argument("--name", default="auto")
    p_show.set_defaults(func=cmd_show)

    args = parser.parse_args()
    use_session(args.session)
    try:
        return args.func(args)
    except HerdrError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
