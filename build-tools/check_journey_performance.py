"""串行验证连续旅程的行为、CPU 预算和资源生命周期；失败时返回非零。"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TESTS = (
    "tripo_village_assets", "tripo_village_expansion", "coop_mechanisms",
    "journey_random_layout", "journey_streaming", "journey_warning_window",
    "journey_spatial_regression", "journey_front_sweep", "web_performance_regression",
    "physical_rope_terrain", "journey_pursuit", "journey_combat",
    "journey_monsters", "journey_combat_variety", "journey_world_view", "journey_failure_presentation", "journey_narrow_routes", "journey_polish", "journey_encounter_density",
    "journey_environment_lifetime", "journey_runtime_budget", "rope_mesh_lifetime", "journey_rescue_transition",
    "journey_rescue_hud", "journey_hazard_grounding", "journey_dynamic_geometry", "journey_audio_combat_polish",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot") or "D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe")
    parser.add_argument("--output", type=Path, default=Path(tempfile.gettempdir()) / "ConjoinedTwins-performance" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["ENVIRONMENT_REPORT"] = str(output / "lifetime.json")
    env["JOURNEY_PERF_REPORT"] = str(output / "runtime-budget.json")
    records = []
    sources = list((ROOT / "scripts").glob("*.gd")) + [ROOT / "tests" / f"{test}.gd" for test in TESTS]
    sources += [Path(__file__).resolve(), ROOT / "project.godot", ROOT / "AGENTS.md"]
    sources += list((ROOT / "scripts").glob("*.gdshader"))
    sources += list((ROOT / "assets/landscape").glob("natural_*.glb"))
    sources += list((ROOT / "assets/landscape").glob("tripo_*.glb"))
    sources += list((ROOT / "assets/journey").glob("tripo_*.glb"))
    sources += list((ROOT / "assets/landscape").glob("tripo_*.glb.import"))
    sources += list((ROOT / "assets/journey").glob("tripo_*.glb.import"))
    sources += list((ROOT / "assets/landscape/ground").glob("*.png"))
    sources += list((ROOT / "assets/landscape/ground").glob("*.png.import"))
    sources += [ROOT / "build-tools/journey/bake_tripo_ground.gd", ROOT / "build-tools/journey/tripo_ground_bake.gdshader"]
    sources += [ROOT / "build-tools/journey/tripo-village-assets.json", ROOT / "build-tools/journey/tripo-village-expansion-assets.json"]
    sources += [ROOT / "build-tools/journey/natural-tree-assets.json"]
    sources += [ROOT / "tests/fixtures/journey_route.gd", ROOT / "tests/fixtures/tripo_village_review.gd", ROOT / "tests/journey_monster_campaign.gd"]
    source_hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    for test in TESTS:
        print(f"RUN {test}", flush=True)
        command = [args.godot, "--headless", "--path", str(ROOT), "--script", f"res://tests/{test}.gd"]
        log_path = output / f"{test}.log"
        timed_out = False
        try:
            # 只回收本命令创建的测试进程；不枚举或停止用户的游戏。
            with log_path.open("w", encoding="utf-8") as log:
                process = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=180, check=False)
            code = process.returncode
        except subprocess.TimeoutExpired:
            code = -1
            timed_out = True
        except OSError as error:
            code = -1
            log_path.write_text(f"ERROR: {error}\n", encoding="utf-8")
        text = log_path.read_text(encoding="utf-8", errors="replace")
        errors = [line for line in text.splitlines() if re.match(r"^(?:SCRIPT ERROR:|ERROR:|FAIL |WARNING:.*leak)", line)]
        passed = code == 0 and not errors and not timed_out
        records.append({"test": test, "passed": passed, "exit_code": code, "timeout": timed_out, "errors": errors, "log": str(log_path)})
        print(f"{'PASS' if passed else 'FAIL'} {test}", flush=True)
    unchanged = all(path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == source_hashes[str(path.relative_to(ROOT))] for path in sources)
    passed = unchanged and all(record["passed"] for record in records)
    report = {"passed": passed, "project": str(ROOT), "godot": args.godot, "sources": source_hashes, "tests": records,
              "sources_unchanged_during_tests": unchanged,
              "scope": "headless functional, CPU and lifetime checks; no GPU FPS or physical input acceptance"}
    (output / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{'PASS' if passed else 'FAIL'}: {output / 'summary.json'}")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
