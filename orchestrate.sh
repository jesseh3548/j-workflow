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
if [[ -d "$SCRIPT_DIR/prompts" ]]; then
    # Source checkout layout: orchestrate.sh at repo root, templates in ./prompts.
    PROMPTS_DIR="$SCRIPT_DIR/prompts"
elif [[ -d "$SCRIPT_DIR/../prompts" ]]; then
    # Installed layout: orchestrate.sh in bin/, templates copied as sibling ../prompts.
    PROMPTS_DIR="$(cd "$SCRIPT_DIR/../prompts" && pwd)"
else
    echo "Cannot find prompt templates near $SCRIPT_DIR" >&2
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
FLOW_FILE=""
FLOW_TEMPLATE_FILE=""
FLOW_SCHEMA_VERSION=""
PROVIDER=""
PROVIDER_CLI=""
MODEL=""
MODEL_FROM_USER=false
MODEL_EXPLORE=""
MODEL_DESIGN=""
MODEL_REVIEW=""
MODEL_REVISE=""
MODEL_IMPLEMENT=""
MODEL_REVIEW_CODE=""
MODEL_FIX=""
SKIP_PHASES=()
AUTO_MODE=false
RESUME_MODE=false
GHOSTTY_WINDOW_ID=""
MAX_ROUNDS=3
PHASE_TIMEOUT_MINUTES=0

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
        WAIT_CHOICE="continue"
        return 0
    fi
    local accept_label="${3:-}"
    echo ""
    echo -e "${YELLOW}[BREAKPOINT]${NC} $1"
    echo -e "  输出文件: ${BOLD}$2${NC}"
    echo ""
    echo "  Enter = 继续推荐路径"
    if [[ -n "$accept_label" ]]; then
        echo "  a     = $accept_label"
    fi
    echo "  q     = 保存状态并退出（之后可用 --resume）"
    read -rp "  请选择 [Enter/a/q]: " choice
    case "$choice" in
        "") WAIT_CHOICE="continue"; return 0 ;;
        a|A)
            if [[ -n "$accept_label" ]]; then
                WAIT_CHOICE="accept"
                return 0
            fi
            log_error "当前断点不支持 a 选项"
            exit 1
            ;;
        q|Q) echo "已退出。可用 --resume 继续。"; exit 0 ;;
        *) log_error "未知选择: $choice"; exit 1 ;;
    esac
}

handle_loop_limit() {
    local loop_name="$1"
    local completed_rounds="$2"

    if [[ "$AUTO_MODE" == true ]]; then
        log_error "${loop_name} 循环达到上限 ${MAX_ROUNDS} 轮仍未 PASS"
        state_cmd set-workflow-meta --file "$STATE_FILE" --key loop_exhausted --value "$loop_name"
        exit 2
    fi

    echo ""
    echo -e "${YELLOW}[LOOP LIMIT]${NC} ${loop_name} 已完成 ${completed_rounds} 轮，达到上限 ${MAX_ROUNDS} 轮仍未 PASS。"
    echo "  c = 继续再跑一轮"
    echo "  a = 接受当前结果，继续后续阶段"
    echo "  q = 保存状态并退出（之后可用 --resume）"
    read -rp "  请选择 [c/a/q]: " choice
    case "$choice" in
        c|C) return 0 ;;
        a|A) return 1 ;;
        q|Q) echo "已退出。可用 --resume 继续。"; exit 0 ;;
        *) log_error "未知选择: $choice"; exit 1 ;;
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
    GHOSTTY_WINDOW_ID="$("$BIN_DIR/detect-ghostty-window" 2>/dev/null || true)"
    if [[ -z "$GHOSTTY_WINDOW_ID" ]]; then
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

get_phase_model() {
    local phase_name="$1"
    local model_key=""

    if [[ -n "${FLOW_FILE:-}" && -f "${FLOW_FILE:-}" ]]; then
        model_key="$("$BIN_DIR/workflow-manifest" phase-get --file "$FLOW_FILE" --phase "$phase_name" --field model_key 2>/dev/null || true)"
    fi

    if [[ -z "$model_key" ]]; then
        case "$phase_name" in
            explore) model_key="model_explore" ;;
            design) model_key="model_design" ;;
            review|review-plan) model_key="model_review" ;;
            revise) model_key="model_revise" ;;
            implement) model_key="model_implement" ;;
            review-code) model_key="model_review_code" ;;
            fix) model_key="model_fix" ;;
            *) model_key="model" ;;
        esac
    fi

    case "$model_key" in
        model_explore) echo "${MODEL_EXPLORE:-$MODEL}" ;;
        model_design) echo "${MODEL_DESIGN:-$MODEL}" ;;
        model_review|model_review_plan) echo "${MODEL_REVIEW:-$MODEL}" ;;
        model_revise) echo "${MODEL_REVISE:-$MODEL}" ;;
        model_implement) echo "${MODEL_IMPLEMENT:-$MODEL}" ;;
        model_review_code) echo "${MODEL_REVIEW_CODE:-$MODEL}" ;;
        model_fix) echo "${MODEL_FIX:-$MODEL}" ;;
        model|*) echo "$MODEL" ;;
    esac
}

model_for_state() {
    local model_value="$1"
    if [[ -n "$model_value" ]]; then
        echo "$model_value"
    else
        echo "provider-default"
    fi
}

validate_flow_manifest() {
    local flow_file="$1"
    "$BIN_DIR/validate-workflow-manifest" "$flow_file"
}

validate_workflow_state() {
    "$BIN_DIR/validate-workflow-state" "$STATE_FILE" >/dev/null
}

get_workflow_meta() {
    state_cmd get-workflow-meta --file "$STATE_FILE" --key "$1" 2>/dev/null || true
}

validate_workspace_artifacts() {
    if [[ -z "${FLOW_FILE:-}" || ! -f "${FLOW_FILE:-}" ]]; then
        return 0
    fi
    if "$BIN_DIR/validate-workspace-artifacts" --manifest "$FLOW_FILE" --workspace "$WORKSPACE_DIR" >/dev/null; then
        state_cmd set-workflow-meta --file "$STATE_FILE" --key artifact_validation_status --value "pass"
    else
        state_cmd set-workflow-meta --file "$STATE_FILE" --key artifact_validation_status --value "failed"
        return 1
    fi
    state_cmd set-workflow-meta --file "$STATE_FILE" --key last_artifact_validation --value "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

validate_phase_artifact() {
    local artifact_kind="$1"
    local file="$2"
    local verdicts=""

    case "$artifact_kind" in
        review-plan) verdicts="PASS,NEEDS_REVISION" ;;
        review-code) verdicts="PASS,NEEDS_FIX" ;;
        requirement-review) verdicts="PASS,NEEDS_CLARIFICATION" ;;
        observability-report) verdicts="PASS,NEEDS_FIX" ;;
    esac

    if [[ -n "${FLOW_FILE:-}" && -f "${FLOW_FILE:-}" ]]; then
        "$BIN_DIR/validate-artifact" --kind "$artifact_kind" --phase "$artifact_kind" --file "$file" --manifest "$FLOW_FILE" --verdicts "$verdicts"
    else
        "$BIN_DIR/validate-artifact" --kind "$artifact_kind" --file "$file" --verdicts "$verdicts"
    fi
}

