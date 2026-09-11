#!/usr/bin/env bash
# 设备侧（L2）契约测试：构建测试 HAP 并在真机上运行。
#
# 用法：./scripts/device-test.sh
# 前置：设备已开 USB 调试并被 hdc 识别（见 docs/ENVIRONMENT.md §4）
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
ROOT_DIR="$(cd "$HERE/.." && pwd -P)"
# shellcheck source=./env.sh
source "$HERE/env.sh" || exit 2

if ! hdc list targets 2>/dev/null | grep -qv '\[Empty\]'; then
  echo "[device-test] 未发现设备：先在平板打开「USB 调试」并授权。" >&2
  echo "[device-test] 判据：lsusb -d 12d1:1101 -v | grep iInterface —— 若是 MTP 说明调试没开（ENVIRONMENT.md §4）" >&2
  exit 2
fi

cd "$ROOT_DIR" || exit 2
echo "[device-test] hvigorw onDeviceTest ..."
hvigorw onDeviceTest --mode module -p module=entry@ohosTest -p product=default --no-daemon
status=$?
echo "[device-test] 退出码=$status"

# 测试 HAP 同时回收一份到 build-output/，便于手动 aa test
mkdir -p "$ROOT_DIR/build-output"
while IFS= read -r f; do
  cp -f "$f" "$ROOT_DIR/build-output/" && echo "[device-test] 回收：$(basename "$f")"
done < <(find "$ROOT_DIR/entry/build" -type f -name '*ohosTest*.hap' 2>/dev/null)

exit "$status"
