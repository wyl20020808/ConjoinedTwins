"""串行启动独立中继与两个生产客户端，验证原生联机故障恢复；证据保存在工程外。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot"))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.godot:
        parser.error("请指定 --godot 引擎可执行文件")
    output = (args.output or Path(tempfile.mkdtemp(prefix="ConjoinedTwins-native-online-"))).resolve()
    if output == ROOT or ROOT in output.parents:
        parser.error("--output 必须位于工程外")
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        parser.error("--output 必须为空目录，避免覆盖既有证据")
    sources = list((ROOT / "scripts").glob("*.gd")) + [ROOT / "project.godot", Path(__file__), ROOT / "tests/native_online_process.gd"]
    digest = lambda: {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    initial_hashes = digest()
    processes, logs, checks, measurements = {}, {}, [], {}

    def phase(name):
        temporary = output / "control.tmp"
        temporary.write_text(json.dumps({"phase": name}), encoding="utf-8")
        temporary.replace(output / "control.json")

    def state(endpoint):
        try:
            return json.loads((output / f"{endpoint}.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}

    def wait(predicate, seconds=5):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if predicate():
                return True
            if any(p.poll() is not None for p in processes.values()):
                return False
            time.sleep(0.05)
        return bool(predicate())

    def check(condition, label):
        checks.append({"name": label, "passed": bool(condition)})
        print(f"{'PASS' if condition else 'FAIL'} {label}", flush=True)
        if not condition:
            raise AssertionError(label)

    def launch(endpoint, port):
        env = os.environ.copy()
        env.update(ONLINE_TEST_DIRECTORY=str(output), ONLINE_TEST_ENDPOINT=endpoint, ONLINE_TEST_PORT=str(port))
        logs[endpoint] = (output / f"{endpoint}.log").open("w", encoding="utf-8")
        processes[endpoint] = subprocess.Popen(
            [args.godot, "--headless", "--path", str(ROOT), "--script", "res://tests/native_online_process.gd"],
            env=env, stdout=logs[endpoint], stderr=subprocess.STDOUT)

    failure = None
    exits = {}
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        phase("warmup")
        launch("relay", port)
        check(wait(lambda: bool(state("relay"))), "独立中继启动")
        for role in range(2):
            endpoint = f"client{role}"
            launch(endpoint, port)
            check(wait(lambda: state(endpoint).get("role") == role, 30), f"独立客户端 {role} 完成握手")
        check(wait(lambda: all(state(f"client{i}").get("applied", 0) >= 90 and state(f"client{i}").get("state") == "running" for i in range(2)), 15), "两个生产场景共同开始")
        phase("stall")
        check(wait(lambda: state("client1").get("phase") == "stall"), "慢端暂停物理更新")
        time.sleep(2)
        peak = state("client1").get("queue", 0)
        measurements["backlog_peak"] = peak
        # ACK 每 15 帧一次，上限以 ACK 而非客户端当前帧计；无需伪造恰好 90 帧。
        check(60 <= peak <= 90, "两秒停顿产生积压且受 90 帧上限保护")
        phase("catchup")
        resumed = time.monotonic()
        check(wait(lambda: state("client1").get("phase") == "catchup" and state("client1").get("queue", 999) <= state("client1").get("target", 0) + 1, 4), "四秒内追回到自适应目标加一帧以内")
        measurements["catchup_ms"] = round((time.monotonic() - resumed) * 1000)
        phase("hold")
        check(wait(lambda: state("relay").get("inputs", [[], []])[1] == [100, 0, True]
                   and all(state(f"client{i}").get("fire", [False, False])[1] for i in range(2))), "方向、跳跃和持续射击到达两端")
        phase("loss")
        check(wait(lambda: state("relay").get("phase") == "loss"), "注入玩家 02 单向输入丢失")
        lost = time.monotonic()
        check(wait(lambda: state("relay").get("stale", [False, False])[1]
                   and state("relay").get("inputs", [[], []])[1] == [0, 0, False]
                   and all(not state(f"client{i}").get("fire", [True, True])[1] for i in range(2)), 1.5), "超时后共同释放移动、跳跃和射击")
        measurements["neutralized_ms"] = round((time.monotonic() - lost) * 1000)
        phase("recover")
        check(wait(lambda: state("relay").get("inputs", [[], []])[1] == [100, 0, True]
                   and not state("relay").get("stale", [True, True])[1]
                   and all(state(f"client{i}").get("fire", [False, False])[1] for i in range(2)), 2), "恢复后当前长按和射击保活重新生效")
        check(all(not state(f"client{i}").get("desync", True) and state(f"client{i}").get("contiguous", False) for i in range(2)), "故障恢复期间未跳帧且未不同步")
        phase("desync")
        check(wait(lambda: state("relay").get("desync") and all(state(f"client{i}").get("desync") for i in range(2))), "主动注入不同步被两端确认")
        before = [state("relay")["frame"], state("client0")["applied"], state("client1")["applied"]]
        time.sleep(0.6)
        after = [state("relay")["frame"], state("client0")["applied"], state("client1")["applied"]]
        check(before == after, "不同步通知后中继和两个生产模拟均停止推进")
        a, b = state("client0")["hashes"], state("client1")["hashes"]
        common = sorted(set(a) & set(b), key=int)
        measurements["common_hash_frames"] = common
        check(len(common) >= 5 and all(a[k] == b[k] for k in common), "至少五个共同采样帧的生产状态指纹完全一致")
    except (AssertionError, OSError, subprocess.SubprocessError) as error:
        failure = str(error)
    finally:
        phase("shutdown")
        for name, process in processes.items():
            try:
                exits[name] = process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait()
                exits[name] = "timeout"
        for log in logs.values():
            log.close()
    errors = {}
    for name in logs:
        errors[name] = [line for line in (output / f"{name}.log").read_text(encoding="utf-8", errors="replace").splitlines()
                        if re.match(r"^(?:SCRIPT ERROR:|ERROR:|FAIL |WARNING:.*leak)", line)]
    unchanged = initial_hashes == digest()
    passed = failure is None and len(exits) == 3 and all(code == 0 for code in exits.values()) and not any(errors.values()) and unchanged
    report = {"passed": passed, "failure": failure, "checks": checks, "measurements": measurements,
              "exit_codes": exits, "errors": errors, "sources": initial_hashes, "sources_unchanged": unchanged,
              "final_states": {name: state(name) for name in processes},
              "scope": "本机三进程原生 UDP、生产场景与故障注入；不是两台 Windows EXE、公网或 GUI 验收"}
    (output / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{'PASS' if passed else 'FAIL'} {output / 'summary.json'}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
