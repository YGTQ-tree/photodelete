#!/usr/bin/env bash
# PhotoDelete 真机开发回路：构建 → 签名 → 装机 → 拉起 → 抓日志
#
# 用法：./scripts/dev-loop.sh [--no-build] [--log-seconds N]
# 依赖：signature/ 下已有 AGC 签发的 .cer 与 .p7b（见 docs/ENVIRONMENT.md §5）
# 任一必需步骤不可用时会**明确报错并停下**，不做静默降级。
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
ROOT_DIR="$(cd "$HERE/.." && pwd -P)"
# shellcheck source=./env.sh
source "$HERE/env.sh" || exit 2

DO_BUILD=1
LOG_SECONDS=15
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) DO_BUILD=0; shift ;;
    --log-seconds) LOG_SECONDS="${2:-15}"; shift 2 ;;
    *) echo "未知参数：$1"; exit 2 ;;
  esac
done

BUNDLE="${PD_BUNDLE:-com.dsh.photodelete}"
ABILITY="${PD_ABILITY:-EntryAbility}"
SIGNED_HAP="$ROOT_DIR/build-output/entry-default-signed.hap"

die() { echo "[dev-loop] 错误：$*" >&2; exit 1; }

command -v hdc >/dev/null 2>&1 || die "缺少 hdc"
if ! hdc list targets 2>/dev/null | grep -qv '\[Empty\]'; then
  die "未发现设备：请在平板上打开「USB 调试」并授权
  判据：lsusb -d 12d1:1101 -v | grep iInterface —— 若显示 MTP 说明调试没开（ENVIRONMENT.md §4）"
fi

if [[ "$DO_BUILD" == "1" ]]; then
  "$HERE/build.sh" || die "构建失败"
fi

"$HERE/sign-hap.sh" || die "签名失败（检查 signature/ 下的 .cer 与 .p7b）"

echo "[dev-loop] 安装 $SIGNED_HAP ..."
hdc install -r "$SIGNED_HAP" || die "安装失败（签名不受信 / Profile 未含本机 UDID，见 ENVIRONMENT.md §5.2）"

echo "[dev-loop] 拉起 $BUNDLE/$ABILITY ..."
hdc shell aa start -a "$ABILITY" -b "$BUNDLE" || die "拉起失败"

echo "[dev-loop] 抓取 ${LOG_SECONDS}s 日志（grep photodelete）..."
timeout "$LOG_SECONDS" hdc hilog 2>/dev/null | grep -i photodelete || true

echo "[dev-loop] 完成。"
