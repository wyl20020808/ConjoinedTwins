#!/usr/bin/env python3
"""同机串行对照原始 test 与任务分支；产物仅写入忽略的 cache 目录。"""
import argparse
import io
import json
import os
from pathlib import Path
import statistics
import subprocess
import tarfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", default="/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--baseline", default="0b24647")
    parser.add_argument("--samples", type=int, default=3)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = root / "build-tools/cache/loading-performance"
    output.mkdir(parents=True, exist_ok=True)
    baseline = output / "comparison-baseline"
    baseline.mkdir(exist_ok=True)
    reference = subprocess.check_output(["git", "rev-parse", args.baseline + "^{commit}"], cwd=root, text=True).strip()
    archive = subprocess.check_output(["git", "archive", reference, "scripts", "scenes", "project.godot"], cwd=root)
    # 输入为本仓库指定提交的固定目录，不接受外部 tar 文件。
    with tarfile.open(fileobj=io.BytesIO(archive)) as source:
        source.extractall(baseline)
    for directory in ["assets", ".godot"]:
        link = baseline / directory
        if not link.exists():
            link.symlink_to(root / directory, target_is_directory=True)
    for name in ["tests/loading_performance.gd", "tests/journey_performance.gd", "tests/fixtures/loading_baseline.json"]:
        target = baseline / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((root / name).read_bytes())
    records = {}
    cases = [("baseline-road", baseline, "loading_performance"), ("final-road", root, "loading_performance"),
             ("baseline-journey", baseline, "journey_performance"), ("final-journey", root, "journey_performance"),
             ("final-loading", root, "journey_loading")]
    for sample in range(1, args.samples + 1):
        for label, project, script in cases:
            path = output / f"comparison-{label}-{sample}.json"
            env = dict(os.environ, PERFORMANCE_REPORT=str(path))
            log = path.with_suffix(".log")
            with log.open("w") as stream:
                result = subprocess.run([args.engine, "--headless", "--path", str(project), "--script", f"res://tests/{script}.gd"],
                                        cwd=root, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=120)
            text = log.read_text()
            if result.returncode or "SCRIPT ERROR" in text or not path.exists():
                raise RuntimeError(f"{label} failed: {log}")
            records.setdefault(label, []).append(json.loads(path.read_text()))
            print(f"完成 {sample}/{args.samples} {label}", flush=True)
    def median(label, *keys):
        values = []
        for record in records[label]:
            value = record
            for key in keys:
                value = value[key]
            values.append(value)
        return statistics.median(values)
    metrics = {}
    pairs = [
        ("音效初始化 CPU 中位数", "baseline-road", "final-road", ("audio_ready", "median_usec")),
        ("道路原生开局墙钟", "baseline-road", "final-road", ("startups", "native", "wall_usec")),
        ("道路原生准备主线程 CPU 总量", "baseline-road", "final-road", ("startups", "native", "prepare_cpu_usec")),
        ("道路无线程开局墙钟", "baseline-road", "final-road", ("startups", "cooperative", "wall_usec")),
        ("道路无线程准备调用 P95", "baseline-road", "final-road", ("startups", "cooperative", "calls", "p95_usec")),
        ("道路缺口视图 CPU P95", "baseline-road", "final-road", ("moving_gap_view", "p95_usec")),
        ("旅程直接场景就绪墙钟", "baseline-journey", "final-journey", ("scene_ready_usec",)),
        ("旅程稳定视图 CPU P95", "baseline-journey", "final-journey", ("steady_view", "p95_usec")),
    ]
    for title, before, after, keys in pairs:
        old, new = median(before, *keys), median(after, *keys)
        metrics[title] = {"baseline_usec": old, "final_usec": new, "reduction_percent": round((old-new)/old*100, 2)}
    layout_ok = all(record["layout_hashes"] == records["baseline-journey"][0]["layout_hashes"]
                    for label in ["final-journey", "final-loading"] for record in records[label])
    audio_ok = all(record["audio_hashes"] == records["baseline-journey"][0]["audio_hashes"] for record in records["final-journey"])
    summary = {"baseline_commit": reference, "task_commit": subprocess.check_output(["git","rev-parse","HEAD"],cwd=root,text=True).strip(),
               "samples": args.samples, "method": "新进程、串行交错、OS 文件缓存未清空、headless CPU；三次结果取中位数，不是 GPU FPS。", "metrics": metrics,
               "loading_ui_usec": median("final-loading", "loading_ui_usec"), "journey_boot_wall_usec": median("final-loading", "boot_wall_usec"),
               "baseline_region_transition_peak_usec": median("baseline-journey", "transition_view", "max_usec"),
               "prepared_region_view_peak_usec": median("final-loading", "prepared_view", "max_usec"),
               "region_preparation_peak_usec": median("final-loading", "peak_usec"), "layout_equal": layout_ok, "ambience_equal": audio_ok,
               "road_equal": all(record["deterministic"] for label in ["baseline-road","final-road"] for record in records[label]),
               "runtime_waits": [record["runtime_waits"] for record in records["final-loading"]]}
    (output / "comparison-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if not layout_ok or not audio_ok or not summary["road_equal"] or any(summary["runtime_waits"]):
        raise SystemExit("确定性或预读吞吐核验失败")


if __name__ == "__main__":
    main()
