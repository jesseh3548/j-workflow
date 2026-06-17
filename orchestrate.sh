#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$SCRIPT_DIR/bin/workflow-state" ]]; then
    # Source checkout layout: orchestrate.sh at repo root, helpers in ./bin.
    BIN_DIR="$SCRIPT_DIR/bin"
elif [[ -x "$SCRIPT_DIR/workflow-state" ]]; then
    # Installed layout: orchestrate.sh and helper scripts live in the same bin dir.
    BIN_DIR="$SCRIPT_DIR"
else
    echo "Cannot find workflow helper scripts near $SCRIPT_DIR" >&2
    exit 1
fi

# ============================================================
# Multi-Agent Development Orchestrator
# 多 Agent 协同开发编排器
#
# Usage:
#   orchestrate.sh --project <project_dir> --requirement <requirement_file> [options]
#   orchestrate.sh --config <config_file>
#
# Examples:
#   orchestrate.sh --project ~/code/card-center --requirement req.md
#   orchestrate.sh --project ~/code/card-center --requirement req.md --skip explore
#   orchestrate.sh --project ~/code/card-center --requirement req.md --auto
# ============================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Defaults
PROJECT_DIR=""
REQUIREMENT_FILE=""
EXPLORE_IDEA=""
TASK_NAME=""
WORKSPACE_DIR=""
CONFIG_FILE=""
PROVIDER=""
PROVIDER_CLI=""
PROVIDER_FROM_CLI=false
MODEL="claude-sonnet-4-6"
MODEL_FROM_USER=false
SKIP_PHASES=()
AUTO_MODE=false
RESUME_MODE=false
GHOSTTY_WINDOW_ID=""

# Phase breakpoints (default: semi-auto)
BP_AFTER_EXPLORE=false
BP_AFTER_DESIGN=true
BP_AFTER_REVIEW=true
BP_AFTER_IMPLEMENT=false
BP_AFTER_REVIEW_CODE=true

# Phase toggles (default: all enabled)
PHASE_EXPLORE=false  # off by default, enable with --explore
PHASE_DESIGN=true
PHASE_REVIEW_PLAN=true
PHASE_IMPLEMENT=true
PHASE_REVIEW_CODE=true

# ============================================================
# Helper functions
# ============================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[DONE]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_phase() {
    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  Phase $1: $2${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo ""
}

wait_for_user() {
    if [[ "$AUTO_MODE" == true ]]; then
        return 0
    fi
    echo ""
    echo -e "${YELLOW}[BREAKPOINT]${NC} $1"
    echo -e "  输出文件: ${BOLD}$2${NC}"
    echo ""
    read -rp "  按 Enter 继续下一阶段, 输入 'q' 退出, 输入 's' 跳过下一阶段: " choice
    case "$choice" in
        q|Q) echo "已退出。"; exit 0 ;;
        s|S) return 1 ;;  # signal skip
        *) return 0 ;;
    esac
}

detect_provider() {
    provider_bin_var() {
        case "$1" in
            claude) echo "CLAUDE_BIN" ;;
            codex) echo "CODEX_BIN" ;;
            *) echo "PROVIDER_BIN" ;;
        esac
    }

    resolve_provider_cli() {
        local provider_name="$1"
        local binary_name="$provider_name"
        local override=""
        local candidate=""

        case "$provider_name" in
            claude) override="${CLAUDE_BIN:-}" ;;
            codex) override="${CODEX_BIN:-}" ;;
            *) return 1 ;;
        esac

        if [[ -n "$override" ]]; then
            if [[ -x "$override" ]]; then
                echo "$override"
                return 0
            fi
            echo "[ERROR] ${provider_name} CLI override is not executable: $override" >&2
            return 1
        fi

        candidate="$(type -P "$binary_name" 2>/dev/null || true)"
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi

        for candidate in \
            "/opt/homebrew/bin/$binary_name" \
            "/usr/local/bin/$binary_name" \
            "$HOME/.local/bin/$binary_name" \
            "$HOME/.npm-global/bin/$binary_name"; do
            if [[ -x "$candidate" ]]; then
                echo "$candidate"
                return 0
            fi
        done

        return 1
    }

    if [[ -n "$PROVIDER" ]]; then
        case "$PROVIDER" in
            claude|codex)
                PROVIDER_CLI="$(resolve_provider_cli "$PROVIDER" || true)"
                if [[ -z "$PROVIDER_CLI" ]]; then
                    log_error "无法找到 $PROVIDER CLI。可设置 $(provider_bin_var "$PROVIDER")=/path/to/$PROVIDER 后重试"
                    exit 1
                fi
                return 0
                ;;
            *) log_error "未知 provider: $PROVIDER（仅支持 claude/codex）"; exit 1 ;;
        esac
    fi

    if printenv | grep -q '^CODEX_' && PROVIDER_CLI="$(resolve_provider_cli codex || true)" && [[ -n "$PROVIDER_CLI" ]]; then
        PROVIDER="codex"
    elif PROVIDER_CLI="$(resolve_provider_cli claude || true)" && [[ -n "$PROVIDER_CLI" ]]; then
        PROVIDER="claude"
    elif PROVIDER_CLI="$(resolve_provider_cli codex || true)" && [[ -n "$PROVIDER_CLI" ]]; then
        PROVIDER="codex"
    else
        log_error "无法找到可用 agent CLI：需要 claude 或 codex"
        log_error "如果 CLI 不在非交互 shell 的 PATH 中，可设置 CLAUDE_BIN 或 CODEX_BIN 为绝对路径"
        exit 1
    fi
}

