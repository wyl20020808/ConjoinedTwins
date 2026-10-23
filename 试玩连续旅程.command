#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GODOT_EXECUTABLE=${GODOT_EXECUTABLE:-/Applications/Godot.app/Contents/MacOS/Godot}
if [ ! -x "$GODOT_EXECUTABLE" ]; then
  echo "未找到 Godot。请在 Godot 中导入本目录的 project.godot，或设置 GODOT_EXECUTABLE。" >&2
  exit 2
fi
exec "$GODOT_EXECUTABLE" --path "$TASK_ROOT"
