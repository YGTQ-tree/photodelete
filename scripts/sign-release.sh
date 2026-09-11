#!/usr/bin/env bash
# 用 AGC 的**发布证书 + 发布 Profile** 签名 release 包（上架用）。
# 与 sign-hap.sh 的区别：那份签的是**调试**证书/Profile（只能装到自己设备），这份用于提交应用市场。
#
# 用法：./scripts/sign-release.sh
# 前置材料（放 signature/）：
#   photodeleteRelease.p12   发布密钥库（./scripts/gen-release-csr.sh 生成）
#   <AGC 下载的发布证书>.cer   AGC：证书管理 → 新增证书 → **发布证书** → 上传 photodeleteRelease.csr → 下载
#   <AGC 下载的发布 Profile>.p7b  AGC：Profile 管理 → 新增 Profile → **发布** → 绑定上面的证书（发布 Profile 不含设备列表）
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
ROOT_DIR="$(cd "$HERE/.." && pwd -P)"
# shellcheck source=./env.sh
source "$HERE/env.sh" || exit 2

SIG="$ROOT_DIR/signature"
SIGN_TOOL="${DEVECO_SDK_HOME:-}/default/openharmony/toolchains/lib/hap-sign-tool.jar"
KEYSTORE="$SIG/photodeleteRelease.p12"
PWD_FILE="$SIG/.keystore-release.pwd"
# ⚠️ 当前发布密钥库的别名是 photodelete（生成它的脚本当年沿用了调试别名）。
# 若你以后用 ./scripts/gen-release-csr.sh 重新生成（新别名 photodeleteRelease），
# 需要重新去 AGC 换证书，并在这里用 PD_KEY_ALIAS=photodeleteRelease 覆盖。
ALIAS="${PD_KEY_ALIAS:-photodelete}"
IN_HAP="$ROOT_DIR/entry/build/default/outputs/default/entry-default-unsigned.hap"
OUT_HAP="$ROOT_DIR/build-output/entry-default-release-signed.hap"

die() { echo "[release-sign] 错误：$*" >&2; exit 1; }

agc_hint() {
  cat >&2 <<'HINT'

[release-sign] 还缺发布签名材料。请先在 AGC 完成以下三步（人工）：
  1) 用户与访问 → 证书管理 → 新增证书 → 类型选「发布证书」
     → 上传  signature/photodeleteRelease.csr  → 下载 .cer 放到 signature/
  2) 我的项目 → 你的应用 → 证书、App ID 和 Profile → Profile 管理 → 新增 Profile
     → 类型选「发布」→ 绑定上面的发布证书（发布 Profile **不需要**设备列表）→ 下载 .p7b 放到 signature/
  3) 重新运行 ./scripts/sign-release.sh

参考：docs/RELEASE-SIGNING.md（含提审步骤）、docs/AGC-SUBMISSION.md（提审材料）
HINT
  exit 1
}

[[ -f "$SIGN_TOOL" ]] || die "找不到 hap-sign-tool.jar：$SIGN_TOOL（检查 DEVECO_SDK_HOME）"
[[ -f "$KEYSTORE" ]] || die "缺少 $KEYSTORE（先运行 ./scripts/gen-release-csr.sh）"
[[ -f "$PWD_FILE" ]] || die "缺少口令文件 $PWD_FILE（同上）"
CERT="$(ls "$SIG"/*elease*.cer 2>/dev/null | head -1 || true)"
PROFILE="$(ls "$SIG"/*elease*.p7b 2>/dev/null | head -1 || true)"
[[ -n "$CERT" ]] || agc_hint
[[ -n "$PROFILE" ]] || agc_hint

echo "[release-sign] 1/3 构建 release 包（buildMode=release）"
( cd "$ROOT_DIR" && hvigorw assembleHap --mode module -p product=default -p buildMode=release --no-daemon ) \
  | grep -E "BUILD (SUCCESSFUL|FAILED)" || die "release 构建失败"
[[ -f "$IN_HAP" ]] || die "找不到未签名包：$IN_HAP"

KS_PWD="$(cat "$PWD_FILE")"
mkdir -p "$ROOT_DIR/build-output"
echo "[release-sign] 2/3 用发布证书签名"
java -jar "$SIGN_TOOL" sign-app \
  -mode localSign -signAlg SHA256withECDSA \
  -keyAlias "$ALIAS" \
  -keystoreFile "$KEYSTORE" -keystorePwd "$KS_PWD" -keyPwd "$KS_PWD" \
  -appCertFile "$CERT" -profileFile "$PROFILE" \
  -inFile "$IN_HAP" -outFile "$OUT_HAP" || die "签名失败"

echo "[release-sign] 3/3 完成"
echo "[release-sign] 产物：$OUT_HAP"
echo "[release-sign] 证书：$(basename "$CERT")   Profile：$(basename "$PROFILE")"
echo "[release-sign] 下一步：把这个 HAP 上传到 AGC「版本管理」提交审核（材料见 docs/AGC-SUBMISSION.md）"

echo "[release-sign] 4/4 构建并签名 **App Pack（.app，AGC 上架用）**"
( cd "$ROOT_DIR" && hvigorw assembleApp --mode project -p product=default -p buildMode=release --no-daemon ) \
  | grep -E "BUILD (SUCCESSFUL|FAILED)" || die "App Pack 构建失败"
APP_IN="$(ls "$ROOT_DIR"/build/outputs/default/*-unsigned.app 2>/dev/null | head -1 || true)"
[[ -n "$APP_IN" ]] || die "找不到未签名 .app（build/outputs/default/）"
APP_OUT="$ROOT_DIR/build-output/PhotoDelete-release-signed.app"
java -jar "$SIGN_TOOL" sign-app \
  -mode localSign -signAlg SHA256withECDSA \
  -keyAlias "$ALIAS" \
  -keystoreFile "$KEYSTORE" -keystorePwd "$KS_PWD" -keyPwd "$KS_PWD" \
  -appCertFile "$CERT" -profileFile "$PROFILE" \
  -inFile "$APP_IN" -outFile "$APP_OUT" || die "App Pack 签名失败"
echo "[release-sign] 上架包（AGC 上传这个）：$APP_OUT"