detect_codex_default_model() {
    local config_file="${CODEX_HOME:-$HOME/.codex}/config.toml"
    if [[ -f "$config_file" ]]; then
        local configured_model
        configured_model="$(awk -F= '/^[[:space:]]*model[[:space:]]*=/{ gsub(/[[:space:]"]/, "", $2); print $2; exit }' "$config_file")"
        if [[ -n "$configured_model" ]]; then
            echo "$configured_model"
            return 0
        fi
    fi
    echo "gpt-5.5"
}

detect_ghostty_window() {
    if [[ -n "$GHOSTTY_WINDOW_ID" ]]; then
        return
    fi
    if ! command -v osascript >/dev/null 2>&1; then
        return
    fi
    GHOSTTY_WINDOW_ID="$(osascript -e '
        tell application "Ghostty"
            if (count of windows) > 0 then
                return id of window 1
            else
                return "not_found"
            end if
        end tell
    ' 2>/dev/null || echo "not_found")"
    if [[ "$GHOSTTY_WINDOW_ID" == "not_found" ]]; then
        GHOSTTY_WINDOW_ID=""
        log_warn "无法检测 Ghostty 当前窗口，新阶段可能 fallback 到新窗口"
    fi
}

state_cmd() {
    "$BIN_DIR/workflow-state" "$@"
}

get_phase_session_id() {
    local phase_name="$1"
    state_cmd get-session-id --file "$STATE_FILE" --phase "$phase_name" 2>/dev/null || true
}

parse_config() {
    local config_file="$1"
    if [[ ! -f "$config_file" ]]; then
        log_error "配置文件不存在: $config_file"
        exit 1
    fi

    # Simple YAML parsing (key: value)
    while IFS=': ' read -r key value; do
        # Skip comments and empty lines
        [[ -z "$key" || "$key" == \#* ]] && continue
        # Trim whitespace
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        case "$key" in
            project_dir) PROJECT_DIR="$value" ;;
            workspace_dir) WORKSPACE_DIR="$value" ;;
            provider)
                if [[ "$PROVIDER_FROM_CLI" != true ]]; then
                    PROVIDER="$value"
                fi
                ;;
            model) MODEL="$value"; MODEL_FROM_USER=true ;;
            explore) PHASE_EXPLORE="$value" ;;
            design) PHASE_DESIGN="$value" ;;
            review_plan) PHASE_REVIEW_PLAN="$value" ;;
            implement) PHASE_IMPLEMENT="$value" ;;
            review_code) PHASE_REVIEW_CODE="$value" ;;
            after_explore) BP_AFTER_EXPLORE="$value" ;;
            after_design) BP_AFTER_DESIGN="$value" ;;
            after_review) BP_AFTER_REVIEW="$value" ;;
            after_implement) BP_AFTER_IMPLEMENT="$value" ;;
            after_review_code) BP_AFTER_REVIEW_CODE="$value" ;;
        esac
    done < "$config_file"
}

usage() {
    cat <<'EOF'
Usage: orchestrate.sh [options]

Required:
  --project <dir>         项目目录路径
  --name <name>           需求名称（用于 workspace 子目录和 session 命名，如 "卡对账"）
  --requirement <file>    需求文档路径（设计阶段起需要）

Options:
  --idea <text>           探索阶段的想法/方向（一句话即可）
  --config <file>         配置文件路径 (.workflow-config.yaml)
  --workspace <dir>       工作区目录 (默认: <project>/.workflow)
  --provider <provider>   Agent provider (claude/codex，默认自动推断)
  --model <model>         Agent 模型（Claude 默认 claude-sonnet-4-6；Codex 默认读取 ~/.codex/config.toml）
  --explore               启用探索阶段
  --skip <phase>          跳过指定阶段 (explore/design/review/implement/review-code)
  --auto                  全自动模式（无断点）
  --resume                从上次中断处继续（跳过已有产出的阶段）
  --no-break <phase>      取消指定阶段后的断点
  --break <phase>         在指定阶段后增加断点
  -h, --help              显示帮助

Examples:
  # 基本用法（半自动，方案设计和评审后有断点）
  orchestrate.sh --project ~/code/card-center --name "卡对账" --requirement req.md

  # 只探索，不做设计（研发主导，先摸底）
  orchestrate.sh --project ~/code/card-center --name "卡对账" --explore --idea "能不能做卡交易自动对账" --skip design --skip review --skip implement --skip review-code

  # 探索 + 全流程
  orchestrate.sh --project ~/code/card-center --name "卡对账" --explore --idea "卡交易对账" --requirement req.md

  # 全自动模式
  orchestrate.sh --project ~/code/card-center --name "卡对账" --requirement req.md --auto

  # 从上次中断处继续（跳过已有产出的阶段）
  orchestrate.sh --project ~/code/card-center --name "卡对账" --requirement req.md --resume
EOF
}

