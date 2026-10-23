"""在临时目录验证安装、快捷方式、重复安装、启动与卸载；仅允许在 idle 模式运行。

会短暂创建真实桌面和开始菜单快捷方式。已安装共生连线或存在同名快捷方式时停止。
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import winreg

import prepare_windows

KEY = r"Software\Microsoft\Windows\CurrentVersion\Uninstall\{F2E2A735-C912-4CCE-ABF0-74F70628F3CB}_is1"


def installed():
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, KEY):
            return True
    except FileNotFoundError:
        return False


def shell_folder(name):
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                        r"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders") as key:
        return Path(os.path.expandvars(winreg.QueryValueEx(key, name)[0]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("installer", type=Path)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    try:
        policy = json.loads(Path("D:/PersonalAgent-data/global-interaction-policy.json").read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        policy = {}
    if policy.get("mode") != "idle":
        raise SystemExit("deferred_by_work_mode：安装快捷方式验证会修改桌面")
    desktop = shell_folder("Desktop") / "共生连线.lnk"
    menu = shell_folder("Programs") / "共生连线"
    if installed() or desktop.exists() or menu.exists():
        raise SystemExit("已有安装或同名快捷方式，保留现状，不运行本机安装验证")
    args.evidence.mkdir(parents=True, exist_ok=False)
    checks = []
    with tempfile.TemporaryDirectory(prefix="ct-install-check-") as temp:
        root = Path(temp)
        app = root / "中文路径 游戏"
        try:
            for step in ("install", "reinstall"):
                result = subprocess.run([str(args.installer.resolve()), "/VERYSILENT", "/SUPPRESSMSGBOXES",
                                         "/NORESTART", "/SP-", f"/DIR={app}", "/TASKS=desktopicon",
                                         f"/LOG={args.evidence.resolve() / (step + '.log')}"], timeout=180)
                assert result.returncode == 0, (step, result.returncode)
                assert installed() and desktop.is_file()
                assert (menu / "共生连线.lnk").is_file() and (menu / "卸载共生连线.lnk").is_file()
                for path in args.source.rglob("*"):
                    if path.is_file() and path.name != "使用说明.txt":
                        assert prepare_windows.sha(path) == prepare_windows.sha(app / path.relative_to(args.source)), path
                checks.append(step + "：文件哈希、桌面快捷方式、开始菜单、卸载项通过")
                (app / "保留我的文件.txt").write_text("用户文件", encoding="utf-8")
            # 独立用户数据目录；不开窗口、不连接公共联机房间。
            env = dict(os.environ, APPDATA=str(root / "roaming"), LOCALAPPDATA=str(root / "local"))
            with (args.evidence / "startup.log").open("w", encoding="utf-8") as log:
                result = subprocess.run([str(app / "ConjoinedTwins.exe"), "--headless", "--quit-after", "120",
                                         "--", "--ct-no-update"], env=env, stdout=log,
                                        stderr=subprocess.STDOUT, timeout=90)
            startup = (args.evidence / "startup.log").read_text(encoding="utf-8")
            startup_ok = result.returncode == 0 and "ERROR" not in startup and "leaked" not in startup
            checks.append("安装后 headless 启动日志：" + ("通过" if startup_ok else "失败，见 startup.log"))
        finally:
            uninstaller = app / "unins000.exe"
            if uninstaller.exists():
                result = subprocess.run([str(uninstaller), "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART",
                                         f"/LOG={args.evidence.resolve() / 'uninstall.log'}"], timeout=120)
                assert result.returncode == 0
                for _ in range(50):
                    if not (app / "ConjoinedTwins.exe").exists() and not installed():
                        break
                    time.sleep(0.1)
                assert not installed() and not desktop.exists() and not menu.exists()
                assert not (app / "ConjoinedTwins.exe").exists() and not (app / "packs").exists()
                assert (app / "保留我的文件.txt").read_text(encoding="utf-8") == "用户文件"
                checks.append("卸载通过：快捷方式与注册项已移除，用户文件保留")
    (args.evidence / "acceptance.json").write_text(json.dumps({"checks": checks,
        "installer_sha256": prepare_windows.sha(args.installer), "controller_tests": [],
        "gui_test": "not_run", "player_test": "pending"}, ensure_ascii=False, indent=2), encoding="utf-8")
    print("\n".join(checks))
    if not startup_ok:
        raise SystemExit("安装生命周期验证通过；游戏启动/退出日志检查失败，详见 startup.log")


if __name__ == "__main__":
    main()
