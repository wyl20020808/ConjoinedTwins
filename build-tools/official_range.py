"""Seekable, cached HTTP Range reader for the official release ZIP (ZIP64 included)."""
import hashlib
import io
import json
from pathlib import Path
import time
import urllib.parse
import urllib.request
import zipfile


class DownloadCheckpoint(Exception):
    pass


class OfficialRange(io.RawIOBase):
    def __init__(self, asset, cache, seconds=None):
        self.asset = asset
        self.cache = cache / "official-ranges"
        self.cache.mkdir(exist_ok=True)
        self.position = 0
        self.deadline = time.monotonic() + seconds if seconds else None
        self.record = self.cache / "responses.json"
        self.evidence = json.loads(self.record.read_text()) if self.record.exists() else []
        identity = self.cache / "asset.json"
        current = {key: asset.get(key) for key in ("id", "size", "digest", "updated_at", "browser_download_url")}
        if identity.exists() and json.loads(identity.read_text()) != current:
            raise ValueError("Official asset identity changed; existing cache retained")
        identity.write_text(json.dumps(current, indent=2), encoding="utf-8")
        self.validator = next((r.get("etag") for r in self.evidence if r.get("etag")), None)

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=0):
        self.position = offset + (self.position if whence == 1 else self.asset["size"] if whence == 2 else 0)
        if not 0 <= self.position <= self.asset["size"]:
            raise ValueError("Invalid remote ZIP seek")
        return self.position

    def fetch(self, start, end):
        cached = self.cache / f"{start}-{end}.bin"
        known = next((r for r in self.evidence if r["start"] == start and r["end"] == end and "sha256" in r), None)
        if cached.exists() and known:
            data = cached.read_bytes()
            if len(data) != end - start + 1 or hashlib.sha256(data).hexdigest() != known["sha256"]:
                raise ValueError("Range cache corrupted; retained for diagnosis")
            return data
        if self.deadline and time.monotonic() >= self.deadline:
            raise DownloadCheckpoint("Range download checkpoint; rerun to resume")
        headers = {"Range": f"bytes={start}-{end}", "Accept-Encoding": "identity"}
        if self.validator:
            headers["If-Range"] = self.validator
        with urllib.request.urlopen(urllib.request.Request(self.asset["browser_download_url"], headers=headers), timeout=60) as response:
            final = urllib.parse.urlsplit(response.url)
            if final.scheme != "https" or final.hostname not in ("github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"):
                raise ValueError("Unexpected official asset redirect")
            record = {"start": start, "end": end, "status": response.status,
                      "content_range": response.headers.get("Content-Range"),
                      "etag": response.headers.get("ETag"), "last_modified": response.headers.get("Last-Modified"),
                      "asset_size": self.asset["size"], "official_url": self.asset["browser_download_url"],
                      "redirect_url": response.url}
            self.evidence.append(record)
            self.record.write_text(json.dumps(self.evidence, indent=2), encoding="utf-8")
            if response.status != 206 or record["content_range"] != f"bytes {start}-{end}/{self.asset['size']}":
                raise ValueError("Range unsupported or misaligned; HTTP evidence retained")
            if self.validator and record["etag"] != self.validator:
                raise ValueError("Official asset changed during download")
            self.validator = record["etag"]
            data = response.read(end - start + 2)
            if len(data) != end - start + 1:
                raise ValueError("Truncated or oversized range response")
        record["sha256"] = hashlib.sha256(data).hexdigest()
        self.record.write_text(json.dumps(self.evidence, indent=2), encoding="utf-8")
        cached.write_bytes(data)
        print(f"Official range cached: {start}-{end} ({len(data)} bytes)", flush=True)
        return data

    def read(self, size=-1):
        remaining = self.asset["size"] - self.position
        size = min(size if size >= 0 else remaining, remaining)
        blocks = []
        while size:
            count = min(size, 4 * 1024 * 1024)
            blocks.append(self.fetch(self.position, self.position + count - 1))
            self.position += count
            size -= count
        return b"".join(blocks)


def extract(asset, cache, seconds=None, suffixes=("/version.txt", "/macos.zip")):
    remote = OfficialRange(asset, cache, seconds)
    entries = []
    with zipfile.ZipFile(remote) as archive:
        for suffix in suffixes:
            info = next(i for i in archive.infolist() if i.filename.endswith(suffix))
            data = archive.read(info)  # Python zipfile checks ZIP/ZIP64 lengths and CRC.
            target = cache / Path(info.filename).name
            if target.exists() and target.read_bytes() != data:
                raise ValueError(f"Existing {target.name} differs; refuse overwrite")
            if suffix == "/version.txt" and data.decode().strip() != "4.7.1.stable":
                raise ValueError("Template version mismatch")
            if suffix.endswith(".zip"):
                with zipfile.ZipFile(io.BytesIO(data)) as inner:
                    if inner.testzip() is not None:
                        raise ValueError(f"{target.name} internal CRC failure")
            if not target.exists():
                target.write_bytes(data)
            entries.append({"entry": info.filename, "crc32": f"{info.CRC:08x}", "crc_checked": True,
                            "size": info.file_size, "compressed_size": info.compress_size,
                            "sha256": hashlib.sha256(data).hexdigest()})
    return {"method": "official_https_range", "entries": entries, "http_evidence": str(remote.record),
            "full_archive_sha256_verified": False,
            "checksum_boundary": "全归档官方 SHA-256 校验未执行；仅检查选取条目 CRC、macos.zip 内部 CRC 和本地 SHA-256"}
