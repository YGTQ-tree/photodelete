#!/usr/bin/env bash
# 主机侧 L1 领域测试的统一跑法。
# 为什么需要 loader：领域层用 ArkTS 约定的「无后缀相对导入」，
# 而 Node ESM 要求显式后缀；loader.mjs 注册解析钩子补 .ts。
# 用法： ./scripts/domain-test.sh
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

if [[ ! -d tools/domain-tests ]]; then
  echo "[domain-test] 缺 tools/domain-tests（T01 交付）" >&2
  exit 2
fi

mapfile -t FILES < <(ls tools/domain-tests/*.test.ts 2>/dev/null | sort)
if [[ "${#FILES[@]}" -eq 0 ]]; then
  echo "[domain-test] tools/domain-tests 下没有 *.test.ts" >&2
  exit 2
fi

exec node \
  --disable-warning=MODULE_TYPELESS_PACKAGE_JSON \
  --disable-warning=ExperimentalWarning \
  --import ./tools/domain-tests/loader.mjs \
  --test "${FILES[@]}"
