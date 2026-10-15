#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BLENDER_EXECUTABLE=${BLENDER_EXECUTABLE:-/Applications/Blender.app/Contents/MacOS/Blender}
if [ ! -x "$BLENDER_EXECUTABLE" ]; then
  echo "未找到 Blender。安装完成后重试，或设置 BLENDER_EXECUTABLE 为实际可执行文件路径。" >&2
  exit 2
fi
"$BLENDER_EXECUTABLE" --background --python "$TASK_ROOT/build-tools/journey/make_assets.py"

"$BLENDER_EXECUTABLE" --background --python "$TASK_ROOT/build-tools/journey/make_villager_actions.py"
