#!/usr/bin/env python3
"""Tiny curl-able build server for driving Bazel on the host machine.

Motivation: the container builds on Linux, but some things (e.g. the Verilator
cc_toolchain) must also work on macOS. Running this on the host lets an agent in
the container trigger host builds/tests and read the logs to fix host-only
breakage.

Run it from anywhere inside the repo (it finds the repo root by walking up to
MODULE.bazel / WORKSPACE):

    python3 tools/build_server.py            # listens on 0.0.0.0:8099
    python3 tools/build_server.py --port 9000

Then, from the container (replace HOST with the Mac's LAN IP):

    # Fire-and-poll: returns a run id immediately.
    curl -sS HOST:8099/run -d 'build //...'
    curl -sS HOST:8099/log/1                 # log so far (+ status/exit trailer)

    # Or block until done and stream back the whole log as text:
    curl -sS 'HOST:8099/run?wait=1' -d 'test //examples/led_cycle:led_cycle_sim.test'

    curl -sS HOST:8099/runs                  # JSON list of runs
    curl -sS HOST:8099/log                    # latest run's log

Only the `bazel` binary (env BAZEL to override, e.g. bazelisk) is executed; the
POST body is shlex-split into its arguments. This is a local dev tool -- don't
expose it to untrusted networks.
"""

import argparse
import json
import os
import shlex
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

BAZEL = os.environ.get("BAZEL", "bazel")


def find_repo_root(start):
    d = os.path.abspath(start)
    while True:
        if any(os.path.exists(os.path.join(d, m)) for m in ("MODULE.bazel", "WORKSPACE", "WORKSPACE.bazel")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return os.path.abspath(start)  # fallback: no marker found
        d = parent


REPO = find_repo_root(os.path.dirname(__file__))
LOGDIR = os.path.join(REPO, ".build_server_logs")
os.makedirs(LOGDIR, exist_ok=True)

_lock = threading.Lock()  # guards `runs` + `counter`
_run_lock = threading.Lock()  # serializes actual bazel invocations
runs = {}
counter = [0]


def _logpath(rid):
    return os.path.join(LOGDIR, "%d.log" % rid)


def _run_job(rid, args):
    with _run_lock, open(_logpath(rid), "w") as f:
        f.write("$ %s %s\n\n" % (BAZEL, " ".join(shlex.quote(a) for a in args)))
        f.flush()
        rc = 127
        try:
            p = subprocess.Popen([BAZEL] + args, cwd=REPO, stdout=f, stderr=subprocess.STDOUT)
            with _lock:
                runs[rid]["pid"] = p.pid
            rc = p.wait()
        except Exception as e:  # noqa: BLE001 - report any launch failure to the client
            f.write("\n[build-server error] %s\n" % e)
        f.write("\n--- exit %d ---\n" % rc)
    with _lock:
        runs[rid]["status"] = "done"
        runs[rid]["exit"] = rc
        runs[rid]["finished"] = time.strftime("%H:%M:%S")


def _latest_id():
    with _lock:
        return counter[0] if counter[0] else None


def _read_log(rid):
    try:
        with open(_logpath(rid)) as f:
            body = f.read()
    except OSError:
        return None
    with _lock:
        info = runs.get(rid, {})
    status = info.get("status", "unknown")
    if status != "done":
        body += "\n--- status: %s ---\n" % status
    return body


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/plain; charset=utf-8"):
        b = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/health"):
            self._send(200, "ok: build server for %s\n" % REPO)
            return
        if path == "/runs":
            with _lock:
                self._send(200, json.dumps(runs, default=str, indent=2) + "\n", "application/json")
            return
        if path == "/log" or path.startswith("/log/"):
            rid = _latest_id() if path == "/log" else int(path.rsplit("/", 1)[1] or 0)
            if not rid:
                self._send(404, "no runs yet\n")
                return
            body = _read_log(rid)
            self._send(200 if body is not None else 404, body or "no such run\n")
            return
        self._send(404, "not found\n")

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/run":
            self._send(404, "not found\n")
            return
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode().strip()
        try:
            args = shlex.split(body)
        except ValueError as e:
            self._send(400, "bad args: %s\n" % e)
            return
        if not args:
            self._send(400, "empty command (POST bazel args as the body)\n")
            return
        with _lock:
            counter[0] += 1
            rid = counter[0]
            runs[rid] = {"status": "running", "exit": None, "cmd": body, "started": time.strftime("%H:%M:%S")}
        threading.Thread(target=_run_job, args=(rid, args), daemon=True).start()

        if parse_qs(parsed.query).get("wait", ["0"])[0] in ("1", "true"):
            while True:
                with _lock:
                    done = runs[rid]["status"] == "done"
                if done:
                    break
                time.sleep(0.5)
            self._send(200, _read_log(rid))
        else:
            self._send(200, json.dumps({"id": rid, "log": "/log/%d" % rid}) + "\n", "application/json")

    def log_message(self, *a):  # quiet; runs are logged to files
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8099")))
    ap.add_argument("--host", default="0.0.0.0")
    args = ap.parse_args()
    srv = ThreadingHTTPServer((args.host, args.port), Handler)
    print("build server on %s:%d  repo=%s  bazel=%s" % (args.host, args.port, REPO, BAZEL))
    print("logs -> %s" % LOGDIR)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