render_phase_template() {
    local phase_id="$1"
    local field="$2"
    local phase_name="$3"
    local phase_dir="$4"

    if [[ -n "${FLOW_FILE:-}" && -f "${FLOW_FILE:-}" ]]; then
        "$BIN_DIR/workflow-manifest" render-template \
            --file "$FLOW_FILE" \
            --phase "$phase_id" \
            --field "$field" \
            --var "project_dir=$PROJECT_DIR" \
            --var "workspace_dir=$WORKSPACE_DIR" \
            --var "task_name=$TASK_NAME" \
            --var "phase_id=$phase_id" \
            --var "phase_name=$phase_name" \
            --var "phase_dir=$phase_dir"
        return
    fi

    case "$field" in
        prompt_file_template) echo "${phase_dir}/${phase_name}.prompt" ;;
        run_script_template) echo "${phase_dir}/${phase_name}.run.sh" ;;
        started_marker_template) echo "${phase_dir}/${phase_name}.started" ;;
        *) return 1 ;;
    esac
}

phase_dir_for() {
    case "$1" in
        explore) echo "$DIR_EXPLORE" ;;
        design) echo "$DIR_DESIGN" ;;
        review-plan|revise) echo "$DIR_REVIEW" ;;
        implement) echo "$DIR_IMPLEMENT" ;;
        review-code|fix) echo "$DIR_REVIEW_CODE" ;;
        requirement-review) echo "$WORKSPACE_DIR/requirement-review" ;;
        verify-observability) echo "$WORKSPACE_DIR/verify-observability" ;;
        *) echo "$WORKSPACE_DIR/$1" ;;
    esac
}

