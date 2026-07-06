#!/bin/bash
# ============================================================
# prd_pipeline.sh — 主编排器：PRD → SPEC → Issues → Tasks → 执行 → 完成
# ============================================================
# 用法:
#   ./prd_pipeline.sh <PRD.md>                           # 全自动
#   MANUAL_APPROVAL=true ./prd_pipeline.sh PRD.md       # 每步前暂停确认
#   ./prd_pipeline.sh PRD.md --skip-to execute          # 跳过前面步骤直接执行
#   ./prd_pipeline.sh PRD.md --direct                   # 直接模式：每个 Issue 直接包装为 1 Task
#   ./prd_pipeline.sh PRD.md --granularity fine --direct # 细粒度+直接模式
#   ./prd_pipeline.sh PRD.md --target-dir /path/to/code  # 项目模式：中间文档归入 projects/
#   ./prd_pipeline.sh PRD.md --target-dir /path --project-name my-app  # 指定项目名
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
PRD_FILE=""
SKIP_UNTIL=""
DIRECT_MODE=false
GRANULARITY="${ISSUE_GRANULARITY:-medium}"
MANUAL_APPROVAL="${MANUAL_APPROVAL:-false}"

# --- 参数解析 ---
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-to)       SKIP_UNTIL="$2"; shift 2 ;;
        --direct)        DIRECT_MODE=true; shift ;;
        --granularity)   GRANULARITY="$2"; shift 2 ;;
        --target-dir)    TARGET_DIR="$2"; shift 2 ;;
        --project-name)  PROJECT_NAME="$2"; shift 2 ;;
        -h|--help) head -20 "$0"; exit 0 ;;
        *) PRD_FILE="$1"; shift ;;
    esac
done

if [ -z "$PRD_FILE" ]; then
    err "用法: $0 <PRD.md> [--skip-to spec|issues|tasks|execute]"
    exit 1
fi
if [ ! -f "$PRD_FILE" ]; then
    err "PRD 文件不存在: $PRD_FILE"
    exit 1
fi

PRD_FILE="$(cd "$(dirname "$PRD_FILE")" && pwd)/$(basename "$PRD_FILE")"

# 项目模式初始化
export TARGET_DIR="${TARGET_DIR:-}"
export PROJECT_NAME="${PROJECT_NAME:-}"
init_project_config
if [ -n "$TARGET_DIR" ]; then
    [ -d "$TARGET_DIR" ] || { err "目标目录不存在: $TARGET_DIR"; exit 1; }
    info "项目模式: $PROJECT_NAME → $TARGET_DIR"
    info "中间文档: $PROJECT_DIR/"
fi

approval() {
    $MANUAL_APPROVAL || return 0
    warn "━━━ 人工审核点 ━━━"
    warn "$1"
    printf "${YELLOW}继续执行? [Y/n]${NC} "
    read -r ans
    [[ "$ans" =~ ^[nN] ]] && err "已取消" && exit 1
    ok "通过"
}

# --- 步骤1: PRD → SPEC ---
step_spec() {
    [ "$SKIP_UNTIL" = "issues" ] || \
    [ "$SKIP_UNTIL" = "tasks" ] || [ "$SKIP_UNTIL" = "execute" ] && return 0

    info "步骤1/4: PRD → SPEC 技术规格拆解"
    approval "PRD: $(basename "$PRD_FILE")\n即将生成 SPEC.md，请确认 PRD 内容正确。"
    bash "$SCRIPT_DIR/prd_to_spec.sh" "$PRD_FILE"
    if [ -n "$SPEC_DIR" ]; then
        ok "SPEC.md → $SPEC_DIR/SPEC.md"
    else
        ok "SPEC.md 已生成"
    fi
    echo ""
}

# --- 步骤2: SPEC → Issues ---
step_issues() {
    [ "$SKIP_UNTIL" = "tasks" ] || \
    [ "$SKIP_UNTIL" = "execute" ] && return 0
    local spec_file=""
    if [ -n "$SPEC_DIR" ]; then
        spec_file="$SPEC_DIR/SPEC.md"
    else
        spec_file="${PRD_FILE%.md}-SPEC.md"
        [ -f "$spec_file" ] || spec_file="$SCRIPT_DIR/SPEC.md"
    fi
    [ -f "$spec_file" ] || { err "找不到 SPEC.md"; exit 1; }

    info "步骤2/4: SPEC → Issues 功能单元拆解"
    approval "即将基于 SPEC.md 拆解出 Issue 列表。"
    bash "$SCRIPT_DIR/spec_to_issues.sh" "$spec_file" --granularity "$GRANULARITY"
    if [ -n "$ISSUES_DIR" ]; then
        ok "ISSUES.md → $ISSUES_DIR/ISSUES.md"
    else
        ok "ISSUES.md 已生成"
    fi
    echo ""
}

