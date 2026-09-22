#!/usr/bin/env python3
"""A stand-in for LM Studio while the promo video renders: an OpenAI-style server
on one port that answers with scripted lines, so the video needs no real model.

    python3 scripts/promo-brain.py 17777
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LINES = [
    "Watch it, you *bouncing* blob! That was my corner.",
    "Says the square who can't see past his own edges. *sigh*",
    "Fine. Have a flower. Try not to lose it this time.",
    "Oh! It's... it's *beautiful*. I'm never leaving your side.",
    "That is exactly what I was afraid of.",
    "Too late. *follows*",
]


class Brain(BaseHTTPRequestHandler):
    calls = 0

    def log_message(self, *_):
        pass

    def _send(self, body):
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._send({"data": [{"id": "promo"}]})

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        line = LINES[Brain.calls % len(LINES)]
        Brain.calls += 1
        self._send({"choices": [{"message": {"role": "assistant", "content": line}}],
                    "usage": {"prompt_tokens": 120, "completion_tokens": 14}})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 17777
    HTTPServer(("127.0.0.1", port), Brain).serve_forever()
