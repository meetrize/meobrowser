#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""HTTP 反代：向 PocketBase Admin (/_/) HTML 注入登录失效自动退回脚本。"""
from __future__ import print_function

import gzip
import os
import socket
import sys

try:
    from http.server import BaseHTTPRequestHandler, HTTPServer
    from urllib.request import Request, urlopen
    from urllib.error import HTTPError, URLError
except ImportError:
    from BaseHTTPServer import BaseHTTPRequestHandler, HTTPServer
    from urllib2 import Request, urlopen, HTTPError, URLError

LISTEN_HOST = os.environ.get("MEO_PROXY_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("MEO_PROXY_PORT", "8090"))
UPSTREAM = os.environ.get("MEO_UPSTREAM", "http://127.0.0.1:18090").rstrip("/")
SCRIPT_PATH = os.environ.get(
    "MEO_AUTH_GUARD_JS",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "static", "meo-auth-guard.js"),
)
INJECT_TAG = '<script src="/meo-auth-guard.js"></script>'

HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "content-encoding",
    "content-length",
}


def load_guard_js():
    with open(SCRIPT_PATH, "rb") as f:
        return f.read()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("[meo-pb-proxy] %s - %s\n" % (self.address_string(), fmt % args))

    def do_GET(self):
        self._proxy()

    def do_POST(self):
        self._proxy()

    def do_PUT(self):
        self._proxy()

    def do_PATCH(self):
        self._proxy()

    def do_DELETE(self):
        self._proxy()

    def do_OPTIONS(self):
        self._proxy()

    def do_HEAD(self):
        self._proxy()

    def _proxy(self):
        if self.path.split("?", 1)[0] == "/meo-auth-guard.js":
            data = load_guard_js()
            self.send_response(200)
            self.send_header("Content-Type", "application/javascript; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(data)
            return

        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length > 0 else None
        url = UPSTREAM + self.path
        headers = {}
        for k, v in self.headers.items():
            if k.lower() in HOP_BY_HOP or k.lower() == "host":
                continue
            headers[k] = v
        # 避免上游压缩，便于注入
        headers["Accept-Encoding"] = "identity"

        req = Request(url, data=body, headers=headers, method=self.command)
        try:
            resp = urlopen(req, timeout=120)
            status = getattr(resp, "status", 200) or 200
            resp_headers = dict(resp.headers.items()) if hasattr(resp.headers, "items") else {}
            raw = resp.read()
        except HTTPError as e:
            status = e.code
            resp_headers = dict(e.headers.items()) if e.headers else {}
            raw = e.read() if hasattr(e, "read") else b""
        except URLError as e:
            msg = ("upstream error: %s" % e).encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)
            return
        except Exception as e:
            msg = ("proxy error: %s" % e).encode("utf-8")
            self.send_response(500)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)
            return

        ctype = ""
        for k, v in list(resp_headers.items()):
            if k.lower() == "content-type":
                ctype = v.lower()
            if k.lower() == "content-encoding" and v.lower() == "gzip":
                try:
                    raw = gzip.decompress(raw)
                except Exception:
                    try:
                        raw = gzip.GzipFile(fileobj=__import__("io").BytesIO(raw)).read()
                    except Exception:
                        pass
                resp_headers = {hk: hv for hk, hv in resp_headers.items() if hk.lower() != "content-encoding"}

        path_only = self.path.split("?", 1)[0]
        if (
            self.command in ("GET", "HEAD")
            and "text/html" in ctype
            and (path_only == "/_/" or path_only == "/_" or path_only.endswith("/_/index.html"))
        ):
            try:
                text = raw.decode("utf-8")
                if "meo-auth-guard.js" not in text:
                    if "</head>" in text:
                        text = text.replace("</head>", INJECT_TAG + "\n</head>", 1)
                    elif "</body>" in text:
                        text = text.replace("</body>", INJECT_TAG + "\n</body>", 1)
                    else:
                        text = text + "\n" + INJECT_TAG
                raw = text.encode("utf-8")
            except Exception:
                pass

        self.send_response(status)
        for k, v in resp_headers.items():
            if k.lower() in HOP_BY_HOP:
                continue
            if k.lower() == "content-length":
                continue
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(raw)


def main():
    # 允许地址重用
    HTTPServer.allow_reuse_address = True
    server = HTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    print(
        "meo-pb-proxy listening on %s:%s -> %s (guard=%s)"
        % (LISTEN_HOST, LISTEN_PORT, UPSTREAM, SCRIPT_PATH),
        flush=True,
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
