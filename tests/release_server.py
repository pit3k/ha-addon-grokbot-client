#!/usr/bin/env python3
"""Serve a fake grokbot-tunnel release directory for updater tests."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(BaseHTTPRequestHandler):
    root = Path(".")

    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/releases/latest":
            self.send_response(302)
            self.send_header("Location", "/releases/tag/v9.9.9")
            self.end_headers()
            return
        if path == "/releases/tag/v9.9.9":
            body = b"v9.9.9"
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        marker = "/releases/download/v9.9.9/"
        if not path.startswith(marker):
            self.send_error(404)
            return
        name = path[len(marker):]
        if "/" in name or name.startswith("."):
            self.send_error(404)
            return
        file = self.root / name
        if not file.is_file():
            self.send_error(404)
            return
        data = file.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--port", type=int, default=0)
    args = parser.parse_args()
    Handler.root = Path(args.root)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(server.server_address[1], flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
