"""Project-local official template acquisition and bounded headless packaging."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import traceback
import urllib.request
import zipfile
from official_range import extract, DownloadCheckpoint

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "build-tools/cache"
OUTPUT = ROOT / "builds/macos"
ENGINE = "D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe"
# 打包门槛使用的当前生产回归（脚本名, 超时秒）。三难度合法键盘路线约需 5 分钟。
PRODUCTION_TESTS = [
    ("baseline_controls", 120),
    ("baseline_rope_view", 120),
    ("road_charge_gate", 120),
    ("road_sync_plates", 120),
    ("endless_collision", 60),
    ("baseline_random_routes", 600),
]
API = "https://api.github.com/repos/godotengine/godot-builds/releases/tags/4.7.1-stable"


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def templates(download_seconds=None):
    CACHE.mkdir(parents=True, exist_ok=True)
    manifest = CACHE / "template-source.json"
    if manifest.exists() and (CACHE / "macos.zip").exists():
        evidence = json.loads(manifest.read_text(encoding="utf-8"))
        if evidence["version"] != "4.7.1-stable" or evidence["macos_template_sha256"] != sha(CACHE / "macos.zip"):
            raise RuntimeError("Cached template identity mismatch; files retained")
        with zipfile.ZipFile(CACHE / "macos.zip") as zipped:
            if zipped.testzip() is not None:
                raise RuntimeError("Cached template ZIP corrupted")
        print("Verified project-local macOS template cache", flush=True)
        return True
    request = urllib.request.Request(API, headers={"User-Agent": "ConjoinedTwins-packager"})
    with urllib.request.urlopen(request, timeout=60) as response:
        release = json.load(response)
    asset = next(a for a in release["assets"] if a["name"] == "Godot_v4.7.1-stable_export_templates.tpz")
    archive = CACHE / asset["name"]
    expected = asset.get("digest", "").removeprefix("sha256:")
    if not expected:
        raise RuntimeError("Official SHA-256 unavailable; refuse unverified template")
    if not archive.exists():
        try:
            evidence = extract(asset, CACHE, download_seconds)
        except DownloadCheckpoint as checkpoint:
            print(str(checkpoint), flush=True)
            return False
        evidence.update({"version": "4.7.1-stable", "release": release["html_url"],
                         "url": asset["browser_download_url"], "asset_size": asset["size"],
                         "official_archive_sha256": expected, "installed_globally": False,
                         "macos_template_sha256": sha(CACHE / "macos.zip")})
        save(CACHE / "template-source.json", evidence)
        print("Official macOS entries extracted and CRC verified", flush=True)
        return True
    actual = sha(archive)
    if actual != expected:
        raise RuntimeError("Cached template checksum mismatch; existing file retained")
    with zipfile.ZipFile(archive) as zipped:
        entry = next(n for n in zipped.namelist() if n.endswith("/macos.zip"))
        data = zipped.read(entry)
    target = CACHE / "macos.zip"
    if target.exists() and target.read_bytes() != data:
        raise RuntimeError("Existing macos.zip differs; refuse overwrite")
    if not target.exists():
        target.write_bytes(data)
    evidence = {"version": "4.7.1-stable", "release": release["html_url"],
                "url": asset["browser_download_url"], "size": archive.stat().st_size,
                "official_sha256": expected, "actual_sha256": actual,
                "checksum_match": True, "extracted_entry": entry,
                "macos_template_sha256": sha(target), "installed_globally": False}
    save(CACHE / "template-source.json", evidence)
    print(json.dumps(evidence, indent=2), flush=True)
    return True


def run(command, log, timeout, records):
    with log.open("w", encoding="utf-8") as stream:
        stream.write(json.dumps(command) + "\n")
        stream.flush()
        try:
            result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired:
            stream.write("\nTIMEOUT (child terminated and reaped)\n")
            records.append({"command": command, "exit_code": None, "timeout": True, "log": str(log)})
            raise
        stream.write(f"\nEXIT_CODE={result.returncode}\n")
    record = {"command": command, "exit_code": result.returncode, "log": str(log)}
    records.append(record)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}); see {log}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--templates-only", action="store_true")
    parser.add_argument("--engine", default=ENGINE)
    parser.add_argument("--download-seconds", type=int)
    args = parser.parse_args()
    if not templates(args.download_seconds):
        sys.exit(3)  # Download checkpoint, not a completed package.
    if args.templates_only:
        return
    OUTPUT.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    evidence_dir = OUTPUT / ("evidence-" + stamp)
    evidence_dir.mkdir()
    report = {"timestamp_utc": stamp, "commands": [], "mac_playtest": "pending",
              "decision_review": "pending", "controller_independent_test": "not_run"}
    save(evidence_dir / "run.json", report)
    try:
        version = subprocess.check_output([args.engine, "--headless", "--version"], text=True).strip()
        if version != "4.7.1.stable.official.a13da4feb":
            raise RuntimeError(f"Unexpected engine version: {version}")
        report["engine_version"] = version
        target = OUTPUT / "ConjoinedTwins-macOS-universal.zip"
        if target.exists():
            previous = {"sha256": sha(target), "size": target.stat().st_size}
            history = OUTPUT / "history"
            history.mkdir(exist_ok=True)
            backup = history / f"ConjoinedTwins-{stamp}-{previous['sha256'][:12]}.zip"
            shutil.copy2(target, backup)
            previous["preserved_at"] = str(backup)
            report["previous_package"] = previous
            save(evidence_dir / "run.json", report)
        from network_manifest import generate
        generate()
        run([args.engine, "--headless", "--path", str(ROOT), "--editor", "--import"], evidence_dir / "import.log", 120, report["commands"])
        run([args.engine, "--headless", "--path", str(ROOT), "--export-release", "macOS Universal", str(target)], evidence_dir / "export.log", 180, report["commands"])
        run([sys.executable, str(ROOT / "build-tools/verify_macos.py"), str(target), str(evidence_dir / "validation.json")], evidence_dir / "validation.log", 120, report["commands"])
        with zipfile.ZipFile(target) as zipped:
            pack_entry = next(n for n in zipped.namelist() if n.endswith(".pck"))
            pack = evidence_dir / "exported-game.pck"
            pack.write_bytes(zipped.read(pack_entry))
        smoke_log = evidence_dir / "exported-pck-smoke.log"
        run([args.engine, "--headless", "--path", str(evidence_dir), "--main-pack", str(pack), "--quit-after", "3"], smoke_log, 30, report["commands"])
        if "ERROR:" in smoke_log.read_text(encoding="utf-8"):
            raise RuntimeError("Exported PCK smoke test logged errors")
        report["exported_pck_smoke"] = "pass (Windows headless engine; not Mac binary execution)"
        # 当前有限三关生产回归：基线操作、绳索显示、三难度合法键盘路线、两类合作门及连续碰撞。
        # 历史 endless_headless.gd 仍断言无限无终点，已不适用于当前生产玩法，不再作为打包门槛。
        regressions = {}
        for name, timeout in PRODUCTION_TESTS:
            log = evidence_dir / f"{name}.log"
            run([args.engine, "--headless", "--path", str(ROOT), "--script", f"res://tests/{name}.gd"], log, timeout, report["commands"])
            text = log.read_text(encoding="utf-8")
            if "SCRIPT ERROR" in text or "\nFAIL " in text:
                raise RuntimeError(f"Production regression {name} reported failures; see {log}")
            regressions[name] = "pass"
        report["production_regressions"] = regressions
        shutil.copy2(ROOT / "tests/endless-collision-result.json", evidence_dir / "collision-result.json")
        shutil.copy2(CACHE / "template-source.json", evidence_dir / "template-source.json")
        report.update({"self_test": "pass", "package": str(target), "size": target.stat().st_size, "sha256": sha(target)})
    except Exception as error:
        report.update({"self_test": "failed", "error": str(error)})
        raise
    finally:
        save(evidence_dir / "run.json", report)
        print(str(evidence_dir), flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        CACHE.mkdir(parents=True, exist_ok=True)
        with (CACHE / "package-error.log").open("a", encoding="utf-8") as stream:
            stream.write(datetime.datetime.now(datetime.timezone.utc).isoformat() + "\n")
            traceback.print_exc(file=stream)
        raise