# ============================================================
# Parse arguments
# ============================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project) PROJECT_DIR="$2"; shift 2 ;;
        --requirement) REQUIREMENT_FILE="$2"; shift 2 ;;
        --idea) EXPLORE_IDEA="$2"; shift 2 ;;
        --name) TASK_NAME="$2"; shift 2 ;;
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --workspace) WORKSPACE_DIR="$2"; shift 2 ;;
        --provider) PROVIDER="$2"; PROVIDER_FROM_CLI=true; shift 2 ;;
        --model) MODEL="$2"; MODEL_FROM_USER=true; shift 2 ;;
        --explore) PHASE_EXPLORE=true; shift ;;
        --skip)
            case "$2" in
                explore) PHASE_EXPLORE=false ;;
                design) PHASE_DESIGN=false ;;
                review|review-plan) PHASE_REVIEW_PLAN=false ;;
                implement) PHASE_IMPLEMENT=false ;;
                review-code) PHASE_REVIEW_CODE=false ;;
                *) log_error "未知阶段: $2"; exit 1 ;;
            esac
            shift 2
            ;;
        --auto) AUTO_MODE=true; shift ;;
        --resume) RESUME_MODE=true; shift ;;
        --no-break)
            case "$2" in
                explore) BP_AFTER_EXPLORE=false ;;
                design) BP_AFTER_DESIGN=false ;;
                review) BP_AFTER_REVIEW=false ;;
                implement) BP_AFTER_IMPLEMENT=false ;;
                review-code) BP_AFTER_REVIEW_CODE=false ;;
            esac
            shift 2
            ;;
        --break)
            case "$2" in
                explore) BP_AFTER_EXPLORE=true ;;
                design) BP_AFTER_DESIGN=true ;;
                review) BP_AFTER_REVIEW=true ;;
                implement) BP_AFTER_IMPLEMENT=true ;;
                review-code) BP_AFTER_REVIEW_CODE=true ;;
            esac
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) log_error "未知参数: $1"; usage; exit 1 ;;
    esac
done

# Load config file if specified
if [[ -n "$CONFIG_FILE" ]]; then
    parse_config "$CONFIG_FILE"
fi

detect_provider
if [[ "$PROVIDER" == "codex" && "$MODEL_FROM_USER" != true ]]; then
    MODEL="$(detect_codex_default_model)"
fi

# Validate required args
if [[ -z "$PROJECT_DIR" ]]; then
    log_error "必须指定 --project <dir>"
    usage
    exit 1
fi

if [[ -z "$TASK_NAME" ]]; then
    log_error "必须指定 --name <需求名称>（用于 workspace 子目录和 session 命名）"
    exit 1
fi

# 探索模式：只需要 --idea，不需要 --requirement
# 设计及后续模式：需要 --requirement
if [[ "$PHASE_EXPLORE" == true && -z "$REQUIREMENT_FILE" && -z "$EXPLORE_IDEA" ]]; then
    log_error "探索模式需要 --idea <想法> 或 --requirement <file>"
    exit 1
fi

if [[ "$PHASE_DESIGN" == true && -z "$REQUIREMENT_FILE" && "$PHASE_EXPLORE" == false ]]; then
    log_error "设计阶段需要 --requirement <file>（或先启用 --explore 由探索阶段产出需求）"
    exit 1
fi

# Resolve paths
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
if [[ -n "$REQUIREMENT_FILE" ]]; then
    REQUIREMENT_FILE="$(cd "$(dirname "$REQUIREMENT_FILE")" && pwd)/$(basename "$REQUIREMENT_FILE")"
fi

if [[ -z "$WORKSPACE_DIR" ]]; then
    WORKSPACE_DIR="$PROJECT_DIR/.workflow"
fi

# Workspace 结构: .workflow/<需求名>/<阶段>/
WORKSPACE_DIR="$WORKSPACE_DIR/$TASK_NAME"

# 阶段子目录
DIR_EXPLORE="$WORKSPACE_DIR/explore"
DIR_DESIGN="$WORKSPACE_DIR/design"
DIR_REVIEW="$WORKSPACE_DIR/review"
DIR_IMPLEMENT="$WORKSPACE_DIR/implement"
DIR_REVIEW_CODE="$WORKSPACE_DIR/review-code"
STATE_FILE="$WORKSPACE_DIR/workflow-state.json"
WORKFLOW_ID="$(basename "$PROJECT_DIR")-${TASK_NAME}-$(date +%Y%m%d%H%M%S)"

# Create workspace and phase directories
mkdir -p "$WORKSPACE_DIR" "$DIR_EXPLORE" "$DIR_DESIGN" "$DIR_REVIEW" "$DIR_IMPLEMENT" "$DIR_REVIEW_CODE"

state_cmd init \
    --file "$STATE_FILE" \
    --workflow-id "$WORKFLOW_ID" \
    --task-name "$TASK_NAME" \
    --provider "$PROVIDER" \
    --model "$MODEL" \
    --project-dir "$PROJECT_DIR" \
    --workspace-dir "$WORKSPACE_DIR"

# Copy requirement to workspace root (if provided)
if [[ -n "$REQUIREMENT_FILE" ]]; then
    cp "$REQUIREMENT_FILE" "$WORKSPACE_DIR/requirement.md"
fi

# Save idea to workspace root (if provided)
if [[ -n "$EXPLORE_IDEA" ]]; then
    echo "$EXPLORE_IDEA" > "$WORKSPACE_DIR/idea.txt"
fi

# Check for agent project instructions
if [[ ! -f "$PROJECT_DIR/CLAUDE.md" && ! -f "$PROJECT_DIR/AGENTS.md" ]]; then
    log_warn "项目目录中没有 CLAUDE.md 或 AGENTS.md，agent 将缺少项目特有的约束和规范"
    log_warn "建议记录编码风格、框架约定、特殊依赖等项目指南"
    echo ""
