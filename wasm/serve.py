#!/usr/bin/env python3
"""
Simple HTTP server that adds the COOP/COEP headers required for
SharedArrayBuffer (needed by Emscripten pthreads).

Usage:
    python3 serve.py [port]        (default port: 8080)
"""
import sys
from http.server import SimpleHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080

class CoopCoepHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy",   "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

    def log_message(self, fmt, *args):
        pass  # suppress per-request noise

print(f"Serving on http://localhost:{PORT}/test.html")
print("(SharedArrayBuffer headers enabled for Emscripten pthreads)")
HTTPServer(("", PORT), CoopCoepHandler).serve_forever()
