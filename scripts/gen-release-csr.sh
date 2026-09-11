#!/usr/bin/env bash
# 生成应用签名密钥对与 CSR（证书签名请求）—— 本步骤**不需要设备**，可与 AGC 操作并行。
#
# 产出的 CSR 要上传到 AGC 换取「调试证书」(.cer)；随后在 AGC 创建绑定该证书与
# 设备 UDID 的「调试 Profile」(.p7b)。完整流程见 docs/ENVIRONMENT.md §5。
#
# 用法：
#   KS_PWD='你的口令' ./scripts/gen-signing-csr.sh
#   # 不设 KS_PWD 时会随机生成并写入 signature/.keystore-release.pwd（权限 600，已被 .gitignore 忽略）
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
ROOT_DIR="$(cd "$HERE/.." && pwd -P)"
# shellcheck source=./env.sh
source "$HERE/env.sh" || exit 2

TOOL_LIB="${DEVECO_SDK_HOME:-}/default/openharmony/toolchains/lib"
SIGN_TOOL="$TOOL_LIB/hap-sign-tool.jar"
[[ -f "$SIGN_TOOL" ]] || { echo "[csr-rel] 找不到 hap-sign-tool.jar：$SIGN_TOOL" >&2; exit 2; }
command -v java >/dev/null 2>&1 || { echo "[csr-rel] 缺少 java（见 ENVIRONMENT.md §1）" >&2; exit 2; }

SIG_DIR="$ROOT_DIR/signature"
ALIAS="${PD_KEY_ALIAS:-photodelete}"
KEYSTORE="$SIG_DIR/photodeleteRelease.p12"
PWD_FILE="$SIG_DIR/.keystore-release.pwd"
CSR="$SIG_DIR/photodeleteRelease.csr"
SUBJECT="${PD_CSR_SUBJECT:-C=CN,O=PhotoDelete,OU=Dev,CN=PhotoDelete Debug}"

mkdir -p "$SIG_DIR"

if [[ -z "${KS_PWD:-}" ]]; then
  if [[ -f "$PWD_FILE" ]]; then
    KS_PWD="$(cat "$PWD_FILE")"
    echo "[csr-rel] 复用已有口令：$PWD_FILE"
  else
    KS_PWD="$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 20)"
    printf '%s' "$KS_PWD" > "$PWD_FILE"
    chmod 600 "$PWD_FILE"
    echo "[csr-rel] 已随机生成密钥库口令并写入 $PWD_FILE（权限 600，勿入库）"
  fi
fi

if [[ -f "$KEYSTORE" ]]; then
  echo "[csr-rel] 密钥库已存在，跳过生成：$KEYSTORE"
else
  echo "[csr-rel] 生成密钥对（ECC NIST-P-256）..."
  java -jar "$SIGN_TOOL" generate-keypair \
    -keyAlias "$ALIAS" -keyPwd "$KS_PWD" \
    -keyAlg ECC -keySize NIST-P-256 \
    -keystoreFile "$KEYSTORE" -keystorePwd "$KS_PWD" || exit 1
fi

echo "[csr-rel] 生成 CSR..."
java -jar "$SIGN_TOOL" generate-csr \
  -keyAlias "$ALIAS" -keyPwd "$KS_PWD" \
  -subject "$SUBJECT" -signAlg SHA256withECDSA \
  -keystoreFile "$KEYSTORE" -keystorePwd "$KS_PWD" \
  -outFile "$CSR" || exit 1

echo
echo "[csr-rel] 完成。产物："
ls -la "$KEYSTORE" "$CSR" 2>/dev/null
echo
echo "下一步（人工，AGC 控制台）："
echo "  1) 用户与访问 → 证书管理 → 新增证书 → 类型「调试证书」→ 上传 $CSR → 下载 .cer"
echo "  2) 设备管理 → 添加设备（需要设备 UDID：hdc shell bm get --udid）"
echo "  3) 我的项目 → 应用 → 证书、App ID 和 Profile → 新增 Profile（调试）→ 绑定证书+设备 → 下载 .p7b"
echo "  把 .cer 与 .p7b 放到 $SIG_DIR/ 后运行：./scripts/sign-hap.sh"
