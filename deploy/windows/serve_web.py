"""Windows 本机网页服务：与 deploy/macmini/Caddyfile 相同的职责，只用 Python 标准库。

- 监听 127.0.0.1:8080（SakuraFrp TCP 隧道 + 自动 HTTPS 把公网 https/wss 解密后转到这里）；
- /ws 开头的请求原样转给本机联机中继的 WebSocket 端口（默认 24681），双向透传；
- /update/ 开头的请求由 --update-root 目录提供（桌面版云更新，见 build-tools/publish_update.py），
  与网页站点分开存放，网页重新发布（robocopy /MIR）不会删掉更新文件；
- 其他请求按网页根目录提供静态文件：浏览器接受 br/gzip 时优先发 prepare_web.py 预压缩的 .br/.gz，
  .wasm 带 application/wasm 类型；Cache-Control: no-cache + ETag，版本更新后浏览器能拿到新文件，
  未变化的文件只回 304。本机缓存由网页里的 Service Worker 负责（见 web/sw.js）。

用法：python deploy/windows/serve_web.py --root D:/ConjoinedTwins-web/site [--update-root D:/ConjoinedTwins-web/update]
      [--port 8080] [--relay-port 24681]
"""
import argparse
import asyncio
import email.utils
import mimetypes
import os
from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit

TYPES = {".wasm": "application/wasm", ".js": "text/javascript", ".html": "text/html; charset=utf-8",
         ".json": "application/json", ".pck": "application/octet-stream", ".jpg": "image/jpeg", ".png": "image/png"}
CHUNK = 1 << 20


def log(text):
    print(f"[{email.utils.formatdate(localtime=True)}] {text}", flush=True)


async def read_head(reader):
    try:
        head = await reader.readuntil(b"\r\n\r\n")
    except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, ConnectionError):
        return None
    lines = head.decode("latin-1").split("\r\n")
    parts = lines[0].split(" ")
    if len(parts) != 3:
        return None
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            key, value = line.split(":", 1)
            headers[key.strip().lower()] = value.strip()
    return {"raw": head, "method": parts[0], "target": parts[1], "version": parts[2], "headers": headers}


async def pipe(reader, writer):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (ConnectionError, OSError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def proxy_websocket(request, reader, writer, relay_port):
    try:
        upstream_reader, upstream_writer = await asyncio.open_connection("127.0.0.1", relay_port)
    except OSError:
        writer.write(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        await writer.drain()
        writer.close()
        log("ws: relay not reachable")
        return
    upstream_writer.write(request["raw"])
    await upstream_writer.drain()
    log(f"ws: connected {writer.get_extra_info('peername')}")
    await asyncio.gather(pipe(reader, upstream_writer), pipe(upstream_reader, writer))
    log("ws: closed")


def respond(writer, status, headers, body=b""):
    lines = [f"HTTP/1.1 {status}"] + [f"{k}: {v}" for k, v in headers.items()]
    writer.write(("\r\n".join(lines) + "\r\n\r\n").encode("latin-1") + body)


async def serve_file(request, writer, root, update_root=None):
    path = unquote(urlsplit(request["target"]).path)
    if update_root is not None and path.startswith("/update/"):
        root, path = update_root, path[len("/update"):]
    if path.endswith("/"):
        path += "index.html"
    target = (root / path.lstrip("/")).resolve()
    if root not in target.parents and target != root or not target.is_file():
        respond(writer, "404 Not Found", {"Content-Length": "9", "Content-Type": "text/plain"}, b"not found")
        return
    accept = request["headers"].get("accept-encoding", "")
    send, encoding = target, None
    for name, suffix in (("br", ".br"), ("gzip", ".gz")):
        candidate = target.with_name(target.name + suffix)
        if name in accept and candidate.is_file():
            send, encoding = candidate, name
            break
    stat = send.stat()
    etag = f'"{stat.st_size:x}-{int(stat.st_mtime):x}"'
    headers = {"Content-Type": TYPES.get(target.suffix, mimetypes.guess_type(target.name)[0] or "application/octet-stream"),
               "Cache-Control": "no-cache", "ETag": etag, "Vary": "Accept-Encoding"}
    if encoding:
        headers["Content-Encoding"] = encoding
    if request["headers"].get("if-none-match") == etag:
        respond(writer, "304 Not Modified", headers)
        return
    headers["Content-Length"] = str(stat.st_size)
    respond(writer, "200 OK", headers)
    if request["method"] == "HEAD":
        return
    with send.open("rb") as stream:
        while True:
            block = stream.read(CHUNK)
            if not block:
                break
            writer.write(block)
            await writer.drain()


async def handle(reader, writer, root, relay_port, update_root=None):
    try:
        while True:
            request = await read_head(reader)
            if request is None:
                break
            if urlsplit(request["target"]).path.startswith("/ws"):
                await proxy_websocket(request, reader, writer, relay_port)
                return
            if request["method"] not in ("GET", "HEAD"):
                respond(writer, "405 Method Not Allowed", {"Content-Length": "0"})
            else:
                await serve_file(request, writer, root, update_root)
            await writer.drain()
            if request["headers"].get("connection", "").lower() == "close":
                break
    except (ConnectionError, OSError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--relay-port", type=int, default=24681)
    parser.add_argument("--update-root", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    if not (root / "index.html").is_file():
        print(f"网页根目录里没有 index.html：{root}", file=sys.stderr)
        return 1
    update_root = args.update_root.resolve() if args.update_root else None
    server = await asyncio.start_server(lambda r, w: handle(r, w, root, args.relay_port, update_root), "127.0.0.1", args.port,
                                        limit=1 << 16)
    log(f"serving {root} on http://127.0.0.1:{args.port}/ , /ws -> 127.0.0.1:{args.relay_port}, /update/ -> {update_root}")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