prompt_template_path_for() {
    local phase_id="$1"
    local prompt_template=""

    if [[ -n "${FLOW_FILE:-}" && -f "${FLOW_FILE:-}" ]]; then
        prompt_template="$("$BIN_DIR/workflow-manifest" phase-get --file "$FLOW_FILE" --phase "$phase_id" --field prompt_template 2>/dev/null || true)"
    fi
    prompt_template="${prompt_template:-prompts/${phase_id}.md}"

    if [[ "$prompt_template" = /* ]]; then
        echo "$prompt_template"
    elif [[ "$prompt_template" == prompts/* ]]; then
        echo "$PROMPTS_DIR/${prompt_template#prompts/}"
    else
        echo "$PROMPTS_DIR/$prompt_template"
    fi
}

# render_phase_prompt <phase_id> <footer> <output_file> <context> [round] [phase_name]
# prompt_template 来自 workflow manifest；phase_name 默认等于 phase_id，
# 循环阶段（review-plan-rN 等）传入实际 phase_name 用于 footer 里的 phase-finish 命令。
render_phase_prompt() {
    local phase_id="$1"
    local footer="$2"
    local output_file="$3"
    local context="$4"
    local round="${5:-}"
    local phase_name="${6:-$phase_id}"

    "$BIN_DIR/render-prompt" \
        --template "$(prompt_template_path_for "$phase_id")" \
        --footer "$footer" \
        --var "project_dir=$PROJECT_DIR" \
        --var "workspace_dir=$WORKSPACE_DIR" \
        --var "task_name=$TASK_NAME" \
        --var "phase_dir=$(phase_dir_for "$phase_id")" \
        --var "phase_id=$phase_id" \
        --var "requirement_file=$WORKSPACE_DIR/requirement.md" \
        --var "plan_file=$DIR_DESIGN/plan.md" \
        --var "brief_file=$DIR_DESIGN/implementation-brief.md" \
        --var "review_latest=$DIR_REVIEW/review.md" \
        --var "code_review_latest=$DIR_REVIEW_CODE/code-review.md" \
        --var "output_file=$output_file" \
        --var "context=$context" \
        --var "round=$round" \
        --var "bin_dir=$BIN_DIR" \
        --var "state_file=$STATE_FILE" \
        --var "phase_name=$phase_name"
}

phase_artifact_path() {
    local phase_id="$1"
    local artifact_kind="$2"
    local round="${3:-}"
    local relative_path

    if [[ -n "${FLOW_FILE:-}" && -f "${FLOW_FILE:-}" ]]; then
        relative_path="$("$BIN_DIR/workflow-manifest" artifact \
            --file "$FLOW_FILE" \
            --phase "$phase_id" \
            --kind "$artifact_kind" \
            --var "round=$round")"
        echo "$WORKSPACE_DIR/$relative_path"
        return
    fi

    return 1
}

artifact_verdict_is_pass() {
    local file="$1"
    "$BIN_DIR/workflow-manifest" is-pass --artifact "$file" 2>/dev/null
}

phase_transition_for_artifact() {
    local phase_id="$1"
    local file="$2"
    "$BIN_DIR/workflow-manifest" transition --file "$FLOW_FILE" --phase "$phase_id" --artifact "$file"
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
        # Strip inline comments, then trim whitespace
        value="${value%%#*}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        case "$key" in
            project_dir) PROJECT_DIR="$value" ;;
            workspace_dir) WORKSPACE_DIR="$value" ;;
            flow_file) FLOW_FILE="$value" ;;
            provider) PROVIDER="$value" ;;
            model) MODEL="$value"; MODEL_FROM_USER=true ;;
            model_explore) MODEL_EXPLORE="$value" ;;
            model_design) MODEL_DESIGN="$value" ;;
            model_review|model_review_plan) MODEL_REVIEW="$value" ;;
            model_revise) MODEL_REVISE="$value" ;;
            model_implement) MODEL_IMPLEMENT="$value" ;;
            model_review_code) MODEL_REVIEW_CODE="$value" ;;
            model_fix) MODEL_FIX="$value" ;;
            max_rounds) MAX_ROUNDS="$value" ;;
            phase_timeout) PHASE_TIMEOUT_MINUTES="$value" ;;
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
  --flow <file>           flow manifest 模板路径（生成 <workspace>/workflow.json 作为本次运行计划）
  --provider <provider>   Agent provider (claude/codex，默认自动推断)
  --model <model>         Agent 模型（Claude 默认使用 CLI 自身配置；Codex 默认读取 ~/.codex/config.toml）
  --model-explore <model> 探索阶段模型（未指定则继承 --model）
  --model-design <model>  设计阶段模型（未指定则继承 --model）
  --model-review <model>  方案评审阶段模型（未指定则继承 --model）
  --model-revise <model>  方案修正阶段模型（未指定则继承 --model）
  --model-implement <model> 实现阶段模型（未指定则继承 --model）
  --model-review-code <model> 代码评审阶段模型（未指定则继承 --model）
  --model-fix <model>     代码修复阶段模型（未指定则继承 --model）
  --max-rounds <n>        review/revise 和 review-code/fix 循环最大轮数（默认 3）
  --phase-timeout <min>   交互阶段最长等待分钟数（默认 0，不超时）
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

ORIGINAL_ARGS=("$@")
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        *) shift ;;
    esac
done

if [[ -n "$CONFIG_FILE" ]]; then
    parse_config "$CONFIG_FILE"
fi

set -- "${ORIGINAL_ARGS[@]}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project) PROJECT_DIR="$2"; shift 2 ;;
        --requirement) REQUIREMENT_FILE="$2"; shift 2 ;;
        --idea) EXPLORE_IDEA="$2"; shift 2 ;;
        --name) TASK_NAME="$2"; shift 2 ;;
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --workspace) WORKSPACE_DIR="$2"; shift 2 ;;
        --flow) FLOW_FILE="$2"; shift 2 ;;
        --provider) PROVIDER="$2"; shift 2 ;;
        --model) MODEL="$2"; MODEL_FROM_USER=true; shift 2 ;;
        --model-explore) MODEL_EXPLORE="$2"; shift 2 ;;
        --model-design) MODEL_DESIGN="$2"; shift 2 ;;
        --model-review|--model-review-plan) MODEL_REVIEW="$2"; shift 2 ;;
        --model-revise) MODEL_REVISE="$2"; shift 2 ;;
        --model-implement) MODEL_IMPLEMENT="$2"; shift 2 ;;
        --model-review-code) MODEL_REVIEW_CODE="$2"; shift 2 ;;
        --model-fix) MODEL_FIX="$2"; shift 2 ;;
        --max-rounds) MAX_ROUNDS="$2"; shift 2 ;;
        --phase-timeout) PHASE_TIMEOUT_MINUTES="$2"; shift 2 ;;
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

if ! [[ "$MAX_ROUNDS" =~ ^[0-9]+$ ]]; then
    log_error "--max-rounds 必须是非负整数: $MAX_ROUNDS"
    exit 1
fi
if ! [[ "$PHASE_TIMEOUT_MINUTES" =~ ^[0-9]+$ ]]; then
    log_error "--phase-timeout 必须是非负整数分钟数: $PHASE_TIMEOUT_MINUTES"
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

if [[ -z "$FLOW_FILE" && -f "$SCRIPT_DIR/workflow.json" ]]; then
    FLOW_TEMPLATE_FILE="$SCRIPT_DIR/workflow.json"
else
    FLOW_TEMPLATE_FILE="$FLOW_FILE"
fi
if [[ -n "$FLOW_TEMPLATE_FILE" ]]; then
    if [[ ! -f "$FLOW_TEMPLATE_FILE" ]]; then
        log_error "flow manifest 不存在: $FLOW_TEMPLATE_FILE"
        exit 1
    fi
    FLOW_TEMPLATE_FILE="$(cd "$(dirname "$FLOW_TEMPLATE_FILE")" && pwd)/$(basename "$FLOW_TEMPLATE_FILE")"
    validate_flow_manifest "$FLOW_TEMPLATE_FILE" >/dev/null
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
RUN_FLOW_FILE="$WORKSPACE_DIR/workflow.json"
WORKFLOW_ID="$(basename "$PROJECT_DIR")-${TASK_NAME}-$(date +%Y%m%d%H%M%S)"

if [[ "$RESUME_MODE" != true ]]; then
    if "$BIN_DIR/archive-workspace" --workspace "$WORKSPACE_DIR" --check-only >/dev/null 2>&1; then
        if [[ "$AUTO_MODE" == true ]]; then
            archived_to="$("$BIN_DIR/archive-workspace" --workspace "$WORKSPACE_DIR")"
            log_warn "检测到旧产出，已归档到 $archived_to"
        else
            echo ""
            echo -e "${YELLOW}[EXISTING WORKSPACE]${NC} 检测到旧产出: $WORKSPACE_DIR"
            echo "  a = 归档旧产出并重新开始"
            echo "  r = 改用 --resume 续跑现有 workspace"
            echo "  q = 退出"
            read -rp "  请选择 [a/r/q]: " archive_choice
            case "$archive_choice" in
                a|A)
                    archived_to="$("$BIN_DIR/archive-workspace" --workspace "$WORKSPACE_DIR")"
                    log_warn "已归档旧产出到 $archived_to"
                    ;;
                r|R)
                    RESUME_MODE=true
                    log_info "切换为续跑模式，将复用现有 workspace"
                    ;;
                q|Q)
                    echo "已退出。"
                    exit 0
                    ;;
                *)
                    log_error "未知选择: $archive_choice"
                    exit 1
                    ;;
            esac
        fi
    fi
fi

# Create workspace and phase directories
mkdir -p "$WORKSPACE_DIR" "$DIR_EXPLORE" "$DIR_DESIGN" "$DIR_REVIEW" "$DIR_IMPLEMENT" "$DIR_REVIEW_CODE"

if [[ "$RESUME_MODE" == true && -f "$RUN_FLOW_FILE" ]]; then
    FLOW_FILE="$RUN_FLOW_FILE"
    FLOW_SCHEMA_VERSION="$(validate_flow_manifest "$FLOW_FILE")"
elif [[ -n "$FLOW_TEMPLATE_FILE" && "$FLOW_TEMPLATE_FILE" == "$RUN_FLOW_FILE" ]]; then
    FLOW_FILE="$RUN_FLOW_FILE"
    FLOW_SCHEMA_VERSION="$(validate_flow_manifest "$FLOW_FILE")"
elif [[ -n "$FLOW_TEMPLATE_FILE" ]]; then
    CREATE_FLOW_ARGS=(
        --template "$FLOW_TEMPLATE_FILE"
        --output "$RUN_FLOW_FILE"
        --mode shell
        --task-name "$TASK_NAME"
        --provider "$PROVIDER"
        --model "$(model_for_state "$MODEL")"
        --max-rounds "$MAX_ROUNDS"
    )
    if [[ "$BP_AFTER_EXPLORE" == true ]]; then CREATE_FLOW_ARGS+=(--break explore); else CREATE_FLOW_ARGS+=(--no-break explore); fi
    if [[ "$BP_AFTER_DESIGN" == true ]]; then CREATE_FLOW_ARGS+=(--break design); else CREATE_FLOW_ARGS+=(--no-break design); fi
    if [[ "$BP_AFTER_REVIEW" == true ]]; then CREATE_FLOW_ARGS+=(--break review-plan); else CREATE_FLOW_ARGS+=(--no-break review-plan); fi
    if [[ "$BP_AFTER_IMPLEMENT" == true ]]; then CREATE_FLOW_ARGS+=(--break implement); else CREATE_FLOW_ARGS+=(--no-break implement); fi
    if [[ "$BP_AFTER_REVIEW_CODE" == true ]]; then CREATE_FLOW_ARGS+=(--break review-code); else CREATE_FLOW_ARGS+=(--no-break review-code); fi
    if [[ "$PHASE_EXPLORE" == true ]]; then
        CREATE_FLOW_ARGS+=(--enable explore)
    else
        CREATE_FLOW_ARGS+=(--disable explore)
    fi
    if [[ "$PHASE_DESIGN" != true ]]; then
        CREATE_FLOW_ARGS+=(--disable design --disable review-plan --disable revise)
    elif [[ "$PHASE_REVIEW_PLAN" != true ]]; then
        CREATE_FLOW_ARGS+=(--disable review-plan --disable revise)
    fi
    if [[ "$PHASE_IMPLEMENT" != true ]]; then
        CREATE_FLOW_ARGS+=(--disable implement)
    fi
    if [[ "$PHASE_REVIEW_CODE" != true ]]; then
        CREATE_FLOW_ARGS+=(--disable review-code --disable fix)
    fi
    "$BIN_DIR/create-workflow-run" "${CREATE_FLOW_ARGS[@]}" >/dev/null
    FLOW_FILE="$RUN_FLOW_FILE"
    FLOW_SCHEMA_VERSION="$(validate_flow_manifest "$FLOW_FILE")"
fi

if [[ -n "$FLOW_FILE" ]]; then
    PHASE_EXPLORE=false
    PHASE_DESIGN=false
    PHASE_REVIEW_PLAN=false
    PHASE_IMPLEMENT=false
    PHASE_REVIEW_CODE=false
    while IFS= read -r phase_id; do
        case "$phase_id" in
            explore) PHASE_EXPLORE=true ;;
            design) PHASE_DESIGN=true ;;
            review-plan) PHASE_REVIEW_PLAN=true ;;
            implement) PHASE_IMPLEMENT=true ;;
            review-code) PHASE_REVIEW_CODE=true ;;
        esac
    done < <("$BIN_DIR/workflow-manifest" execution-order --file "$FLOW_FILE" --kind order)

    FLOW_MAX_ROUNDS="$("$BIN_DIR/workflow-manifest" execution-get --file "$FLOW_FILE" --key max_rounds 2>/dev/null || true)"
    if [[ "$FLOW_MAX_ROUNDS" =~ ^[0-9]+$ ]]; then
        MAX_ROUNDS="$FLOW_MAX_ROUNDS"
    fi
    if "$BIN_DIR/workflow-manifest" phase-get --file "$FLOW_FILE" --phase design --field breakpoint_after >/dev/null 2>&1; then
        BP_AFTER_EXPLORE="$("$BIN_DIR/workflow-manifest" breakpoint-after --file "$FLOW_FILE" --phase explore)"
        BP_AFTER_DESIGN="$("$BIN_DIR/workflow-manifest" breakpoint-after --file "$FLOW_FILE" --phase design)"
        BP_AFTER_REVIEW="$("$BIN_DIR/workflow-manifest" breakpoint-after --file "$FLOW_FILE" --phase review-plan)"
        BP_AFTER_IMPLEMENT="$("$BIN_DIR/workflow-manifest" breakpoint-after --file "$FLOW_FILE" --phase implement)"
        BP_AFTER_REVIEW_CODE="$("$BIN_DIR/workflow-manifest" breakpoint-after --file "$FLOW_FILE" --phase review-code)"
    fi
fi

state_cmd init \
    --file "$STATE_FILE" \
    --workflow-id "$WORKFLOW_ID" \
    --task-name "$TASK_NAME" \
    --provider "$PROVIDER" \
    --model "$(model_for_state "$MODEL")" \
    --project-dir "$PROJECT_DIR" \
    --workspace-dir "$WORKSPACE_DIR"

if [[ -n "$FLOW_FILE" ]]; then
    state_cmd set-workflow-meta --file "$STATE_FILE" --key flow_file --value "$FLOW_FILE"
    state_cmd set-workflow-meta --file "$STATE_FILE" --key flow_schema_version --value "$FLOW_SCHEMA_VERSION"
    state_cmd set-workflow-meta --file "$STATE_FILE" --key source_manifest --value "$FLOW_TEMPLATE_FILE"
fi
validate_workflow_state
if ! validate_workspace_artifacts; then
    if [[ "$RESUME_MODE" == true ]]; then
        log_warn "workspace 产物命名/指针校验失败；resume 模式下继续，让后续阶段修复。"
        "$BIN_DIR/validate-workspace-artifacts" --manifest "$FLOW_FILE" --workspace "$WORKSPACE_DIR" || true
    else
        log_error "workspace 产物命名/指针校验失败，请修订 $WORKSPACE_DIR"
        exit 1
    fi
fi

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
if [[ -n "$FLOW_FILE" ]]; then
    log_info "Flow:     $FLOW_FILE (schema v${FLOW_SCHEMA_VERSION})"
fi
log_info "Provider: $PROVIDER"
log_info "CLI:      $PROVIDER_CLI"
log_info "模型:     $(model_for_state "$MODEL")"
for phase in explore design review-plan revise implement review-code fix; do
    phase_model="$(get_phase_model "$phase")"
    if [[ "$phase_model" != "$MODEL" ]]; then
        log_info "模型覆盖: $phase=$phase_model"
    fi
done
log_info "自动模式: $AUTO_MODE"
detect_ghostty_window
if [[ -n "$GHOSTTY_WINDOW_ID" ]]; then
    log_info "Ghostty 窗口: $GHOSTTY_WINDOW_ID"
    state_cmd set-workflow-meta --file "$STATE_FILE" --key ghostty_window_id --value "$GHOSTTY_WINDOW_ID"
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
    local phase_model
    phase_model="$(get_phase_model "$skill_name")"

    # prompt 已由调用方通过 render_phase_prompt（bin/render-prompt --footer interactive）渲染好，
    # 完成状态指令包含在 _footer-interactive.md 里，这里只需落盘。
    local prompt_file
    prompt_file="$(render_phase_template "$skill_name" "prompt_file_template" "$phase_name" "$log_dir")"
    echo "$prompt" > "$prompt_file"

    # 构建在新 tab 中执行的脚本
    local started_marker
    local run_script
    started_marker="$(render_phase_template "$skill_name" "started_marker_template" "$phase_name" "$log_dir")"
    run_script="$(render_phase_template "$skill_name" "run_script_template" "$phase_name" "$log_dir")"
    local phase_started_epoch
    phase_started_epoch="$(date +%s)"
    "$BIN_DIR/render-phase-run-script" \
        --output "$run_script" \
        --provider "$PROVIDER" \
        --provider-cli "$PROVIDER_CLI" \
        --model "$phase_model" \
        --project-dir "$PROJECT_DIR" \
        --session-name "$session_name" \
        --prompt-file "$prompt_file" \
        --started-marker "$started_marker" \
        --workflow-state "$BIN_DIR/workflow-state" \
        --state-file "$STATE_FILE" \
        --phase "$phase_name" \
        --output-file "$output_file" \
        --resume-session-id "$resume_session_id" \
        --resume-session-name "$resume_session_name"

    state_cmd phase-start \
        --file "$STATE_FILE" \
        --phase "$phase_name" \
        --provider "$PROVIDER" \
        --model "$(model_for_state "$phase_model")" \
        --session-name "$session_name" \
        --output-file "$output_file" \
        --prompt-file "$prompt_file" \
        --run-script "$run_script" \
        --started-epoch "$phase_started_epoch"
    state_cmd set-workflow-meta --file "$STATE_FILE" --key current_phase --value "$phase_name"

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

    # 等待该阶段完成（轮询 workflow-state.json，而不是 marker 文件）
    log_info "等待 session 完成..."
    local phase_status
    local wait_iterations=0
    local waited_seconds=0
    local timeout_seconds=$((PHASE_TIMEOUT_MINUTES * 60))
    phase_status="$(state_cmd get-phase-status --file "$STATE_FILE" --phase "$phase_name" 2>/dev/null || true)"
    while [[ "$phase_status" == "running" ]]; do
        sleep 5
        wait_iterations=$((wait_iterations + 1))
        waited_seconds=$((wait_iterations * 5))
        phase_status="$(state_cmd get-phase-status --file "$STATE_FILE" --phase "$phase_name" 2>/dev/null || true)"

        if [[ "$phase_status" != "running" ]]; then
            break
        fi

        if (( timeout_seconds > 0 && waited_seconds >= timeout_seconds )); then
            state_cmd phase-finish \
                --file "$STATE_FILE" \
                --phase "$phase_name" \
                --status failed \
                --exit-code 124 \
                --output-file "$output_file"
            rm -f "${prompt_file}"
            log_error "$phase_name 等待超过 ${PHASE_TIMEOUT_MINUTES} 分钟，已标记 failed，exit=124"
            log_error "修复或确认 agent 状态后可用 --resume 继续。"
            exit 124
        fi

        if (( wait_iterations % 60 == 0 )); then
            local waited_minutes=$((waited_seconds / 60))
            echo ""
            echo -e "${YELLOW}[WAIT]${NC} 仍在等待 $phase_name 完成（已等待 ${waited_minutes}m）。"
            echo "  - 如 agent 已完成但忘了写状态，可手动执行:"
            echo "    \"$BIN_DIR/workflow-state\" phase-finish --file \"$STATE_FILE\" --phase \"$phase_name\" --status done --exit-code 0 --output-file \"$output_file\""
            echo "  - 如想放弃该阶段: 将 --status 改为 failed，编排器会退出并保留状态。"
        fi
    done

    local exit_code
    exit_code="$(state_cmd get-phase-field --file "$STATE_FILE" --phase "$phase_name" --key exit_code 2>/dev/null || true)"
    exit_code="${exit_code:-1}"
    rm -f "${prompt_file}"

    if [[ "$phase_status" != "done" && "$phase_status" != "skipped" ]]; then
        log_error "$phase_name 失败，exit=${exit_code}"
        exit 1
    fi
    state_cmd set-workflow-meta --file "$STATE_FILE" --key last_finished_phase --value "$phase_name"

    if [[ -f "$output_file" ]]; then
        if ! validate_phase_artifact "$skill_name" "$output_file"; then
            log_error "$phase_name 的产物未通过内容校验，请先修订 $output_file"
            exit 1
        fi
        if ! validate_workspace_artifacts; then
            log_error "$phase_name 完成后 workspace 产物命名/指针校验失败，请修订 $WORKSPACE_DIR"
            exit 1
        fi
        log_success "$phase_name 完成 → $output_file"
    else
        log_warn "$phase_name 完成，但输出文件未生成，请检查 ${log_dir}/${phase_name}.log"
    fi
}

run_analysis_phase() {
    local phase_name="$1"
    local skill_name="$2"
    local prompt="$3"
    local output_file="$4"
    local log_dir="$5"

    local session_name="${TASK_NAME}-${phase_name}"
    local phase_model
    phase_model="$(get_phase_model "$skill_name")"
    local prompt_file="${log_dir}/${phase_name}.prompt"
    local log_file="${log_dir}/${phase_name}.log"
    local phase_started_epoch
    phase_started_epoch="$(date +%s)"

    log_info "启动 analysis phase: $phase_name"
    log_info "Provider: $PROVIDER"
    log_info "输出文件: $output_file"

    # prompt 已由调用方通过 render_phase_prompt（bin/render-prompt --footer noninteractive）渲染好，
    # 非交互约束包含在 _footer-noninteractive.md 里，这里只需落盘。
    printf '%s' "$prompt" > "$prompt_file"

    state_cmd phase-start \
        --file "$STATE_FILE" \
        --phase "$phase_name" \
        --provider "$PROVIDER" \
        --model "$(model_for_state "$phase_model")" \
        --session-name "$session_name" \
        --output-file "$output_file" \
        --prompt-file "$prompt_file" \
        --run-script "$log_file" \
        --started-epoch "$phase_started_epoch"
    state_cmd set-workflow-meta --file "$STATE_FILE" --key current_phase --value "$phase_name"

    set +e
    "$BIN_DIR/run-provider-noninteractive" \
        --provider "$PROVIDER" \
        --provider-cli "$PROVIDER_CLI" \
        --model "$phase_model" \
        --project-dir "$PROJECT_DIR" \
        --workspace-dir "$WORKSPACE_DIR" \
        --prompt-file "$prompt_file" \
        --log-file "$log_file"
    local exit_code
    exit_code="$?"
    set -e

    local phase_status="done"
    if [[ "$exit_code" != "0" || ! -f "$output_file" ]]; then
        phase_status="failed"
    fi

    state_cmd phase-finish \
        --file "$STATE_FILE" \
        --phase "$phase_name" \
        --status "$phase_status" \
        --exit-code "$exit_code" \
        --output-file "$output_file"
    state_cmd set-workflow-meta --file "$STATE_FILE" --key last_finished_phase --value "$phase_name"

    rm -f "$prompt_file"

    if [[ "$phase_status" != "done" ]]; then
        log_error "$phase_name analysis phase 失败，exit=${exit_code}，日志: $log_file"
        if [[ -f "$log_file" ]]; then
            tail -80 "$log_file" || true
        fi
        exit 1
    fi

    if ! validate_phase_artifact "$skill_name" "$output_file"; then
        log_error "$phase_name 的产物未通过内容校验，请先修订 $output_file"
        exit 1
    fi

    log_success "$phase_name 完成 → $output_file"
}

# Resume 检查：state 已完成/跳过、产出存在且产物校验通过时才跳过该阶段
# 用法: should_skip_phase "phase_name" "output_file" && skip
should_skip_phase() {
    local phase_name="$1"
    local output_file="$2"
    local artifact_kind="${3:-$phase_name}"
    local phase_status
    if [[ "$RESUME_MODE" != true ]]; then
        return 1
    fi

    phase_status="$(state_cmd get-phase-status --file "$STATE_FILE" --phase "$phase_name" 2>/dev/null || true)"
    if [[ "$phase_status" != "done" && "$phase_status" != "skipped" ]]; then
        log_info "不跳过 ${phase_name}（state status=${phase_status:-missing}）"
        return 1
    fi
    if [[ ! -f "$output_file" ]]; then
        log_info "不跳过 ${phase_name}（缺少产出: $output_file）"
        return 1
    fi
    if ! validate_phase_artifact "$artifact_kind" "$output_file"; then
        log_warn "不跳过 ${phase_name}（产物校验失败: $output_file）"
        return 1
    fi

    log_info "跳过 ${phase_name}（state=${phase_status}，产物已校验: $(basename "$output_file")）"
    return 0
}

# ── Phase 1: Explore ──

EXPLORE_OUTPUT="$(phase_artifact_path "explore" "primary")"
if [[ "$PHASE_EXPLORE" == true ]] && ! should_skip_phase "explore" "$EXPLORE_OUTPUT"; then
    log_phase 1 "需求探索 (/explore)"

    # 确定探索输入：优先用 idea，其次用 requirement
    EXPLORE_INPUT=""
    if [[ -n "$EXPLORE_IDEA" ]]; then
        EXPLORE_INPUT="想法/方向：$EXPLORE_IDEA"
    elif [[ -f "$WORKSPACE_DIR/requirement.md" ]]; then
        EXPLORE_INPUT="参考需求文档 $WORKSPACE_DIR/requirement.md"
    fi

    EXPLORE_PROMPT="$(render_phase_prompt "explore" "interactive" "$EXPLORE_OUTPUT" "$EXPLORE_INPUT")"
    run_phase "explore" "explore" "$EXPLORE_PROMPT" "$EXPLORE_OUTPUT" "$DIR_EXPLORE"

    if [[ "$BP_AFTER_EXPLORE" == true ]]; then
        wait_for_user "探索阶段完成，请审阅探索报告" "$EXPLORE_OUTPUT"
    fi
fi

# ── Phase 2: Design ──

DESIGN_OUTPUT="$(phase_artifact_path "design" "primary")"
if [[ "$PHASE_DESIGN" == true ]] && ! should_skip_phase "design" "$DESIGN_OUTPUT"; then
    log_phase 2 "方案设计 (/design)"

    DESIGN_CONTEXT=""
    if [[ -f "$DIR_EXPLORE/exploration.md" ]]; then
        DESIGN_CONTEXT="探索报告在 $DIR_EXPLORE/exploration.md，请先阅读。"
    fi

    DESIGN_PROMPT="$(render_phase_prompt "design" "interactive" "$DESIGN_OUTPUT" "$DESIGN_CONTEXT")"
    run_phase "design" "design" "$DESIGN_PROMPT" "$DESIGN_OUTPUT" "$DIR_DESIGN"

    if [[ "$BP_AFTER_DESIGN" == true ]]; then
        wait_for_user "方案设计完成，请审阅技术方案" "$DESIGN_OUTPUT" "跳过方案评审，直接进入实现"
        if [[ "$WAIT_CHOICE" == "accept" ]]; then
            PHASE_REVIEW_PLAN=false
        fi
    fi
fi

# ── Phase 3: Review-Revise Loop ──
# 评审 → 修正 → 再评审，循环直到 VERDICT: PASS

REVIEW_ROUND=0
REVIEW_LATEST="$(phase_artifact_path "review-plan" "latest")"
REVIEW_RESUME_REVISE_ROUND=0

REVIEW_ALREADY_PASSED=false
if [[ "$RESUME_MODE" == true && -f "$REVIEW_LATEST" ]]; then
    if validate_phase_artifact "review-plan" "$REVIEW_LATEST" && artifact_verdict_is_pass "$REVIEW_LATEST"; then
        log_info "跳过 review（已有已校验 VERDICT: PASS）"
        REVIEW_ALREADY_PASSED=true
    else
        REVIEW_TRANSITION_RESUME="$(phase_transition_for_artifact "review-plan" "$REVIEW_LATEST" 2>/dev/null || true)"
        if [[ "$REVIEW_TRANSITION_RESUME" == "revise" ]]; then
            REVIEW_META_LOOP="$(get_workflow_meta current_loop)"
            REVIEW_META_ROUND="$(get_workflow_meta current_round)"
            if [[ "$REVIEW_META_LOOP" == "design-review" && "$REVIEW_META_ROUND" =~ ^[0-9]+$ && "$REVIEW_META_ROUND" -gt 0 ]]; then
                REVISE_RESUME_OUTPUT="$(phase_artifact_path "revise" "primary" "$REVIEW_META_ROUND")"
                if [[ -f "$REVISE_RESUME_OUTPUT" ]] && validate_phase_artifact "revise" "$REVISE_RESUME_OUTPUT"; then
                    REVIEW_ROUND="$REVIEW_META_ROUND"
                    log_info "resume: 第${REVIEW_META_ROUND}轮 revise 已存在，下一步从第$((REVIEW_META_ROUND + 1))轮 review-plan 继续"
                else
                    REVIEW_ROUND=$((REVIEW_META_ROUND - 1))
                    REVIEW_RESUME_REVISE_ROUND="$REVIEW_META_ROUND"
                    log_info "resume: 第${REVIEW_META_ROUND}轮 review-plan 已要求修正，直接进入 revise-r${REVIEW_META_ROUND}"
                fi
            fi
        fi
    fi
fi

if [[ "$PHASE_REVIEW_PLAN" == true && "$REVIEW_ALREADY_PASSED" == false ]]; then
    while true; do
        REVIEW_ROUND=$((REVIEW_ROUND + 1))
        if (( REVIEW_ROUND > MAX_ROUNDS )); then
            if handle_loop_limit "design-review" "$((REVIEW_ROUND - 1))"; then
                MAX_ROUNDS="$REVIEW_ROUND"
            else
                break
            fi
        fi
        state_cmd set-workflow-meta --file "$STATE_FILE" --key current_loop --value "design-review"
        state_cmd set-workflow-meta --file "$STATE_FILE" --key current_round --value "$REVIEW_ROUND"
        REVIEW_OUTPUT="$(phase_artifact_path "review-plan" "primary" "$REVIEW_ROUND")"
        REVISE_OUTPUT="$(phase_artifact_path "revise" "primary" "$REVIEW_ROUND")"
        PLAN_ROUND_OUTPUT="$DIR_DESIGN/plan-r${REVIEW_ROUND}.md"

        if [[ "$REVIEW_RESUME_REVISE_ROUND" == "$REVIEW_ROUND" ]]; then
            log_phase "3" "方案评审 第${REVIEW_ROUND}轮已完成（resume）"
            if [[ ! -f "$REVIEW_OUTPUT" && -f "$REVIEW_LATEST" ]]; then
                cp "$REVIEW_LATEST" "$REVIEW_OUTPUT"
            fi
            REVIEW_TRANSITION="revise"
        else
            log_phase "3" "方案评审 第${REVIEW_ROUND}轮 (/review-plan)"

            # 构建评审上下文：第 2 轮起告知评审者这是复审
            REVIEW_CONTEXT=""
            if [[ $REVIEW_ROUND -gt 1 ]]; then
                PREV_REVIEW_OUTPUT="$(phase_artifact_path "review-plan" "primary" "$((REVIEW_ROUND-1))")"
                PREV_REVISE_OUTPUT="$(phase_artifact_path "revise" "primary" "$((REVIEW_ROUND-1))")"
                REVIEW_CONTEXT="这是第${REVIEW_ROUND}轮评审。上一轮评审报告在 $PREV_REVIEW_OUTPUT，方案修正说明在 $PREV_REVISE_OUTPUT。请重点验证上轮提出的问题是否已修正到位，同时检查修正是否引入新问题。"
            fi

            REVIEW_PROMPT="$(render_phase_prompt "review-plan" "noninteractive" "$REVIEW_OUTPUT" "$REVIEW_CONTEXT" "$REVIEW_ROUND" "review-plan-r${REVIEW_ROUND}")"
            run_analysis_phase "review-plan-r${REVIEW_ROUND}" "review-plan" "$REVIEW_PROMPT" "$REVIEW_OUTPUT" "$DIR_REVIEW"

            # 保持 review.md 始终指向最新版
            cp "$REVIEW_OUTPUT" "$REVIEW_LATEST" 2>/dev/null || true
            if ! validate_workspace_artifacts; then
                log_error "review-plan 完成后 workspace 产物命名/指针校验失败，请修订 $WORKSPACE_DIR"
                exit 1
            fi

            # 检查评审结论
            REVIEW_TRANSITION="$(phase_transition_for_artifact "review-plan" "$REVIEW_OUTPUT")"
        fi
        state_cmd set-phase-field --file "$STATE_FILE" --phase "review-plan-r${REVIEW_ROUND}" --key round --value "$REVIEW_ROUND"
        state_cmd set-phase-field --file "$STATE_FILE" --phase "review-plan-r${REVIEW_ROUND}" --key loop --value "design-review"
        state_cmd set-phase-field --file "$STATE_FILE" --phase "review-plan-r${REVIEW_ROUND}" --key transition --value "$REVIEW_TRANSITION"
        if [[ "$REVIEW_TRANSITION" == "continue" ]]; then
            log_success "方案评审通过（第${REVIEW_ROUND}轮）"
            break
        fi
        if [[ "$REVIEW_TRANSITION" != "revise" ]]; then
            log_error "未知 review-plan transition: $REVIEW_TRANSITION"
            exit 1
        fi

        # 断点：让用户看评审结果
        if [[ "$BP_AFTER_REVIEW" == true && "$REVIEW_RESUME_REVISE_ROUND" != "$REVIEW_ROUND" ]]; then
            wait_for_user "第${REVIEW_ROUND}轮评审完成，方案需要修正" "$REVIEW_OUTPUT" "接受当前方案，跳过修正并进入实现"
            if [[ "$WAIT_CHOICE" == "accept" ]]; then
                break
            fi
        fi

        # ── Revise ──
        log_phase "3.5" "方案修正 第${REVIEW_ROUND}轮"

        REVISE_CONTEXT=""
        if [[ $REVIEW_ROUND -gt 1 ]]; then
            PREV_REVISE_OUTPUT="$(phase_artifact_path "revise" "primary" "$((REVIEW_ROUND-1))")"
            REVISE_CONTEXT="这是第${REVIEW_ROUND}轮修正。上一轮修正说明在 $PREV_REVISE_OUTPUT。"
        fi

        # revise 续接 design session（同一个 agent 修正自己的方案）
        REVISE_PROMPT="$(render_phase_prompt "revise" "interactive" "$REVISE_OUTPUT" "$REVISE_CONTEXT" "$REVIEW_ROUND" "revise-r${REVIEW_ROUND}")"
        run_phase "revise-r${REVIEW_ROUND}" "revise" "$REVISE_PROMPT" "$REVISE_OUTPUT" "$DIR_REVIEW" "design"
        state_cmd set-phase-field --file "$STATE_FILE" --phase "revise-r${REVIEW_ROUND}" --key round --value "$REVIEW_ROUND"
        state_cmd set-phase-field --file "$STATE_FILE" --phase "revise-r${REVIEW_ROUND}" --key loop --value "design-review"
        state_cmd set-phase-field --file "$STATE_FILE" --phase "revise-r${REVIEW_ROUND}" --key resume_from --value "design"

        # 保持 plan.md 始终指向最新版
        cp "$PLAN_ROUND_OUTPUT" "$DIR_DESIGN/plan.md" 2>/dev/null || true

        log_success "第${REVIEW_ROUND}轮方案修正完成，进入下一轮评审"
    done
fi

# ── Phase 4: Implement ──

IMPLEMENT_OUTPUT="$(phase_artifact_path "implement" "primary")"
if [[ "$PHASE_IMPLEMENT" == true ]] && ! should_skip_phase "implement" "$IMPLEMENT_OUTPUT"; then
    log_phase 4 "TDD 实现 (/implement)"

    IMPL_CONTEXT=""
    if [[ -f "$DIR_REVIEW/review.md" ]]; then
        IMPL_CONTEXT="评审反馈在 $DIR_REVIEW/review.md。"
    fi
    if [[ -n "${REVISE_OUTPUT:-}" && -f "$REVISE_OUTPUT" ]]; then
        IMPL_CONTEXT="${IMPL_CONTEXT}方案修正说明在 $REVISE_OUTPUT，注意哪些评审意见已被采纳。"
    fi

    IMPLEMENT_PROMPT="$(render_phase_prompt "implement" "interactive" "$IMPLEMENT_OUTPUT" "$IMPL_CONTEXT")"
    run_phase "implement" "implement" "$IMPLEMENT_PROMPT" "$IMPLEMENT_OUTPUT" "$DIR_IMPLEMENT"

    if [[ "$BP_AFTER_IMPLEMENT" == true ]]; then
        wait_for_user "实现完成，请审阅实现说明" "$IMPLEMENT_OUTPUT" "跳过代码评审，直接结束"
        if [[ "$WAIT_CHOICE" == "accept" ]]; then
            PHASE_REVIEW_CODE=false
        fi
    fi
fi

# ── Phase 5: Code Review-Fix Loop ──
# 代码评审 → 修复 → 再评审，循环直到 VERDICT: PASS

CODE_REVIEW_ROUND=0
CODE_REVIEW_LATEST="$(phase_artifact_path "review-code" "latest")"
CODE_REVIEW_RESUME_FIX_ROUND=0

CODE_REVIEW_ALREADY_PASSED=false
if [[ "$RESUME_MODE" == true && -f "$CODE_REVIEW_LATEST" ]]; then
    if validate_phase_artifact "review-code" "$CODE_REVIEW_LATEST" && artifact_verdict_is_pass "$CODE_REVIEW_LATEST"; then
        log_info "跳过 review-code（已有已校验 VERDICT: PASS）"
        CODE_REVIEW_ALREADY_PASSED=true
    else
        CODE_REVIEW_TRANSITION_RESUME="$(phase_transition_for_artifact "review-code" "$CODE_REVIEW_LATEST" 2>/dev/null || true)"
        if [[ "$CODE_REVIEW_TRANSITION_RESUME" == "fix" ]]; then
            CODE_REVIEW_META_LOOP="$(get_workflow_meta current_loop)"
            CODE_REVIEW_META_ROUND="$(get_workflow_meta current_round)"
            if [[ "$CODE_REVIEW_META_LOOP" == "code-review-fix" && "$CODE_REVIEW_META_ROUND" =~ ^[0-9]+$ && "$CODE_REVIEW_META_ROUND" -gt 0 ]]; then
                FIX_RESUME_OUTPUT="$(phase_artifact_path "fix" "primary" "$CODE_REVIEW_META_ROUND")"
                if [[ -f "$FIX_RESUME_OUTPUT" ]] && validate_phase_artifact "fix" "$FIX_RESUME_OUTPUT"; then
                    CODE_REVIEW_ROUND="$CODE_REVIEW_META_ROUND"
                    log_info "resume: 第${CODE_REVIEW_META_ROUND}轮 fix 已存在，下一步从第$((CODE_REVIEW_META_ROUND + 1))轮 review-code 继续"
                else
                    CODE_REVIEW_ROUND=$((CODE_REVIEW_META_ROUND - 1))
                    CODE_REVIEW_RESUME_FIX_ROUND="$CODE_REVIEW_META_ROUND"
                    log_info "resume: 第${CODE_REVIEW_META_ROUND}轮 review-code 已要求修复，直接进入 fix-r${CODE_REVIEW_META_ROUND}"
                fi
            fi
        fi
    fi
fi

if [[ "$PHASE_REVIEW_CODE" == true && "$CODE_REVIEW_ALREADY_PASSED" == false ]]; then
    while true; do
        CODE_REVIEW_ROUND=$((CODE_REVIEW_ROUND + 1))
        if (( CODE_REVIEW_ROUND > MAX_ROUNDS )); then
            if handle_loop_limit "code-review-fix" "$((CODE_REVIEW_ROUND - 1))"; then
                MAX_ROUNDS="$CODE_REVIEW_ROUND"
            else
                break
            fi
        fi
        state_cmd set-workflow-meta --file "$STATE_FILE" --key current_loop --value "code-review-fix"
        state_cmd set-workflow-meta --file "$STATE_FILE" --key current_round --value "$CODE_REVIEW_ROUND"
        CODE_REVIEW_OUTPUT="$(phase_artifact_path "review-code" "primary" "$CODE_REVIEW_ROUND")"
        FIX_OUTPUT="$(phase_artifact_path "fix" "primary" "$CODE_REVIEW_ROUND")"

        if [[ "$CODE_REVIEW_RESUME_FIX_ROUND" == "$CODE_REVIEW_ROUND" ]]; then
            log_phase "5" "代码评审 第${CODE_REVIEW_ROUND}轮已完成（resume）"
            if [[ ! -f "$CODE_REVIEW_OUTPUT" && -f "$CODE_REVIEW_LATEST" ]]; then
                cp "$CODE_REVIEW_LATEST" "$CODE_REVIEW_OUTPUT"
            fi
            CODE_REVIEW_TRANSITION="fix"
        else
            log_phase "5" "代码评审 第${CODE_REVIEW_ROUND}轮 (/review-code)"

            # 构建评审上下文：第 2 轮起告知评审者这是复审
            CODE_REVIEW_CONTEXT=""
            if [[ $CODE_REVIEW_ROUND -gt 1 ]]; then
                PREV_CODE_REVIEW_OUTPUT="$(phase_artifact_path "review-code" "primary" "$((CODE_REVIEW_ROUND-1))")"
                PREV_FIX_OUTPUT="$(phase_artifact_path "fix" "primary" "$((CODE_REVIEW_ROUND-1))")"
                CODE_REVIEW_CONTEXT="这是第${CODE_REVIEW_ROUND}轮代码评审。上一轮评审报告在 $PREV_CODE_REVIEW_OUTPUT，修复说明在 $PREV_FIX_OUTPUT。请重点验证上轮提出的必须修改项是否已修复到位，同时检查修复是否引入新问题。"
            fi

            CODE_REVIEW_PROMPT="$(render_phase_prompt "review-code" "noninteractive" "$CODE_REVIEW_OUTPUT" "$CODE_REVIEW_CONTEXT" "$CODE_REVIEW_ROUND" "review-code-r${CODE_REVIEW_ROUND}")"
            run_analysis_phase "review-code-r${CODE_REVIEW_ROUND}" "review-code" "$CODE_REVIEW_PROMPT" "$CODE_REVIEW_OUTPUT" "$DIR_REVIEW_CODE"

            # 保持 code-review.md 始终指向最新版
            cp "$CODE_REVIEW_OUTPUT" "$CODE_REVIEW_LATEST" 2>/dev/null || true
            if ! validate_workspace_artifacts; then
                log_error "review-code 完成后 workspace 产物命名/指针校验失败，请修订 $WORKSPACE_DIR"
                exit 1
            fi

            # 检查评审结论
            CODE_REVIEW_TRANSITION="$(phase_transition_for_artifact "review-code" "$CODE_REVIEW_OUTPUT")"
        fi
        state_cmd set-phase-field --file "$STATE_FILE" --phase "review-code-r${CODE_REVIEW_ROUND}" --key round --value "$CODE_REVIEW_ROUND"
        state_cmd set-phase-field --file "$STATE_FILE" --phase "review-code-r${CODE_REVIEW_ROUND}" --key loop --value "code-review-fix"
        state_cmd set-phase-field --file "$STATE_FILE" --phase "review-code-r${CODE_REVIEW_ROUND}" --key transition --value "$CODE_REVIEW_TRANSITION"
        if [[ "$CODE_REVIEW_TRANSITION" == "continue" ]]; then
            log_success "代码评审通过（第${CODE_REVIEW_ROUND}轮）"
            break
        fi
        if [[ "$CODE_REVIEW_TRANSITION" != "fix" ]]; then
            log_error "未知 review-code transition: $CODE_REVIEW_TRANSITION"
            exit 1
        fi

        # 断点：让用户看评审结果
        if [[ "$BP_AFTER_REVIEW_CODE" == true && "$CODE_REVIEW_RESUME_FIX_ROUND" != "$CODE_REVIEW_ROUND" ]]; then
            wait_for_user "第${CODE_REVIEW_ROUND}轮代码评审完成，代码需要修复" "$CODE_REVIEW_OUTPUT" "接受当前代码，跳过修复并结束评审循环"
            if [[ "$WAIT_CHOICE" == "accept" ]]; then
                break
            fi
        fi

        # ── Fix ──
        log_phase "5.5" "代码修复 第${CODE_REVIEW_ROUND}轮"

        FIX_CONTEXT=""
        if [[ $CODE_REVIEW_ROUND -gt 1 ]]; then
            PREV_FIX_OUTPUT="$(phase_artifact_path "fix" "primary" "$((CODE_REVIEW_ROUND-1))")"
            FIX_CONTEXT="这是第${CODE_REVIEW_ROUND}轮修复。上一轮修复说明在 $PREV_FIX_OUTPUT。"
        fi

        # fix 续接 implement session（同一个 agent 修复自己的代码）
        FIX_PROMPT="$(render_phase_prompt "fix" "interactive" "$FIX_OUTPUT" "$FIX_CONTEXT" "$CODE_REVIEW_ROUND" "fix-r${CODE_REVIEW_ROUND}")"
        run_phase "fix-r${CODE_REVIEW_ROUND}" "fix" "$FIX_PROMPT" "$FIX_OUTPUT" "$DIR_REVIEW_CODE" "implement"
        state_cmd set-phase-field --file "$STATE_FILE" --phase "fix-r${CODE_REVIEW_ROUND}" --key round --value "$CODE_REVIEW_ROUND"
        state_cmd set-phase-field --file "$STATE_FILE" --phase "fix-r${CODE_REVIEW_ROUND}" --key loop --value "code-review-fix"
        state_cmd set-phase-field --file "$STATE_FILE" --phase "fix-r${CODE_REVIEW_ROUND}" --key resume_from --value "implement"

        log_success "第${CODE_REVIEW_ROUND}轮代码修复完成，进入下一轮评审"
    done
fi
validate_workflow_state
validate_workspace_artifacts

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
    "$EXPLORE_OUTPUT|explore/exploration.md" \
    "$DESIGN_OUTPUT|design/plan.md" \
    "$DIR_DESIGN/implementation-brief.md|design/implementation-brief.md" \
    "$REVIEW_LATEST|review/review.md" \
    "$IMPLEMENT_OUTPUT|implement/impl-notes.md" \
    "$CODE_REVIEW_LATEST|review-code/code-review.md"; do
    full_path="${entry%%|*}"
    label="${entry##*|}"
    if [[ -f "$full_path" ]]; then
        echo -e "  ${GREEN}✓${NC} ${label}"
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
