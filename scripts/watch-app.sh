#!/usr/bin/env bash
# 看门狗：应用被**系统静默卸载**时自动重装，让它始终可用。
#
# 为什么需要（权宜之计，不是根因修复）：真机实测该应用会被设备侧静默卸载
# （已发生 4 次：11:40 / 11:54:20 / 12:15:24 / 12:54:00，走 BMS 卸载接口，
#  `scripts/` 里没有任何 uninstall，用户也未手动卸载）。根因未定位，
# 详见 docs/ENVIRONMENT.md §8。本脚本保证「被卸载后 20 秒内自动回来」。
#
# 代价：重装会清空应用数据与权限（实测行为），所以沙箱里的照片与待删除记录会没。
#
# 用法：./scripts/watch-app.sh [轮询秒数，默认 20]
# 停止：Ctrl-C（或作为后台任务时用 job_kill）
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
ROOT_DIR="$(cd "$HERE/.." && pwd -P)"
# shellcheck source=./env.sh
source "$HERE/env.sh" || exit 2

INTERVAL="${1:-20}"
BUNDLE="${PD_BUNDLE:-com.dsh.photodelete}"
ABILITY="${PD_ABILITY:-EntryAbility}"
SIGNED_HAP="$ROOT_DIR/build-output/entry-default-signed.hap"

installed() {
  hdc shell "bm dump -n $BUNDLE" 2>/dev/null | grep -q '"appId"'
}

grant_camera() {
  # 重装会重置权限；自动把相机授权点回来（先等弹窗动画结束再 dump，见 ENVIRONMENT §8）
  hdc shell aa start -a "$ABILITY" -b "$BUNDLE" >/dev/null 2>&1
  sleep 6
  hdc shell "uitest uiInput click 1400 1690" >/dev/null 2>&1   # 首页「打开相机（拍照）」大致位置
  sleep 4
  local tmp xy
  tmp="$(mktemp)"
  hdc shell "uitest dumpLayout -p /data/local/tmp/pd-watch.json" >/dev/null 2>&1
  hdc file recv /data/local/tmp/pd-watch.json "$tmp" >/dev/null 2>&1
  xy="$(python3 - "$tmp" <<'PY' 2>/dev/null || true
import json,re,sys
d=json.load(open(sys.argv[1]))
def walk(n):
    a=n.get('attributes',{}); t=(a.get('text') or '').strip()
    if t=='允许':
        m=re.findall(r'-?\d+', a.get('bounds') or '')
        if len(m)>=4:
            print((int(m[0])+int(m[2]))//2,(int(m[1])+int(m[3]))//2)
    for c in n.get('children',[]) or []: walk(c)
walk(d)
PY
)"
  rm -f "$tmp"
  if [[ -n "$xy" ]]; then
    echo "[watch] 自动授权相机 @ $xy"
    hdc shell "uitest uiInput click $xy" >/dev/null 2>&1
    sleep 3
  fi
  # 回首页，留一个干净状态
  hdc shell aa force-stop "$BUNDLE" >/dev/null 2>&1
  sleep 1
  hdc shell aa start -a "$ABILITY" -b "$BUNDLE" >/dev/null 2>&1
}

[[ -f "$SIGNED_HAP" ]] || { echo "[watch] 错误：缺少 $SIGNED_HAP，先跑 ./scripts/build.sh && ./scripts/sign-hap.sh" >&2; exit 2; }

echo "[watch] 开始监视 $BUNDLE（每 ${INTERVAL}s 一次）。被卸载会自动重装。"
ROUND=0
while true; do
  ROUND=$((ROUND + 1))
  if installed; then
    if [[ $ROUND -eq 1 ]]; then echo "[watch] $(date '+%H:%M:%S') 应用在。"; fi
  else
    echo "[watch] $(date '+%H:%M:%S') ⚠️ 检测到应用被卸载，正在重装…"
    hdc install -r "$SIGNED_HAP" 2>&1 | tail -1
    grant_camera
    if installed; then
      echo "[watch] $(date '+%H:%M:%S') 已恢复。"
    else
      echo "[watch] $(date '+%H:%M:%S') 重装后仍查不到，下一轮再试。"
    fi
  fi
  sleep "$INTERVAL"
done
