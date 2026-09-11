#!/usr/bin/env bash
# 只构建 L2 测试 HAP，不运行 —— **不需要设备**。
#
# 为什么要单独有这个脚本：`device-test.sh` 会一直走到装机与运行，无设备时整体失败，
# 于是 ohosTest 源码的类型错误要等到能装机才暴露。本脚本只关心「测试包是否构建成功」，
# 把设备阶段的失败视为预期，从而把 L2 的编译检查纳入日常验证。
#
# 退出码：0 = 测试包构建成功；1 = 编译/打包失败；3 = 没有 ohosTest 目标（跳过）
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
ROOT_DIR="$(cd "$HERE/.." && pwd -P)"
# shellcheck source=./env.sh
source "$HERE/env.sh" || exit 2

if [[ ! -d "$ROOT_DIR/entry/src/ohosTest" ]]; then
  echo "[test-hap] 无 entry/src/ohosTest，跳过"
  exit 3
fi
command -v hvigorw >/dev/null 2>&1 || { echo "[test-hap] 缺 hvigorw" >&2; exit 2; }

cd "$ROOT_DIR" || exit 2
LOG="$(mktemp /tmp/pd-testhap-XXXX.log)"

hvigorw onDeviceTest --mode module -p module=entry@ohosTest -p product=default --no-daemon >"$LOG" 2>&1
status=$?

# 编译期错误：明确失败
if grep -qE "ArkTS Compiler Error|Error Message:" "$LOG"; then
  echo "[test-hap] ❌ 测试源码编译失败："
  grep -E "Error Message:|ERROR" "$LOG" | head -15
  echo "[test-hap] 完整日志：$LOG"
  exit 1
fi

# 打包成功即视为通过。注意增量构建时该任务显示 UP-TO-DATE 而不是 Finished，
# 两种都要认（早期只认 Finished，导致增量场景误报失败）。
if grep -qE "(Finished|UP-TO-DATE) :entry:ohosTest@PackageHap" "$LOG"; then
  echo "[test-hap] ✅ 测试 HAP 构建成功（ArkTS 编译 + 打包通过）"
  # 把后续设备阶段的失败原因如实带出来，避免「绿了就以为全好了」
  if grep -q "need connect-key" "$LOG"; then
    echo "[test-hap] note: 设备阶段失败于无设备（need connect-key），属预期"
  elif grep -q "does not exist. Check whether the hap/hsp package is signed" "$LOG"; then
    echo "[test-hap] note: 设备阶段失败于「主包未签名」（缺 entry-default-signed.hap）—— 等 AGC 证书到位即可，属预期"
  elif grep -qE "Failed :|BUILD FAILED" "$LOG"; then
    echo "[test-hap] note: 设备阶段另有失败，原文如下（编译/打包已通过，但请确认这不是真实问题）："
    grep -E "ErrorCode|Description:" "$LOG" | head -4
  fi
  # 回收测试包，便于手动 aa test
  mkdir -p "$ROOT_DIR/build-output"
  while IFS= read -r f; do
    cp -f "$f" "$ROOT_DIR/build-output/" 2>/dev/null && echo "[test-hap] 回收：$(basename "$f")"
  done < <(find "$ROOT_DIR/entry/build" -type f -name '*ohosTest*.hap' 2>/dev/null)
  exit 0
fi

echo "[test-hap] ❌ 未能确认测试包构建成功（hvigor 退出码 $status）"
tail -20 "$LOG"
echo "[test-hap] 完整日志：$LOG"
exit 1