fi

log_info "项目目录: $PROJECT_DIR"
if [[ -n "$REQUIREMENT_FILE" ]]; then
    log_info "需求文档: $REQUIREMENT_FILE"
fi
if [[ -n "$EXPLORE_IDEA" ]]; then
    log_info "探索想法: $EXPLORE_IDEA"
fi
log_info "工作区:   $WORKSPACE_DIR"
log_info "Provider: $PROVIDER"
log_info "CLI:      $PROVIDER_CLI"
log_info "模型:     $MODEL"
log_info "自动模式: $AUTO_MODE"
detect_ghostty_window
if [[ -n "$GHOSTTY_WINDOW_ID" ]]; then
    log_info "Ghostty 窗口: $GHOSTTY_WINDOW_ID"
fi
if [[ "$RESUME_MODE" == true ]]; then
    log_info "续跑模式: 已有产出的阶段将被跳过"
fi
echo ""

# ============================================================
# Phase execution
# ============================================================

run_phase() {
    local phase_name="$1"
    local skill_name="$2"
    local prompt="$3"
    local output_file="$4"
    local log_dir="$5"  # 日志输出目录
    local resume_phase="${6:-}"  # 可选：要 resume 的 phase name

    local session_name="${TASK_NAME}-${phase_name}"
    local resume_session_name=""
    local resume_session_id=""

    if [[ -n "$resume_phase" ]]; then
        resume_session_name="${TASK_NAME}-${resume_phase}"
        resume_session_id="$(get_phase_session_id "$resume_phase")"
    fi

    if [[ -n "$resume_phase" ]]; then
        if [[ -n "$resume_session_id" ]]; then
            log_info "续接 session: $resume_phase ($resume_session_id)"
        elif [[ "$PROVIDER" == "claude" ]]; then
            log_warn "未找到 $resume_phase 的 session_id，将回退到 session name: $resume_session_name"
        else
            log_error "未找到 $resume_phase 的 session_id，codex 无法可靠续接"
            exit 1
        fi
    else
        log_info "启动 session: $session_name"
    fi
    log_info "输出文件: $output_file"

    # 阶段模型：优先用阶段专属模型，fallback 到全局
    local phase_model="$MODEL"

    # 将 prompt 写入临时文件，避免命令行长度限制和转义问题
    local prompt_file="${log_dir}/${phase_name}.prompt"
    echo "$prompt" > "$prompt_file"

    # 在 prompt 末尾追加完成标记指令
    # agent 完成任务后询问用户确认，用户确认后写 .done，编排器检测到后推进下一阶段
    local done_marker="${log_dir}/${phase_name}.done"
    cat >> "$prompt_file" << DONEEOF

重要：当你完成上述所有任务后，请告知用户你已完成，并列出你的产出文件路径，请用户审阅。
当用户确认可以继续后（例如回复"ok"、"继续"、"下一步"等），运行以下 bash 命令写入完成标记：
echo "0" > "${done_marker}"
这个标记用于通知编排器推进到下一阶段。在用户明确确认之前，不要写入该标记。
DONEEOF

    # 构建在新 tab 中执行的脚本
    local started_marker="${log_dir}/${phase_name}.started"
    local run_script="${log_dir}/${phase_name}.run.sh"
    local phase_started_epoch
    phase_started_epoch="$(date +%s)"
    # 捕获当前环境中 claude 需要的认证和配置变量
    local env_exports=""
    for var in ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_BEDROCK_BASE_URL \
               ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL \
               CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_SKIP_BEDROCK_AUTH CLAUDE_CODE_USE_VERTEX \
               OPENAI_API_KEY CODEX_HOME \
               AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION \
               HOME; do
        if [[ -n "${!var:-}" ]]; then
            env_exports="${env_exports}export ${var}='${!var}'
"
        fi
    done

    cat > "$run_script" << RUNEOF
#!/bin/bash
export NODE_TLS_REJECT_UNAUTHORIZED=0
export PATH="/opt/homebrew/bin:/usr/local/bin:\$HOME/.local/bin:\$PATH"
swift -e 'import Carbon; let s = TISCreateInputSourceList([kTISPropertyInputSourceID: "com.apple.keylayout.ABC" as CFString] as CFDictionary, false)!.takeRetainedValue() as! [TISInputSource]; if let i = s.first { TISSelectInputSource(i) }' 2>/dev/null || true
${env_exports}
cd "$PROJECT_DIR"
# 写启动标记（用于验证 tab 打开成功）
echo "\$\$" > "${started_marker}"
echo -e "\033[1;36m════════════════════════════════════════\033[0m"
echo -e "\033[1;36m  Session: ${session_name}\033[0m"
echo -e "\033[1;36m  Provider:${PROVIDER}\033[0m"
echo -e "\033[1;36m  CLI:     ${PROVIDER_CLI}\033[0m"
echo -e "\033[1;36m  Model:   ${phase_model}\033[0m"
echo -e "\033[1;36m  Project: ${PROJECT_DIR}\033[0m"
echo -e "\033[1;36m════════════════════════════════════════\033[0m"
echo ""
# agent 在前台运行，保持完整的 tty 连接
# 用户确认后 agent 写 .done，编排器检测到即推进下一阶段
if [[ "${PROVIDER}" == "claude" ]]; then
    if [[ -n "${resume_session_id}" ]]; then
        "${PROVIDER_CLI}" \\
            --model "$phase_model" \\
            --session-id "${resume_session_id}" \\
            --add-dir "$PROJECT_DIR" \\
            --permission-mode default \\
            --verbose \\
            -- "\$(cat '${prompt_file}')"
    elif [[ -n "${resume_session_name}" ]]; then
        "${PROVIDER_CLI}" \\
            --model "$phase_model" \\
            --add-dir "$PROJECT_DIR" \\
            --permission-mode default \\
            --verbose \\
            --resume "${resume_session_name}" \\
            -- "\$(cat '${prompt_file}')"
    else
        "${PROVIDER_CLI}" \\
            --model "$phase_model" \\
            --name "$session_name" \\
            --add-dir "$PROJECT_DIR" \\
            --permission-mode default \\
            --verbose \\
            -- "\$(cat '${prompt_file}')"
    fi
elif [[ "${PROVIDER}" == "codex" ]]; then
    if [[ -n "${resume_session_id}" ]]; then
        "${PROVIDER_CLI}" resume \\
            -m "$phase_model" \\
            -C "$PROJECT_DIR" \\
            "${resume_session_id}" \\
            "\$(cat '${prompt_file}')"
    else
        "${PROVIDER_CLI}" \\
            -m "$phase_model" \\
            -C "$PROJECT_DIR" \\
            "\$(cat '${prompt_file}')"
    fi
else
    echo "Unsupported provider: ${PROVIDER}" >&2
    exit 2
fi
EXIT_CODE=\$?

# 如果 agent 没有写 .done（比如用户手动退出 claude），由脚本兜底写入
if [[ ! -f "${done_marker}" ]]; then
    echo "\$EXIT_CODE" > "${done_marker}"
fi
RUNEOF
    chmod +x "$run_script"

    state_cmd phase-start \
        --file "$STATE_FILE" \
        --phase "$phase_name" \
        --provider "$PROVIDER" \
        --model "$phase_model" \
        --session-name "$session_name" \
        --output-file "$output_file" \
        --prompt-file "$prompt_file" \
        --run-script "$run_script" \
        --started-epoch "$phase_started_epoch"

    # 在当前 Ghostty 窗口中打开新 tab 执行脚本
    rm -f "$started_marker"
    if [[ -n "$GHOSTTY_WINDOW_ID" ]]; then
        "$BIN_DIR/ghostty-open-tab" --script "$run_script" --cwd "$PROJECT_DIR" --verify-file "$started_marker" --window-id "$GHOSTTY_WINDOW_ID"
    else
        "$BIN_DIR/ghostty-open-tab" --script "$run_script" --cwd "$PROJECT_DIR" --verify-file "$started_marker"
    fi

    if [[ -z "$resume_phase" ]]; then
        local discovered_session_id
        discovered_session_id="$("$BIN_DIR/find-agent-session" \
            --provider "$PROVIDER" \
            --project-dir "$PROJECT_DIR" \
            --session-name "$session_name" \
            --started-epoch "$phase_started_epoch" 2>/dev/null || true)"
        if [[ -n "$discovered_session_id" ]]; then
            state_cmd set-session-id --file "$STATE_FILE" --phase "$phase_name" --session-id "$discovered_session_id"
            log_info "记录 session_id: $phase_name → $discovered_session_id"
        else
            log_warn "未能发现 $phase_name 的 session_id，后续精确续接可能不可用"
        fi
    fi

    # 等待该阶段完成（轮询 .done 标记文件）
    log_info "等待 session 完成..."
    while [[ ! -f "${log_dir}/${phase_name}.done" ]]; do
        sleep 5
    done

    local exit_code
    exit_code=$(cat "${log_dir}/${phase_name}.done")
    rm -f "${log_dir}/${phase_name}.done" "${prompt_file}"

    local phase_status="done"
    if [[ "$exit_code" != "0" ]]; then
        phase_status="failed"
    fi
    state_cmd phase-finish \
        --file "$STATE_FILE" \
        --phase "$phase_name" \
        --status "$phase_status" \
        --exit-code "$exit_code" \
        --output-file "$output_file"

    if [[ -f "$output_file" ]]; then
        log_success "$phase_name 完成 → $output_file"
    else
        log_warn "$phase_name 完成，但输出文件未生成，请检查 ${log_dir}/${phase_name}.log"
    fi
}

