#!/usr/bin/env python3
"""Tiny HTTP server for tests/ci-vm.sh: serves a directory (GET) and stores uploads (PUT).

The VM uploads its install log and the vm-check result here; the host script waits for them.
    ci-server.py DIR PORT
"""
import http.server
import os
import sys

root, port = sys.argv[1], int(sys.argv[2])


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=root, **kw)

    def do_PUT(self):
        name = os.path.basename(self.path.split("?")[0]) or "upload"
        length = int(self.headers.get("Content-Length", 0))
        data = self.rfile.read(length) if length else b""
        os.makedirs(os.path.join(root, "up"), exist_ok=True)
        tmp = os.path.join(root, "up", "." + name)
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, os.path.join(root, "up", name))  # appears complete or not at all
        self.send_response(201)
        self.end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("http: " + fmt % args + "\n")


http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
