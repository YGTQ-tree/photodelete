#!/usr/bin/env bash
# PhotoDelete 环境自检（G0-A 第 2 步）
# 用法：./scripts/check-env.sh [--json]
# 退出码：0 = 必需项齐全；1 = 有必需项缺失
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
# 先激活工具链（CLI Tools + 便携 JDK），否则会把已装好的工具误报为缺失
# shellcheck source=./env.sh
source "$HERE/env.sh" >/dev/null 2>&1 || true

JSON=0
[[ "${1:-}" == "--json" ]] && JSON=1

pass=(); skip=(); fail=()

check_cmd() { # name required
  local name="$1" required="$2" path
  if path="$(command -v "$name" 2>/dev/null)"; then
    pass+=("$name: $path")
  elif [[ "$required" == "required" ]]; then
    fail+=("$name: 未安装（必需）")
  else
    skip+=("$name: 未安装（可选）")
  fi
}

check_cmd java required
check_cmd node required
check_cmd ohpm required
check_cmd hvigorw required
check_cmd hdc required
check_cmd codelinter optional

if [[ -n "${DEVECO_SDK_HOME:-}" && -d "${DEVECO_SDK_HOME}" ]]; then
  pass+=("DEVECO_SDK_HOME: $DEVECO_SDK_HOME")
else
  fail+=("DEVECO_SDK_HOME: 未设置或目录不存在")
fi

# Node 版本：hvigor 对版本敏感
if command -v node >/dev/null 2>&1; then
  node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  if [[ "$node_major" -ge 20 && "$node_major" -le 22 ]]; then
    pass+=("node 版本: v$node_major（在 hvigor 支持区间）")
  else
    skip+=("node 版本: v$node_major（若 hvigor 报版本错误，执行 nvm use 20）")
  fi
fi

# 真机（可选，但 T00 的 G0-A-3 需要）
# 注意：hdc 在无设备时字面输出 "[Empty]"，必须过滤掉，否则会被误判为已连上设备
if command -v hdc >/dev/null 2>&1; then
  device_line="$(hdc list targets 2>/dev/null | grep -v '\[Empty\]' | grep -v '^[[:space:]]*$' | head -3 || true)"
  if [[ -n "$device_line" ]]; then
    pass+=("hdc 设备: $(echo "$device_line" | tr '\n' ' ')")
  else
    skip+=("hdc 设备: 未发现 —— 先在平板打开「USB 调试」并授权；判据见 ENVIRONMENT.md §4（接口若是 MTP 说明调试未开）")
  fi
fi

# 领域单测回路（不依赖 SDK）：必须走 domain-test.sh，它注册了无后缀导入的解析钩子
if [[ -d tools/domain-tests ]]; then
  if "$HERE/domain-test.sh" >/tmp/pd-l1.log 2>&1; then
    pass+=("L1 领域单测: 通过（$(grep -E 'tests [0-9]+|pass [0-9]+' /tmp/pd-l1.log | tr -d '\r' | tr '\n' ' ')）")
  else
    fail+=("L1 领域单测: 失败（详见 /tmp/pd-l1.log）")
  fi
else
  skip+=("L1 领域单测: tools/domain-tests 尚未创建（T01 交付）")
fi

if [[ "$JSON" == "1" ]]; then
  printf '{"pass":%d,"skip":%d,"fail":%d}\n' "${#pass[@]}" "${#skip[@]}" "${#fail[@]}"
else
  echo "==== PhotoDelete 环境自检 ===="
  for l in "${pass[@]:-}"; do [[ -n "$l" ]] && echo "  [ OK ] $l"; done
  for l in "${skip[@]:-}"; do [[ -n "$l" ]] && echo "  [SKIP] $l"; done
  for l in "${fail[@]:-}"; do [[ -n "$l" ]] && echo "  [FAIL] $l"; done
  echo "-------------------------------"
  echo "通过 ${#pass[@]} / 跳过 ${#skip[@]} / 失败 ${#fail[@]}"
fi

[[ "${#fail[@]}" -eq 0 ]] || exit 1
exit 0