# Resume 检查：如果产出文件已存在，跳过该阶段
# 用法: should_skip_phase "phase_name" "output_file" && skip
should_skip_phase() {
    local phase_name="$1"
    local output_file="$2"
    if [[ "$RESUME_MODE" == true && -f "$output_file" ]]; then
        log_info "跳过 ${phase_name}（已有产出: $(basename "$output_file")）"
        state_cmd phase-finish \
            --file "$STATE_FILE" \
            --phase "$phase_name" \
            --status "skipped" \
            --exit-code "0" \
            --output-file "$output_file"
        return 0
    fi
    return 1
}

# ── Phase 1: Explore ──

if [[ "$PHASE_EXPLORE" == true ]] && ! should_skip_phase "explore" "$DIR_EXPLORE/exploration.md"; then
    log_phase 1 "需求探索 (/explore)"

    # 确定探索输入：优先用 idea，其次用 requirement
    EXPLORE_INPUT=""
    if [[ -n "$EXPLORE_IDEA" ]]; then
        EXPLORE_INPUT="想法/方向：$EXPLORE_IDEA"
    elif [[ -f "$WORKSPACE_DIR/requirement.md" ]]; then
        EXPLORE_INPUT="参考需求文档 $WORKSPACE_DIR/requirement.md"
    fi

    run_phase "explore" "explore" \
        "调用 /explore skill。

