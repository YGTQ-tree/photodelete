#!/usr/bin/env bash
# PhotoDelete 工具链环境变量。用法： source scripts/env.sh
#
# 自动探测华为 Command Line Tools（默认装在 ~/HarmonyOS_dev 下）。
# 可用 PD_TOOLS_ROOT 覆盖，例如：
#   PD_TOOLS_ROOT=/opt/command-line-tools source scripts/env.sh

_pd_detect_root() {
  if [[ -n "${PD_TOOLS_ROOT:-}" ]]; then
    echo "$PD_TOOLS_ROOT"
    return
  fi
  local candidate
  for candidate in "$HOME"/HarmonyOS_dev/commandline-tools-linux-*/command-line-tools; do
    if [[ -d "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done
}

PD_TOOLS_ROOT="$(_pd_detect_root)"

if [[ -z "$PD_TOOLS_ROOT" || ! -d "$PD_TOOLS_ROOT" ]]; then
  echo "[env.sh] 未找到 Command Line Tools；请设置 PD_TOOLS_ROOT（见 docs/ENVIRONMENT.md §2）" >&2
else
  export PD_TOOLS_ROOT
  export DEVECO_SDK_HOME="$PD_TOOLS_ROOT/sdk"
  case ":$PATH:" in
    *":$PD_TOOLS_ROOT/bin:"*) ;;
    *) PATH="$PD_TOOLS_ROOT/bin:$PD_TOOLS_ROOT/ohpm/bin:$PD_TOOLS_ROOT/hvigor/bin:$PATH" ;;
  esac
  if [[ -d "$DEVECO_SDK_HOME/default/openharmony/toolchains" ]]; then
    case ":$PATH:" in
      *"openharmony/toolchains:"*) ;;
      *) PATH="$DEVECO_SDK_HOME/default/openharmony/toolchains:$PATH" ;;
    esac
  fi
  export PATH
fi

# JDK：hvigor 的 PackageHap / hap-sign-tool 都需要 java（系统无 java 时用便携 JDK）
if ! command -v java >/dev/null 2>&1; then
  for _jdk in "$HOME"/HarmonyOS_dev/jdk-*; do
    if [[ -x "$_jdk/bin/java" ]]; then
      export JAVA_HOME="$_jdk"
      PATH="$JAVA_HOME/bin:$PATH"
      break
    fi
  done
fi
unset _jdk

# hvigor 对 Node 版本敏感：若 hvigor 报版本错误，用 nvm 切到 20
export PD_BUNDLE="${PD_BUNDLE:-com.dsh.photodelete}"
export PD_ABILITY="${PD_ABILITY:-EntryAbility}"
