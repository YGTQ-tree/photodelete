#!/usr/bin/env bash
# 构建 HAP。
#
# 路径策略（见 docs/ENVIRONMENT.md §10）：
#   - 工程路径合规（纯 ASCII 允许字符）→ **原地构建**（2026-09-11 起为默认）
#   - 工程路径含中文等非法字符        → 复制到 ASCII 镜像构建，再把产物拷回
# hvigor 用 process.cwd() 做这个校验，只允许 [a-zA-Z0-9-_.()@ 空格]。
#
# 用法：
#   ./scripts/build.sh                 # assembleHap（debug）
#   ./scripts/build.sh --mode release
#   ./scripts/build.sh --task assembleApp
set -uo pipefail

TASK="assembleHap"
BUILD_MODE="debug"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="${2:-assembleHap}"; shift 2 ;;
    --mode) BUILD_MODE="${2:-debug}"; shift 2 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "$0")" && pwd -P)"
# 用 pwd -P 取物理路径：若工程目录本身是符号链接，要按真实路径判断是否合规
ROOT_DIR="$(cd "$HERE/.." && pwd -P)"

# shellcheck source=./env.sh
source "$HERE/env.sh" || exit 2

path_ok() { ! printf '%s' "$1" | LC_ALL=C grep -qE '[^a-zA-Z0-9/_.()@ -]'; }

if path_ok "$ROOT_DIR"; then
  BUILD_DIR="$ROOT_DIR"
  echo "[build] 原地构建：$BUILD_DIR"
else
  MIRROR="${PD_MIRROR:-$HOME/pd-build/PhotoDelete}"
  if ! path_ok "$MIRROR"; then
    echo "[build] 镜像路径也含非法字符：$MIRROR" >&2
    echo "[build] 允许：字母 数字 / - _ . ( ) 空格 @（见 docs/ENVIRONMENT.md §10）" >&2
    exit 2
  fi
  echo "[build] 工程路径含非法字符（hvigor 会拒绝）：$ROOT_DIR"
  echo "[build] 退回复制镜像：$MIRROR"
  rm -rf "$MIRROR"
  mkdir -p "$MIRROR"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude 'build' --exclude '.hvigor' --exclude 'oh_modules' \
      --exclude '.git' --exclude 'build-output' \
      "$ROOT_DIR"/ "$MIRROR"/
  else
    for item in AppScope entry hvigor tools scripts docs tasks \
                build-profile.json5 hvigorfile.ts oh-package.json5 AGENTS.md; do
      [[ -e "$ROOT_DIR/$item" ]] && cp -a "$ROOT_DIR/$item" "$MIRROR"/
    done
  fi
  BUILD_DIR="$MIRROR"
fi

cd "$BUILD_DIR" || exit 2

if [[ -f oh-package.json5 ]]; then
  echo "[build] ohpm install ..."
  ohpm install 2>&1 | tail -5
fi

echo "[build] hvigorw $TASK (buildMode=$BUILD_MODE) ..."
hvigorw "$TASK" --mode module -p product=default -p buildMode="$BUILD_MODE" --no-daemon
status=$?

# 产物回收到 build-output/（原地构建时同样执行，保证产物路径稳定）
mkdir -p "$ROOT_DIR/build-output"
copied=0
while IFS= read -r f; do
  cp -f "$f" "$ROOT_DIR/build-output/" && copied=$((copied + 1))
done < <(find "$BUILD_DIR" -type f \( -name '*.hap' -o -name '*.app' -o -name '*.har' \) 2>/dev/null)

echo "[build] 产物拷回 $copied 个 → $ROOT_DIR/build-output/"
ls -la "$ROOT_DIR/build-output/" 2>/dev/null | tail -4
echo "[build] 构建目录：$BUILD_DIR"
echo "[build] hvigor 退出码=$status"
exit "$status"