上下文参数：
- 探索输入：${EXPLORE_INPUT}
- 项目路径：$PROJECT_DIR
- 报告输出路径：$DIR_EXPLORE/exploration.md
- 如果探索过程中发现需求可以被细化，也将细化后的需求描述写入 $WORKSPACE_DIR/requirement.md" \
        "$DIR_EXPLORE/exploration.md" "$DIR_EXPLORE"

    if [[ "$BP_AFTER_EXPLORE" == true ]]; then
        wait_for_user "探索阶段完成，请审阅探索报告" "$DIR_EXPLORE/exploration.md" || PHASE_DESIGN=false
    fi
fi

# ── Phase 2: Design ──

if [[ "$PHASE_DESIGN" == true ]] && ! should_skip_phase "design" "$DIR_DESIGN/plan.md"; then
    log_phase 2 "方案设计 (/design)"

    DESIGN_CONTEXT=""
    if [[ -f "$DIR_EXPLORE/exploration.md" ]]; then
        DESIGN_CONTEXT="探索报告在 $DIR_EXPLORE/exploration.md，请先阅读。"
    fi

    run_phase "design" "design" \
        "调用 /design skill。

上下文参数：
- 需求路径：$WORKSPACE_DIR/requirement.md
- 项目路径：$PROJECT_DIR
- 方案输出路径：$DIR_DESIGN/plan.md
- 补充上下文：${DESIGN_CONTEXT}

额外约束：
- 对每个改动项，必须明确区分「行为变更」和「结构优化」
- 对生产在跑的关键路径，默认保留现有行为，除非有明确且充分的理由变更
- 如果涉及序列化库切换、数据格式变更、协议变更等行为变更，必须逐字段验证兼容性，并在风险章节显式标注" \
        "$DIR_DESIGN/plan.md" "$DIR_DESIGN"

    if [[ "$BP_AFTER_DESIGN" == true ]]; then
        wait_for_user "方案设计完成，请审阅技术方案" "$DIR_DESIGN/plan.md" || PHASE_REVIEW_PLAN=false
    fi
fi

# ── Phase 3: Review-Revise Loop ──
# 评审 → 修正 → 再评审，循环直到 VERDICT: PASS

REVIEW_ROUND=0

REVIEW_ALREADY_PASSED=false
if [[ "$RESUME_MODE" == true && -f "$DIR_REVIEW/review.md" ]] && grep -q "VERDICT: PASS" "$DIR_REVIEW/review.md" 2>/dev/null; then
    log_info "跳过 review（已有 VERDICT: PASS）"
    REVIEW_ALREADY_PASSED=true
fi

if [[ "$PHASE_REVIEW_PLAN" == true && "$REVIEW_ALREADY_PASSED" == false ]]; then
    while true; do
        REVIEW_ROUND=$((REVIEW_ROUND + 1))

        log_phase "3" "方案评审 第${REVIEW_ROUND}轮 (/review-plan)"

        # 构建评审上下文：第 2 轮起告知评审者这是复审
        REVIEW_CONTEXT=""
        if [[ $REVIEW_ROUND -gt 1 ]]; then
            REVIEW_CONTEXT="这是第${REVIEW_ROUND}轮评审。上一轮评审报告在 $DIR_REVIEW/review-r$((REVIEW_ROUND-1)).md，方案修正说明在 $DIR_REVIEW/revise-notes-r$((REVIEW_ROUND-1)).md。请重点验证上轮提出的问题是否已修正到位，同时检查修正是否引入新问题。"
        fi

        run_phase "review-plan-r${REVIEW_ROUND}" "review-plan" \
            "调用 /review-plan skill。

上下文参数：
- 方案路径：$DIR_DESIGN/plan.md
- 项目路径：$PROJECT_DIR
- 报告输出路径：$DIR_REVIEW/review-r${REVIEW_ROUND}.md
- 评审上下文：${REVIEW_CONTEXT}

额外关注：
- 方案中标注为「行为变更」的改动，必须逐字段验证兼容性
- 如果方案没有区分行为变更和结构优化，这本身就是一个问题

最后必须给出一行总体裁决（这一行会被自动解析，格式必须严格）：
- 如果所有项都通过：VERDICT: PASS
- 如果有任何项需要修改：VERDICT: NEEDS_REVISION" \
            "$DIR_REVIEW/review-r${REVIEW_ROUND}.md" "$DIR_REVIEW"

        # 保持 review.md 始终指向最新版
        cp "$DIR_REVIEW/review-r${REVIEW_ROUND}.md" "$DIR_REVIEW/review.md" 2>/dev/null || true

        # 检查评审结论
        if grep -q "VERDICT: PASS" "$DIR_REVIEW/review-r${REVIEW_ROUND}.md" 2>/dev/null; then
            log_success "方案评审通过（第${REVIEW_ROUND}轮）"
            break
        fi

        # 断点：让用户看评审结果
        if [[ "$BP_AFTER_REVIEW" == true ]]; then
            wait_for_user "第${REVIEW_ROUND}轮评审完成，方案需要修正" "$DIR_REVIEW/review-r${REVIEW_ROUND}.md" || { PHASE_IMPLEMENT=false; break; }
        fi

        # ── Revise ──
        log_phase "3.5" "方案修正 第${REVIEW_ROUND}轮"

        REVISE_CONTEXT=""
        if [[ $REVIEW_ROUND -gt 1 ]]; then
            REVISE_CONTEXT="这是第${REVIEW_ROUND}轮修正。上一轮修正说明在 $DIR_REVIEW/revise-notes-r$((REVIEW_ROUND-1)).md。"
        fi

        # revise 续接 design session（同一个 agent 修正自己的方案）
        run_phase "revise-r${REVIEW_ROUND}" "revise" \
            "评审报告已出，请根据评审反馈修正你的技术方案。

