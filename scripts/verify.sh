#!/usr/bin/env bash
# PhotoDelete 分层验证
# 用法：./scripts/verify.sh [--with-build] [--with-device]
#   --with-build  额外跑 HAP 构建（经 ASCII 镜像，见 scripts/build.sh）
#   --with-device 额外跑设备侧契约测试（需要真机与签名）
# 退出码：0 = 无 FAIL（SKIP 不算失败，但必须写明原因）
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2
HERE="$(pwd)"

WITH_BUILD=0
WITH_DEVICE=0
for arg in "$@"; do
  case "$arg" in
    --with-build)  WITH_BUILD=1 ;;
    --with-device) WITH_DEVICE=1 ;;
    *) echo "未知参数：$arg"; exit 2 ;;
  esac
done

# shellcheck source=./env.sh
source "$HERE/scripts/env.sh" >/dev/null 2>&1 || true

declare -a L_NAME=() L_STATE=() L_DETAIL=()
record() { L_NAME+=("$1"); L_STATE+=("$2"); L_DETAIL+=("$3"); }

# ---------- 1. 工程配置合规（快，永远跑） ----------
if [[ -f build-profile.json5 ]]; then
  if out="$(node scripts/check-profile.mjs 2>&1)"; then
    record "工程配置合规" "PASS" "$(echo "$out" | tail -1)"
  else
    echo "$out"
    record "工程配置合规" "FAIL" "见上方逐字段报告"
  fi
else
  record "工程配置合规" "SKIP" "缺 build-profile.json5（T00 交付）"
fi

# ---------- 2. L1 领域单测（永远跑，不需要 SDK/真机） ----------
if [[ -d tools/domain-tests ]]; then
  if out="$(./scripts/domain-test.sh 2>&1)"; then
    summary="$(echo "$out" | grep -E 'tests [0-9]+|pass [0-9]+|fail [0-9]+' | tr -d '\r' | tr '\n' ' ')"
    record "L1 领域单测" "PASS" "${summary:-通过}"
  else
    echo "$out" | tail -30
    record "L1 领域单测" "FAIL" "详见上方输出"
  fi
else
  record "L1 领域单测" "SKIP" "缺 tools/domain-tests（T01 交付）"
fi

# ---------- 3. 领域层语法合规（禁鸿蒙依赖 / 禁不可擦除语法） ----------
# 只匹配真正的 import/声明语句，不匹配注释里的说明文字（曾经的假阳性来源）。
# 为什么必须手工 grep：实测 codelinter（含自带规则集）与 ArkTS 编译器都不拦
# `any` 之类违规，这道纪律没有被工具兜底。
if [[ -d entry/src/main/ets/domain ]]; then
  viol_import="$(grep -rnE '^[[:space:]]*(import|export)[^;]*(@kit\.|@ohos\.)' \
      entry/src/main/ets/domain entry/src/main/ets/common 2>/dev/null || true)"
  viol_syntax="$(grep -rnE '^[[:space:]]*(export[[:space:]]+)?(enum|namespace)[[:space:]]' \
      entry/src/main/ets/domain entry/src/main/ets/common 2>/dev/null || true)"
  if [[ -z "$viol_import" && -z "$viol_syntax" ]]; then
    record "领域层语法合规" "PASS" "无 @kit/@ohos 导入、无 enum/namespace 声明"
  else
    [[ -n "$viol_import" ]] && echo "$viol_import"
    [[ -n "$viol_syntax" ]] && echo "$viol_syntax"
    record "领域层语法合规" "FAIL" "见上方违规行"
  fi
else
  record "领域层语法合规" "SKIP" "缺 entry/src/main/ets/domain（T01 交付）"
fi

# ---------- 4. 静态检查 ----------
# 实测（tools 6.0.2.670）：默认规则与自带 eslintAgent/config/code-linter.json
# 扫描含 `any` + 无类型对象字面量的 .ets 探针，均报 "No defects found" 且退出码 0。
# 因此这道检查目前**不构成有效门禁**，如实记 SKIP 而不是 PASS。
if command -v codelinter >/dev/null 2>&1; then
  record "codelinter" "SKIP" "工具可用但规则集无牙齿（探针实测漏报 any），待接入规则集后启用"
else
  record "codelinter" "SKIP" "未安装"
fi

# ---------- 5. HAP 构建 ----------
if [[ "$WITH_BUILD" == "1" ]]; then
  if command -v hvigorw >/dev/null 2>&1 && [[ -n "${DEVECO_SDK_HOME:-}" ]]; then
    if out="$(./scripts/build.sh 2>&1)"; then
      record "HAP 构建" "PASS" "$(echo "$out" | grep -E 'BUILD SUCCESSFUL|产物拷回' | tr '\n' ' ')"
    else
      echo "$out" | tail -30
      record "HAP 构建" "FAIL" "见上方输出"
    fi
  else
    record "HAP 构建" "SKIP" "缺 hvigorw 或 DEVECO_SDK_HOME（T00 门禁 G0-A）"
  fi

  # L2 测试包的**编译**检查：不需要设备（脚本把设备阶段的失败视为预期）。
  # 没有这道检查时，ohosTest 源码的类型错误要等到能装机才暴露。
  if [[ -d entry/src/ohosTest ]] && command -v hvigorw >/dev/null 2>&1; then
    if out="$(./scripts/compile-test-hap.sh 2>&1)"; then
      record "L2 测试包编译" "PASS" "$(echo "$out" | grep -E '构建成功' | head -1)"
    else
      echo "$out" | tail -20
      record "L2 测试包编译" "FAIL" "见上方输出"
    fi
  else
    record "L2 测试包编译" "SKIP" "无 entry/src/ohosTest 或缺 hvigorw"
  fi
else
  record "HAP 构建" "SKIP" "未加 --with-build"
fi

# ---------- 6. 设备侧测试 ----------
if [[ "$WITH_DEVICE" == "1" ]]; then
  # 注意：hdc 无设备时字面输出 "[Empty]"，必须过滤，否则会误判为已连上
  if command -v hdc >/dev/null 2>&1 \
     && hdc list targets 2>/dev/null | grep -qv '\[Empty\]' \
     && command -v hvigorw >/dev/null 2>&1; then
    if out="$(./scripts/device-test.sh 2>&1)"; then
      record "L2 设备契约测试" "PASS" "$(echo "$out" | grep -iE 'pass|fail' | tail -2 | tr '\n' ' ')"
    else
      echo "$out" | tail -30
      record "L2 设备契约测试" "FAIL" "见上方输出"
    fi
  else
    record "L2 设备契约测试" "SKIP" "无设备：先在平板开 USB 调试并授权（ENVIRONMENT.md §4）"
  fi
else
  record "L2 设备契约测试" "SKIP" "未加 --with-device"
fi

# ---------- 汇总 ----------
echo
echo "==== 验证结果 ===="
fail=0
for i in "${!L_NAME[@]}"; do
  printf '  [%-4s] %-16s %s\n' "${L_STATE[$i]}" "${L_NAME[$i]}" "${L_DETAIL[$i]}"
  [[ "${L_STATE[$i]}" == "FAIL" ]] && fail=$((fail + 1))
done
echo "=================="
if [[ "$fail" -gt 0 ]]; then
  echo "结论：$fail 项失败。SKIP 不算通过——请在任务卡写明原因与补做计划。"
  exit 1
fi
echo "结论：无失败项。SKIP 项须在任务卡中写明原因。"
exit 0
