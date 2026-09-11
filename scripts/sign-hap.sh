#!/usr/bin/env bash
# 用 AGC 签发的调试证书与 Profile 对 HAP 签名。
#
# 前置（见 docs/ENVIRONMENT.md §5）：
#   signature/photodelete.p12  密钥库（由 ./scripts/gen-signing-csr.sh 生成）
#   signature/photodelete.cer  AGC 用 CSR 换回的调试证书
#   signature/photodelete.p7b  AGC 创建、已绑定证书与设备 UDID 的调试 Profile
#
# 用法：
#   ./scripts/sign-hap.sh [输入.hap] [输出.hap]
#   默认：build-output/entry-default-unsigned.hap → build-output/entry-default-signed.hap
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
ROOT_DIR="$(cd "$HERE/.." && pwd -P)"
# shellcheck source=./env.sh
source "$HERE/env.sh" || exit 2

SIG_DIR="$ROOT_DIR/signature"
SIGN_TOOL="${DEVECO_SDK_HOME:-}/default/openharmony/toolchains/lib/hap-sign-tool.jar"
ALIAS="${PD_KEY_ALIAS:-photodelete}"
KEYSTORE="$SIG_DIR/photodelete.p12"
CERT="$SIG_DIR/photodelete.cer"
PROFILE="$SIG_DIR/photodelete.p7b"

IN_HAP="${1:-$ROOT_DIR/build-output/entry-default-unsigned.hap}"
OUT_HAP="${2:-$ROOT_DIR/build-output/entry-default-signed.hap}"

die() { echo "[sign] 错误：$*" >&2; exit 1; }

# AGC 下载的原始文件名往往不是 photodelete.p7b（例如 photodeleteDebug.p7b），
# 所以：优先用约定的名字，找不到就退而取该目录下唯一的同类文件。
resolve_material() { # <约定路径> <后缀>
  local preferred="$1" ext="$2" found
  if [[ -f "$preferred" ]]; then printf '%s' "$preferred"; return 0; fi
  found="$(find "$SIG_DIR" -maxdepth 1 -type f -name "*${ext}" ! -name '.*' 2>/dev/null | sort | head -1)"
  if [[ -n "$found" ]]; then printf '%s' "$found"; return 0; fi
  return 1
}

CERT="$(resolve_material "$SIG_DIR/photodelete.cer" ".cer" || true)"
PROFILE="$(resolve_material "$SIG_DIR/photodelete.p7b" ".p7b" || true)"

[[ -f "$SIGN_TOOL" ]] || die "找不到 hap-sign-tool.jar：$SIGN_TOOL"
command -v java >/dev/null 2>&1 || die "缺少 java（见 ENVIRONMENT.md §1）"
[[ -f "$IN_HAP" ]] || die "输入 HAP 不存在：$IN_HAP（先跑 ./scripts/build.sh 或 hvigorw onDeviceTest）"
for f in "$KEYSTORE" "$CERT" "$PROFILE"; do
  [[ -f "$f" ]] || die "缺少签名材料 $f
  换证书链见 docs/ENVIRONMENT.md §5：
    1) ./scripts/gen-signing-csr.sh 生成 CSR
    2) AGC 上传 CSR 换 .cer，创建绑定设备 UDID 的调试 Profile 得 .p7b
    3) 把两个文件放进 $SIG_DIR/"
done

if [[ -z "${KS_PWD:-}" ]]; then
  if [[ -f "$SIG_DIR/.keystore.pwd" ]]; then
    KS_PWD="$(cat "$SIG_DIR/.keystore.pwd")"
  else
    die "缺少密钥库口令：设置 KS_PWD，或让 signature/.keystore.pwd 存在"
  fi
fi

echo "[sign] 签名 $IN_HAP"
java -jar "$SIGN_TOOL" sign-app \
  -mode localSign -signAlg SHA256withECDSA \
  -keyAlias "$ALIAS" \
  -keystoreFile "$KEYSTORE" -keystorePwd "$KS_PWD" -keyPwd "$KS_PWD" \
  -appCertFile "$CERT" -profileFile "$PROFILE" \
  -inFile "$IN_HAP" -outFile "$OUT_HAP" || die "签名失败"

echo "[sign] 完成：$OUT_HAP"
echo "[sign] 证书：$(basename "$CERT")   Profile：$(basename "$PROFILE")"

# hvigor 的 onDeviceTest 会去固定路径找**已签名**主包（否则报 00507001），
# 所以顺手把它放到 hvigor 期望的位置，让 device-test.sh 能一把跑通。
HVIGOR_OUT="$ROOT_DIR/entry/build/default/outputs/default/entry-default-signed.hap"
if [[ -d "$(dirname "$HVIGOR_OUT")" ]]; then
  cp -f "$OUT_HAP" "$HVIGOR_OUT" && echo "[sign] 已同步主包：entry/build/default/outputs/default/entry-default-signed.hap"
fi

# 设备侧测试还需要**已签名**的测试包
TEST_UNSIGNED="$ROOT_DIR/entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap"
TEST_SIGNED="$ROOT_DIR/entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap"
if [[ -f "$TEST_UNSIGNED" ]]; then
  java -jar "$SIGN_TOOL" sign-app \
    -mode localSign -signAlg SHA256withECDSA \
    -keyAlias "$ALIAS" \
    -keystoreFile "$KEYSTORE" -keystorePwd "$KS_PWD" -keyPwd "$KS_PWD" \
    -appCertFile "$CERT" -profileFile "$PROFILE" \
    -inFile "$TEST_UNSIGNED" -outFile "$TEST_SIGNED" >/dev/null 2>&1 \
    && echo "[sign] 已签名测试包：entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap" \
    || echo "[sign] 注意：测试包签名失败（尚未构建过 ohosTest 时属正常）"
fi
ls -la "$OUT_HAP"
echo "[sign] 下一步：hdc install -r '$OUT_HAP'"