阅读评审报告：$DIR_REVIEW/review.md
${REVISE_CONTEXT}

在 $PROJECT_DIR 项目中验证评审意见是否正确（自己读代码确认）。

修正规则：
- 评审意见正确的：修正方案
- 评审意见有误的：保留原方案，说明理由
- 评审建议合理但不在本次范围的：记录到风险章节

修正方式：
- 先执行 cp $DIR_DESIGN/plan.md $DIR_DESIGN/plan-r${REVIEW_ROUND}.md，在 plan-r${REVIEW_ROUND}.md 上修改
- 就地修改对应章节，禁止在文件末尾追加修正说明章节。plan-r${REVIEW_ROUND}.md 必须是一份完整、自洽的方案文档
- 修改任何一处后，检查全文是否有其他章节涉及同一话题（如改了数据模型，流程、性能评估、实现指引中的引用也要同步更新）
- 用 Edit 工具精确修改具体章节，不要 Write 重写整个文件
- 所有修改完成后，Read 整个 plan-r${REVIEW_ROUND}.md 通读一遍，确认没有前后矛盾或残留旧内容

将修正说明写入 $DIR_REVIEW/revise-notes-r${REVIEW_ROUND}.md，包含：
- 采纳的评审意见及修正内容（标注修改了哪些章节）
- 未采纳的评审意见及理由
- 新增的风险项" \
            "$DIR_REVIEW/revise-notes-r${REVIEW_ROUND}.md" "$DIR_REVIEW" \
            "design"

        # 保持 plan.md 始终指向最新版
        cp "$DIR_DESIGN/plan-r${REVIEW_ROUND}.md" "$DIR_DESIGN/plan.md" 2>/dev/null || true

        log_success "第${REVIEW_ROUND}轮方案修正完成，进入下一轮评审"
    done
fi

# ── Phase 4: Implement ──

if [[ "$PHASE_IMPLEMENT" == true ]] && ! should_skip_phase "implement" "$DIR_IMPLEMENT/impl-notes.md"; then
    log_phase 4 "TDD 实现 (/implement)"

    IMPL_CONTEXT=""
    if [[ -f "$DIR_REVIEW/review.md" ]]; then
        IMPL_CONTEXT="评审反馈在 $DIR_REVIEW/review.md。"
    fi
    if [[ -f "$DIR_REVIEW/revise-notes.md" ]]; then
        IMPL_CONTEXT="${IMPL_CONTEXT}方案修正说明在 $DIR_REVIEW/revise-notes.md，注意哪些评审意见已被采纳。"
    fi

    run_phase "implement" "implement" \
        "调用 /implement skill。

上下文参数：
- 方案路径：$DIR_DESIGN/plan.md
- 项目路径：$PROJECT_DIR
- 输出路径：$DIR_IMPLEMENT/impl-notes.md
- 实现上下文：${IMPL_CONTEXT}" \
        "$DIR_IMPLEMENT/impl-notes.md" "$DIR_IMPLEMENT"

    if [[ "$BP_AFTER_IMPLEMENT" == true ]]; then
        wait_for_user "实现完成，请审阅实现说明" "$DIR_IMPLEMENT/impl-notes.md" || PHASE_REVIEW_CODE=false
    fi
fi

# ── Phase 5: Code Review-Fix Loop ──
# 代码评审 → 修复 → 再评审，循环直到 VERDICT: PASS

CODE_REVIEW_ROUND=0

CODE_REVIEW_ALREADY_PASSED=false
if [[ "$RESUME_MODE" == true && -f "$DIR_REVIEW_CODE/code-review.md" ]] && grep -q "VERDICT: PASS" "$DIR_REVIEW_CODE/code-review.md" 2>/dev/null; then
    log_info "跳过 review-code（已有 VERDICT: PASS）"
    CODE_REVIEW_ALREADY_PASSED=true
fi

if [[ "$PHASE_REVIEW_CODE" == true && "$CODE_REVIEW_ALREADY_PASSED" == false ]]; then
    while true; do
        CODE_REVIEW_ROUND=$((CODE_REVIEW_ROUND + 1))

        log_phase "5" "代码评审 第${CODE_REVIEW_ROUND}轮 (/review-code)"

        # 构建评审上下文：第 2 轮起告知评审者这是复审
        CODE_REVIEW_CONTEXT=""
        if [[ $CODE_REVIEW_ROUND -gt 1 ]]; then
            CODE_REVIEW_CONTEXT="这是第${CODE_REVIEW_ROUND}轮代码评审。上一轮评审报告在 $DIR_REVIEW_CODE/code-review-r$((CODE_REVIEW_ROUND-1)).md，修复说明在 $DIR_REVIEW_CODE/fix-notes-r$((CODE_REVIEW_ROUND-1)).md。请重点验证上轮提出的必须修改项是否已修复到位，同时检查修复是否引入新问题。"
        fi

        run_phase "review-code-r${CODE_REVIEW_ROUND}" "review-code" \
            "调用 /review-code skill（对照方案模式）。

