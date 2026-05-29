#!/usr/bin/env python3
"""Local mock of DeepSeek's OpenAI-compatible /chat/completions endpoint.

Used by `OptionNow --uitest` to verify the AI streaming pipeline (AC-AI-03) and
request construction (AC-AI-07) deterministically, without a real API key.

- Authorization "Bearer bad"  -> 401 (drives the invalidKey path, AC-AI-06)
- otherwise                    -> dumps the request body to /tmp/optionnow_ai_req.json
                                  and streams SSE: "Hello" / " there" / " friend" / [DONE]
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

CHUNKS = ["Hello", " there", " friend"]

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        auth = self.headers.get("Authorization", "")

        if auth.strip() == "Bearer bad":
            self.send_response(401)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"error":{"message":"invalid api key"}}')
            return

        try:
            with open("/tmp/optionnow_ai_req.json", "wb") as f:
                f.write(body)
        except Exception:
            pass

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for c in CHUNKS:
            payload = {"choices": [{"delta": {"content": c}}]}
            self.wfile.write(f"data: {json.dumps(payload)}\n\n".encode())
            self.wfile.flush()
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()

if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
