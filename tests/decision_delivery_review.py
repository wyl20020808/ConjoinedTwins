"""决策者复验现有 ZIP；不导出，不覆盖执行者证据。"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "builds/macos/decision-review-t04-20261012"
ENGINE = "D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe"
PACKAGE = ROOT / "builds/macos/ConjoinedTwins-macOS-universal.zip"
OUT.mkdir(exist_ok=True)
records = []


def run(command, name, timeout):
    log = OUT / (name + ".log")
    with log.open("w", encoding="utf-8") as stream:
        result = subprocess.run(command, cwd=OUT, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout,
                                env={**os.environ, "PYTHONUTF8": "1"})
    errors = "ERROR:" in log.read_text(encoding="utf-8")
    records.append({"command": command, "exit_code": result.returncode, "engine_errors": errors, "log": str(log)})
    if result.returncode or errors:
        raise RuntimeError(f"Review failed: {name}, exit={result.returncode}, errors={errors}")


try:
    run([sys.executable, str(ROOT / "build-tools/verify_macos.py"), str(PACKAGE), str(OUT / "validation.json")], "validation", 90)
    with zipfile.ZipFile(PACKAGE) as archive:
        entry = next(name for name in archive.namelist() if name.endswith(".pck"))
        pack = OUT / "actual-export.pck"
        pack.write_bytes(archive.read(entry))
    for source, result_name in [("endless_headless.gd", "packed-endless-result.json"), ("endless_collision.gd", "packed-collision-result.json")]:
        original = (ROOT / "tests" / source).read_text(encoding="utf-8")
        original_output = "res://tests/endless-result.json" if source == "endless_headless.gd" else "res://tests/endless-collision-result.json"
        script = OUT / source
        script.write_text(original.replace(original_output, (OUT / result_name).as_posix()), encoding="utf-8")
        run([ENGINE, "--headless", "--path", str(OUT), "--main-pack", str(pack), "--script", str(script)], source.removesuffix(".gd"), 120)
        result = json.loads((OUT / result_name).read_text(encoding="utf-8"))
        if not result["passed"]:
            raise RuntimeError(f"Packed assertions failed: {source}")
        print(source, "checks", len(result["checks"]), "pass", flush=True)
    status = "pass"
finally:
    report = {"status": locals().get("status", "failed"), "commands": records, "size": PACKAGE.stat().st_size,
              "sha256": hashlib.sha256(PACKAGE.read_bytes()).hexdigest(), "boundary": "Windows headless actual PCK and static Mach-O validation; Mac runtime pending"}
    (OUT / "review.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"status": report["status"], "commands": len(records), "sha256": report["sha256"]}), flush=True)