上下文参数：
- 方案路径：$DIR_DESIGN/plan.md
- 项目路径：$PROJECT_DIR
- 报告输出路径：$DIR_REVIEW_CODE/code-review-r${CODE_REVIEW_ROUND}.md
- 评审上下文：${CODE_REVIEW_CONTEXT}

最后必须给出一行总体裁决（这一行会被自动解析，格式必须严格）：
- 如果所有必须修改的问题都已解决或无必须修改项：VERDICT: PASS
- 如果有必须修改的问题：VERDICT: NEEDS_FIX" \
            "$DIR_REVIEW_CODE/code-review-r${CODE_REVIEW_ROUND}.md" "$DIR_REVIEW_CODE"

        # 保持 code-review.md 始终指向最新版
        cp "$DIR_REVIEW_CODE/code-review-r${CODE_REVIEW_ROUND}.md" "$DIR_REVIEW_CODE/code-review.md" 2>/dev/null || true

        # 检查评审结论
        if grep -q "VERDICT: PASS" "$DIR_REVIEW_CODE/code-review-r${CODE_REVIEW_ROUND}.md" 2>/dev/null; then
            log_success "代码评审通过（第${CODE_REVIEW_ROUND}轮）"
            break
        fi

        # 断点：让用户看评审结果
        if [[ "$BP_AFTER_REVIEW_CODE" == true ]]; then
            wait_for_user "第${CODE_REVIEW_ROUND}轮代码评审完成，代码需要修复" "$DIR_REVIEW_CODE/code-review-r${CODE_REVIEW_ROUND}.md" || break
        fi

        # ── Fix ──
        log_phase "5.5" "代码修复 第${CODE_REVIEW_ROUND}轮"

        FIX_CONTEXT=""
        if [[ $CODE_REVIEW_ROUND -gt 1 ]]; then
            FIX_CONTEXT="这是第${CODE_REVIEW_ROUND}轮修复。上一轮修复说明在 $DIR_REVIEW_CODE/fix-notes-r$((CODE_REVIEW_ROUND-1)).md。"
        fi

        # fix 续接 implement session（同一个 agent 修复自己的代码）
        run_phase "fix-r${CODE_REVIEW_ROUND}" "fix" \
            "代码评审报告已出，请根据评审反馈修复代码问题。

阅读评审报告：$DIR_REVIEW_CODE/code-review.md
${FIX_CONTEXT}

在 $PROJECT_DIR 项目中修复评审指出的问题。

修复规则：
- 「必须修改」的问题：必须修复
- 评审意见有误的：保留原实现，说明理由
- 「建议改进」的问题：酌情采纳，不强制

修复后运行与本次变更相关的测试确保通过；如果项目没有测试、测试工具不可用，或本次变更不适合自动化测试，请在修复说明中写明原因和替代验证方式。

将修复说明写入 $DIR_REVIEW_CODE/fix-notes-r${CODE_REVIEW_ROUND}.md，包含：
- 已修复的问题及修复内容
- 未修复的问题及理由
- 测试运行结果" \
            "$DIR_REVIEW_CODE/fix-notes-r${CODE_REVIEW_ROUND}.md" "$DIR_REVIEW_CODE" \
            "implement"

        log_success "第${CODE_REVIEW_ROUND}轮代码修复完成，进入下一轮评审"
    done
fi

# ============================================================
# Summary
# ============================================================

echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  全部阶段完成${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "工作区: ${BOLD}$WORKSPACE_DIR${NC}"
echo ""
echo "产出文件:"

# 按阶段列出产出
for entry in \
    "$WORKSPACE_DIR/requirement.md|requirement.md" \
    "$WORKSPACE_DIR/idea.txt|idea.txt" \
    "$DIR_EXPLORE/exploration.md|explore/exploration.md" \
    "$DIR_DESIGN/plan.md|design/plan.md" \
    "$DIR_REVIEW/review.md|review/review.md" \
    "$DIR_REVIEW/revise-notes.md|review/revise-notes.md" \
    "$DIR_IMPLEMENT/impl-notes.md|implement/impl-notes.md" \
    "$DIR_REVIEW_CODE/code-review.md|review-code/code-review.md"; do
    full_path="${entry%%|*}"
    label="${entry##*|}"
    if [[ -f "$full_path" ]]; then
        echo -e "  ${GREEN}✓${NC} ${label}"
    fi
done

# 列出评审轮次
for f in "$DIR_REVIEW"/round-*.md; do
    if [[ -f "$f" ]]; then
        echo -e "  ${GREEN}✓${NC} review/$(basename "$f")"
    fi
done

echo ""
echo "日志文件:"
for dir in "$DIR_EXPLORE" "$DIR_DESIGN" "$DIR_REVIEW" "$DIR_IMPLEMENT" "$DIR_REVIEW_CODE"; do
    for f in "$dir"/*.log; do
        if [[ -f "$f" ]]; then
            local_dir="$(basename "$(dirname "$f")")"
            echo -e "  ${BLUE}→${NC} ${local_dir}/$(basename "$f")"
        fi
    done
done
echo ""
if [[ -f "$DIR_DESIGN/plan.md" ]]; then
    echo -e "${CYAN}[TIP]${NC} 方案已生成，可在 Claude Code 中运行 /write-trd 生成 TRD 文档"
fi
