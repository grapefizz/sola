#!/usr/bin/env python3
"""Serve the Love.js build with the isolation headers required by WebAssembly."""

from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


BUILD_DIRECTORY = Path(__file__).resolve().parent / "build" / "web"


class LoveJsHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        # Love.js uses WebAssembly threads, so SharedArrayBuffer is only
        # available when the page is cross-origin isolated.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        super().end_headers()


if __name__ == "__main__":
    if not BUILD_DIRECTORY.is_dir():
        raise SystemExit("build/web does not exist; compile the game first")

    server = ThreadingHTTPServer(
        ("127.0.0.1", 4173),
        lambda *args, **kwargs: LoveJsHandler(
            *args, directory=str(BUILD_DIRECTORY), **kwargs
        ),
    )
    print("Serving Sola at http://127.0.0.1:4173")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