# --- 步骤3: Issues → Tasks ---
step_tasks() {
    [ "$SKIP_UNTIL" = "execute" ] && return 0
    local spec_file=""
    if [ -n "$SPEC_DIR" ]; then
        spec_file="$SPEC_DIR/SPEC.md"
    else
        spec_file="${PRD_FILE%.md}-SPEC.md"
        [ -f "$spec_file" ] || spec_file="$SCRIPT_DIR/SPEC.md"
    fi
    [ -f "$spec_file" ] || { err "找不到 SPEC.md"; exit 1; }
    local issues_file=""
    if [ -n "$ISSUES_DIR" ]; then
        issues_file="$ISSUES_DIR/ISSUES.md"
    else
        issues_file="$SCRIPT_DIR/ISSUES.md"
    fi
    [ -f "$issues_file" ] || { err "找不到 ISSUES.md"; exit 1; }

    info "步骤3/4: Issues → Task 文件拆解"
    approval "即将为每个 Issue 拆解出可执行的 Task 文件。"
    local direct_flag=""
    [ "$DIRECT_MODE" = true ] && direct_flag="--direct"
    bash "$SCRIPT_DIR/issue_to_tasks.sh" "$spec_file" "$issues_file" $direct_flag
    if [ -n "$TASKS_DIR" ]; then
        ok "Task 文件 → $TASKS_DIR/"
    else
        ok "Task 文件已生成"
    fi
    echo ""
}

# --- 步骤4: 执行所有 Task ---
step_execute() {
    info "步骤4/4: 执行所有 Task"
    local task_search_dir="${TASKS_DIR:-$SCRIPT_DIR/tasks}"
    # null-safe 方式检查是否有 task 文件
    local found_task=false
    if [ -d "$task_search_dir" ]; then
        for _tf in "$task_search_dir"/TASK-*.md; do
            [ -f "$_tf" ] && { found_task=true; break; }
        done
    fi
    if [ "$found_task" = false ]; then
        # 也检查平面 tasks/ 目录
        if [ -n "$TASKS_DIR" ] && [ -d "$SCRIPT_DIR/tasks" ]; then
            for _tf in "$SCRIPT_DIR/tasks"/TASK-*.md; do
                [ -f "$_tf" ] && { task_search_dir="$SCRIPT_DIR/tasks"; found_task=true; break; }
            done
        fi
        if [ "$found_task" = false ]; then
            warn "没有找到 Task 文件，跳过执行"
            return 0
        fi
    fi
    approval "即将执行所有 Task，这会实际调用 Claude Code 修改代码。请确认项目目录正确。"
    bash "$SCRIPT_DIR/task_executor.sh"
    ok "所有 Task 执行完毕"
    echo ""
}

# --- 进度汇总 ---
summary() {
    echo ""
    info "═══════════════════════════════"
    info "  管道执行完成"
    info "═══════════════════════════════"
    if [ -n "$PROJECT_NAME" ]; then
        bash "$SCRIPT_DIR/progress.sh" --project "$PROJECT_NAME" 2>/dev/null || true
    else
        bash "$SCRIPT_DIR/progress.sh" 2>/dev/null || true
    fi
    echo ""
    info "产出物清单:"
    if [ -n "$PROJECT_DIR" ]; then
        [ -f "$SPEC_DIR/SPEC.md" ]   && ok "  $PROJECT_DIR/01-spec/SPEC.md  — 技术规格"
        [ -f "$ISSUES_DIR/ISSUES.md" ] && ok "  $PROJECT_DIR/02-issues/ISSUES.md  — Issue 列表"
        local tc=0
        for _f in "$TASKS_DIR"/TASK-*.md; do [ -f "$_f" ] && tc=$((tc+1)); done
        [ $tc -gt 0 ] && ok "  $TASKS_DIR/  — $tc 个 Task 文件"
        [ -f "$EXEC_DIR/summary.md" ] && ok "  $EXEC_DIR/summary.md  — 执行报告"
    else
        [ -f "$SCRIPT_DIR/SPEC.md" ]    && ok "  SPEC.md    — 技术规格"
        [ -f "$SCRIPT_DIR/ISSUES.md" ]  && ok "  ISSUES.md  — Issue 列表"
        local tc=0
        for _f in "$SCRIPT_DIR"/tasks/TASK-*.md; do [ -f "$_f" ] && tc=$((tc+1)); done
        [ $tc -gt 0 ] && ok "  tasks/     — $tc 个 Task 文件"
    fi
    echo ""
    info "下一步: ./progress.sh 查看详细进度"
}

# --- 主流程 ---
cd "$SCRIPT_DIR"
step_spec
step_issues
step_tasks
step_execute
summary
