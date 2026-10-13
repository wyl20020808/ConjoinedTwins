"""Validate ZIP, PCK and both Mach-O ad-hoc CodeDirectories on Windows."""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct
import sys
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def signatures(data, special_resources):
    require(data[:4] == b"\xca\xfe\xba\xbe", "Expected Universal Mach-O")
    count = struct.unpack_from(">I", data, 4)[0]
    results = []
    for index in range(count):
        cpu, subtype, offset, size, alignment = struct.unpack_from(">IIIII", data, 8 + index * 20)
        thin = data[offset:offset + size]
        require(thin[:4] == b"\xcf\xfa\xed\xfe", "Expected 64-bit Mach-O")
        ncmds = struct.unpack_from("<I", thin, 16)[0]
        pos = 32
        sig = None
        for _ in range(ncmds):
            cmd, length = struct.unpack_from("<II", thin, pos)
            require(length >= 8, "Invalid Mach-O command")
            if cmd == 0x1D:
                start, length_sig = struct.unpack_from("<II", thin, pos + 8)
                sig = thin[start:start + length_sig]
            pos += length
        require(sig is not None, "Missing LC_CODE_SIGNATURE")
        magic, length, slots = struct.unpack_from(">III", sig)
        require(magic == 0xFADE0CC0 and length <= len(sig), "Invalid signature SuperBlob")
        directories = []
        for slot in range(slots):
            slot_type, blob_offset = struct.unpack_from(">II", sig, 12 + slot * 8)
            blob = sig[blob_offset:]
            if struct.unpack_from(">I", blob)[0] != 0xFADE0C02:
                continue
            _, cd_length, version, flags, hash_offset, ident_offset, specials, codes, limit = struct.unpack_from(">9I", blob)
            hash_size, hash_type, platform, page_exp = struct.unpack_from("4B", blob, 36)
            require(flags & 2, "CodeDirectory lacks CS_ADHOC")
            require(hash_type in (1, 2, 3, 4), "Unsupported signature hash")
            algorithm = {1: "sha1", 2: "sha256", 3: "sha256", 4: "sha384"}[hash_type]
            if version >= 0x20300 and limit == 0xFFFFFFFF:
                limit = struct.unpack_from(">Q", blob, 56)[0]
            page_size = 1 << page_exp
            require(codes == (limit + page_size - 1) // page_size, "Wrong CodeDirectory page count")
            for page in range(codes):
                actual = hashlib.new(algorithm, thin[page * page_size:min((page + 1) * page_size, limit)]).digest()[:hash_size]
                expected = blob[hash_offset + page * hash_size:hash_offset + (page + 1) * hash_size]
                require(actual == expected, f"Signature page hash mismatch: CPU {cpu}, page {page}")
            verified_specials = []
            for slot_number, payload in special_resources.items():
                require(specials >= slot_number, "Missing signed resource special slot")
                expected = blob[hash_offset - slot_number * hash_size:hash_offset - (slot_number - 1) * hash_size]
                require(hashlib.new(algorithm, payload).digest()[:hash_size] == expected,
                        f"CodeDirectory resource binding mismatch: slot {slot_number}")
                verified_specials.append(slot_number)
            directories.append({"flags": flags, "ad_hoc": True, "hash_algorithm": algorithm,
                                "verified_code_pages": codes, "verified_special_slots": verified_specials,
                                "identifier": blob[ident_offset:].split(b"\0")[0].decode()})
        require(directories, "Missing CodeDirectory")
        results.append({"cpu": cpu, "architecture": {0x1000007: "x86_64", 0x100000C: "arm64"}.get(cpu), "code_directories": directories})
    require({r["architecture"] for r in results} == {"x86_64", "arm64"}, "Both architectures required")
    return results


def pck_files(data):
    require(data[:4] == b"GDPC", "Invalid PCK header")
    version = struct.unpack_from("<I", data, 4)[0]
    flags = struct.unpack_from("<I", data, 20)[0]
    require(not flags & 1, "Encrypted PCK directory unsupported")
    base = struct.unpack_from("<Q", data, 24)[0]
    require(version in (2, 3, 4), "Unknown PCK format")
    pos = struct.unpack_from("<Q", data, 32)[0] if version >= 3 else 96
    count = struct.unpack_from("<I", data, pos)[0]
    pos += 4
    files = []
    for _ in range(count):
        length = struct.unpack_from("<I", data, pos)[0]
        pos += 4
        name = data[pos:pos + length].rstrip(b"\0").decode()
        pos += length
        offset, size = struct.unpack_from("<QQ", data, pos)
        digest = data[pos + 16:pos + 32]
        file_flags = struct.unpack_from("<I", data, pos + 32)[0]
        pos += 36
        require(file_flags == 0, "Unexpected PCK file flags")
        payload = data[base + offset:base + offset + size]
        require(len(payload) == size, "Truncated PCK resource")
        require(hashlib.md5(payload).digest() == digest, f"PCK resource hash mismatch: {name}")
        require(not re.search(r"(^|/)(tests|docs|build-tools|builds)/|\.(cmd|log)$", name), f"Excluded resource in PCK: {name}")
        files.append(name)
    return {"format": version, "files": files, "all_resource_md5_verified": True}


def main():
    path, output = map(Path, sys.argv[1:3])
    preset = (Path(__file__).resolve().parents[1] / "export_presets.cfg").read_text()
    require('codesign/codesign=1' in preset and 'notarization/notarization=0' in preset, "Incorrect signing preset")
    with zipfile.ZipFile(path) as zipped:
        require(zipped.testzip() is None, "ZIP CRC failure")
        names = zipped.namelist()
        plist_path = next(n for n in names if n.endswith(".app/Contents/Info.plist"))
        root = plist_path.removesuffix("Contents/Info.plist")
        require(all(n.startswith(root) for n in names), "Unexpected ZIP root")
        plist = plistlib.loads(zipped.read(plist_path))
        bundle = plist["CFBundleIdentifier"]
        require(bundle == "org.conjoinedtwins.whitebox" and re.fullmatch(r"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+", bundle), "Wrong bundle identifier")
        executable = root + "Contents/MacOS/" + plist["CFBundleExecutable"]
        info = zipped.getinfo(executable)
        mode = info.external_attr >> 16
        require(info.create_system == 3 and mode & 0o111, "ZIP lacks Unix executable permissions")
        require(root + "Contents/_CodeSignature/CodeResources" in names, "Missing signed resource envelope")
        architectures = signatures(zipped.read(executable), {
            1: zipped.read(plist_path), 3: zipped.read(root + "Contents/_CodeSignature/CodeResources")})
        envelope = plistlib.loads(zipped.read(root + "Contents/_CodeSignature/CodeResources"))
        sealed = 0
        for name, value in envelope.get("files2", {}).items():
            if isinstance(value, dict) and "hash2" in value:
                require(hashlib.sha256(zipped.read(root + "Contents/" + name)).digest() == value["hash2"], f"Resource seal mismatch: {name}")
                sealed += 1
        packs = [n for n in names if n.endswith(".pck")]
        require(len(packs) == 1, "Expected one game PCK")
        resources = pck_files(zipped.read(packs[0]))
        require(plist.get("CFBundleShortVersionString") == "0.3.0", "Wrong current package version")
        for dependency in ("scenes/road_demo", "scripts/road_demo", "scripts/road_run", "scripts/road_templates", "scripts/link_motion",
                           "assets/mechs/George.gltf", "assets/mechs/Leela.gltf", "assets/industrial/building-a.glb",
                           "assets/industrial/building-f.glb", "assets/industrial/building-k.glb", "assets/industrial/building-p.glb",
                           "assets/industrial/shipping-container-a.glb", "assets/industrial/detail-tank.glb",
                           "assets/industrial/chimney-large.glb", "assets/industrial/Textures/colormap.png"):
            require(any(dependency + "." in n for n in resources["files"]), f"Missing production dependency: {dependency}")
        report = {"status": "pass", "zip_crc": "pass", "bundle_id": bundle,
                  "executable": executable, "unix_mode": oct(mode), "architectures": architectures,
                  "resource_envelope_sha256_verified": sealed, "pck": resources,
                  "zip_entries": names, "notarized": False, "mac_execution": "pending",
                  "boundary": "Static hash/structure validation, not Apple's codesign or macOS runtime verification",
                  "size": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
