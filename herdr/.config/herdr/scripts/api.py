#!/usr/bin/env python3
"""Raw herdr socket-API client.

`herdr <noun> <verb>` only wraps part of the socket API — layout.export,
layout.apply and tab.move have no CLI subcommand in 0.7.5 even though the
protocol (17) speaks them. The wire format is one JSON request per line on
$HERDR_SOCKET_PATH, one JSON reply back.

    api.py layout.export '{"pane_id": "w4:p1"}'
    api.py tab.move '{"tab_id": "w4:t2", "insert_index": 0}'

Importable too: `from api import call`.
"""

from __future__ import annotations

import json
import os
import socket
import sys

SOCKET = os.environ.get("HERDR_SOCKET_PATH") or os.path.expanduser("~/.config/herdr/herdr.sock")


class HerdrApiError(RuntimeError):
    pass


def call(method: str, params: dict | None = None) -> dict:
    try:
        conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        conn.connect(SOCKET)
    except OSError as exc:
        raise HerdrApiError(f"{method}: cannot reach {SOCKET}: {exc}") from exc
    with conn:
        request = {"id": f"api:{method}", "method": method, "params": params or {}}
        conn.sendall((json.dumps(request) + "\n").encode())
        line = conn.makefile("r").readline()
    if not line:
        raise HerdrApiError(f"{method}: empty reply")
    payload = json.loads(line)
    if "error" in payload:
        err = payload["error"]
        raise HerdrApiError(f"{method}: {err.get('message', err)}")
    return payload.get("result", {})


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    params = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
    try:
        json.dump(call(sys.argv[1], params), sys.stdout)
    except HerdrApiError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
