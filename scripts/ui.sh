#!/usr/bin/env bash
# 用设备端 `uitest` 驱动真机 UI：导出布局 / 按文本定位 / 点击。
# 用途：把端到端验收（docs/ACCEPTANCE-REPORT.md 的 A1–A10）从「人工点」变成「脚本点」。
#
# 用法：
#   source scripts/ui.sh
#   ui_texts                 # 打印当前屏幕所有文本（看状态）
#   ui_click "拍照"          # 按包含该文本的控件中心点击
#   ui_dump /tmp/x.json     # 导出布局供分析
#
# 依赖：设备已连（hdc list targets 非空）、应用在前台。设备端无 acm，权限需人工授过一次。

ui_dump() { # $1 = 本地保存路径
  local out="${1:-/tmp/pd-ui.json}"
  hdc shell "uitest dumpLayout -p /data/local/tmp/pd-ui.json" >/dev/null 2>&1
  hdc file recv /data/local/tmp/pd-ui.json "$out" >/dev/null 2>&1
}

ui_texts() { # [$1 = 布局文件，缺省则现场导出]
  local f="${1:-}"
  if [[ -z "$f" ]]; then
    f="$(mktemp)"
    ui_dump "$f"
  fi
  python3 - "$f" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
def walk(n):
    t=(n.get('attributes',{}).get('text') or '').strip()
    if t: print("  ",t[:110])
    for c in n.get('children',[]) or []: walk(c)
walk(d)
PY
}

ui_find() { # $1 = 布局文件, $2 = 文本（优先精确匹配，其次子串）→ 输出 "x y"
  python3 - "$1" "$2" <<'PY'
import json,re,sys
layout,needle=sys.argv[1],sys.argv[2]
d=json.load(open(layout))
exact=None; partial=None
def centre(a):
    m=re.findall(r'-?\d+', a.get('bounds') or '')
    if len(m)>=4:
        x1,y1,x2,y2=map(int,m[:4])
        return ((x1+x2)//2,(y1+y2)//2)
    return None
def walk(n):
    global exact,partial
    a=n.get('attributes',{})
    t=(a.get('text') or '')
    if t==needle and exact is None:
        c=centre(a)
        if c: exact=c
    elif needle in t and partial is None:
        c=centre(a)
        if c: partial=c
    for c2 in n.get('children',[]) or []: walk(c2)
walk(d)
hit = exact or partial
if hit: print(f"{hit[0]} {hit[1]}")
else: sys.exit(1)
PY
}

ui_click() { # $1 = 文本子串（支持多个备选，用 | 分隔）
  local tmp xy
  tmp="$(mktemp)"
  ui_dump "$tmp"
  local IFS='|'
  for want in $1; do
    if xy="$(ui_find "$tmp" "$want")"; then
      rm -f "$tmp"
      echo "[ui] 点击「$want」@ $xy"
      hdc shell "uitest uiInput click $xy" >/dev/null 2>&1
      sleep 1
      return 0
    fi
  done
  rm -f "$tmp"
  echo "[ui] 找不到控件：$1" >&2
  return 1
}

ui_wait_text() { # $1 = 文本子串, $2 = 超时秒
  local want="$1" timeout="${2:-15}" i=0 tmp
  while (( i < timeout )); do
    tmp="$(mktemp)"
    ui_dump "$tmp"
    if ui_find "$tmp" "$want" >/dev/null 2>&1; then
      rm -f "$tmp"
      return 0
    fi
    rm -f "$tmp"
    sleep 1
    i=$((i+1))
  done
  echo "[ui] 等待超时：$want" >&2
  return 1
}
