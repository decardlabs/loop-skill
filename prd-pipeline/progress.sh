#!/bin/bash
# ============================================================
# progress.sh — 实时进度查看（支持项目布局 + 平面布局）
# ============================================================
# 用法:
#   ./progress.sh                           # 自动检测项目或平面布局
#   ./progress.sh --project <name>          # 查看指定项目进度
#   ./progress.sh <name>                    # 同上
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
load_agentrc "$SCRIPT_DIR"

# --- 参数解析 ---
PROJECT_ARG=""
proj_list=()
while [ $# -gt 0 ]; do
    case "$1" in
        --project) PROJECT_ARG="$2"; shift 2 ;;
        -h|--help) head -10 "$0"; exit 0 ;;
        *) PROJECT_ARG="$1"; shift ;;
    esac
done

# --- 确定搜索基础目录 ---
SEARCH_DIR="$SCRIPT_DIR"

if [ -n "$PROJECT_ARG" ]; then
    # 用户指定了项目名
    SEARCH_DIR="$SCRIPT_DIR/projects/$PROJECT_ARG"
    if [ ! -d "$SEARCH_DIR" ]; then
        err "项目不存在: $PROJECT_ARG (查找路径: $SEARCH_DIR)"
        exit 1
    fi
    bold "═══════════════════════════════════════════"
    bold "  项目进度报告: ${PROJECT_ARG}"
    bold "═══════════════════════════════════════════"
else
    # 自动检测：如果 projects/ 存在且有内容，取最新项目
    proj_list=()
    while IFS= read -r -d '' d; do
        proj_list+=("$d")
    done < <(find "$SCRIPT_DIR/projects" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)
    if [ ${#proj_list[@]} -gt 0 ]; then
        SEARCH_DIR="${proj_list[${#proj_list[@]}-1]}"
        PROJECT_ARG="$(basename "$SEARCH_DIR")"
        bold "═══════════════════════════════════════════"
        bold "  项目进度报告: ${PROJECT_ARG}"
        bold "═══════════════════════════════════════════"
    else
        bold "═══════════════════════════════════════════"
        bold "  PRD 管道 进度报告"
        bold "═══════════════════════════════════════════"
    fi
fi
echo ""

# 工具函数：尝试多个路径搜索文件
find_artifact() {
    local base="$1"  # 基础目录
    shift
    for name in "$@"; do
        local p="$base/$name"
        [ -f "$p" ] && echo "$p" && return 0
    done
    return 1
}

# ─── 层级1: PRD ───
prd_file=$(find_artifact "$SEARCH_DIR" "PRD.md" "PRD-example.md")
if [ -n "$prd_file" ]; then
    ok "  ✓ PRD: $(basename "$prd_file")"
else
    err "  ✗ PRD: 未找到"
fi

# ─── 层级2: SPEC ───
spec_file=$(find_artifact "$SEARCH_DIR/01-spec" "SPEC.md")
if [ -z "$spec_file" ]; then
    spec_file=$(find_artifact "$SEARCH_DIR" "SPEC.md" "*-SPEC.md")
fi
if [ -n "$spec_file" ]; then
    ok "  ✓ SPEC: $(basename "$spec_file") ($(wc -l < "$spec_file") 行)"
else
    err "  ✗ SPEC: 未生成"
fi

# ─── 层级3: Issues ───
issues_file=$(find_artifact "$SEARCH_DIR/02-issues" "ISSUES.md")
if [ -z "$issues_file" ]; then
    issues_file=$(find_artifact "$SEARCH_DIR" "ISSUES.md")
fi
if [ -n "$issues_file" ]; then
    ISSUE_COUNT=$(grep -c '^## ISSUE-' "$issues_file" 2>/dev/null || echo 0)
    ok "  ✓ ISSUES: $ISSUE_COUNT 个 Issue"
else
    err "  ✗ ISSUES: 未生成"
    ISSUE_COUNT=0
fi

# ─── 层级4: Tasks ───
TASK_DIR=""
for d in "$SEARCH_DIR/03-tasks" "$SEARCH_DIR/tasks"; do
    [ -d "$d" ] && TASK_DIR="$d" && break
done

TOTAL_TASKS=0; DONE_COUNT=0; FAIL_COUNT=0; PENDING_COUNT=0; RUNNING_COUNT=0
if [ -n "$TASK_DIR" ] && [ -d "$TASK_DIR" ]; then
    TASK_FILES=()
    while IFS= read -r -d '' f; do
        TASK_FILES+=("$f")
    done < <(find "$TASK_DIR" -maxdepth 1 -name 'TASK-*.md' -print0 2>/dev/null)
    TOTAL_TASKS=${#TASK_FILES[@]}
    if [ $TOTAL_TASKS -gt 0 ]; then
        for f in "${TASK_FILES[@]}"; do
            status=$(awk '/^status: /{print $2}' "$f")
            case "$status" in
                done)    DONE_COUNT=$((DONE_COUNT+1)) ;;
                failed)  FAIL_COUNT=$((FAIL_COUNT+1)) ;;
                running) RUNNING_COUNT=$((RUNNING_COUNT+1)) ;;
                *)       PENDING_COUNT=$((PENDING_COUNT+1)) ;;
            esac
        done
        ok    "  ✓ TASKS: 共 $TOTAL_TASKS 个 Task"
        ok    "    ✅ 完成:  $DONE_COUNT"
        [ $RUNNING_COUNT -gt 0 ] && warn "    ▶ 运行中: $RUNNING_COUNT"
        [ $PENDING_COUNT -gt 0 ] && warn "    ⏳ 待执行: $PENDING_COUNT"
        [ $FAIL_COUNT -gt 0 ]    && err "    ❌ 失败:   $FAIL_COUNT"

        if [ $TOTAL_TASKS -gt 0 ]; then
            PCT=$((DONE_COUNT * 100 / TOTAL_TASKS))
            BAR_LEN=30
            FILL=$((PCT * BAR_LEN / 100))
            EMPTY=$((BAR_LEN - FILL))
            printf "    进度: ["
            for ((i=0; i<FILL; i++)); do printf "█"; done
            for ((i=0; i<EMPTY; i++)); do printf "░"; done
            printf "] %d%%\n" $PCT
        fi
    else
        warn "  ○ TASKS: 目录存在但无 Task 文件"
    fi
else
    err "  ✗ TASKS: 目录不存在"
fi

# ─── 检查执行报告 ───
summary_file=$(find_artifact "$SEARCH_DIR/04-execution" "summary.md")
if [ -n "$summary_file" ]; then
    ok "  ✓ 报告: $summary_file"
fi

# ─── 整体状态 ───
echo ""
bold "────────────── 快速操作 ──────────────"
if [ -n "$PROJECT_ARG" ]; then
    [ -z "$spec_file" ]   && info "  生成 SPEC:    cd $SCRIPT_DIR && ./prd_to_spec.sh projects/${PROJECT_ARG}/PRD.md"
    [ -z "$issues_file" ] && info "  生成 Issues:  cd $SCRIPT_DIR && ./spec_to_issues.sh projects/${PROJECT_ARG}/01-spec/SPEC.md"
    [ $TOTAL_TASKS -eq 0 ] && [ -n "$issues_file" ] && info "  生成 Tasks:   cd $SCRIPT_DIR && ./issue_to_tasks.sh projects/${PROJECT_ARG}/01-spec/SPEC.md projects/${PROJECT_ARG}/02-issues/ISSUES.md"
    [ $PENDING_COUNT -gt 0 ] || [ $FAIL_COUNT -gt 0 ] && info "  执行 Tasks:   cd $SCRIPT_DIR && ./task_executor.sh"
    [ $FAIL_COUNT -gt 0 ]              && info "  重试失败:     cd $SCRIPT_DIR && ./task_executor.sh --retry-failed"
else
    [ -z "$spec_file" ]     && info "  生成 SPEC:    ./prd_to_spec.sh PRD.md"
    [ -z "$issues_file" ]   && info "  生成 Issues:  ./spec_to_issues.sh SPEC.md"
    [ $TOTAL_TASKS -eq 0 ] && [ -n "$issues_file" ] && info "  生成 Tasks:   ./issue_to_tasks.sh SPEC.md ISSUES.md"
    [ $PENDING_COUNT -gt 0 ] || [ $FAIL_COUNT -gt 0 ] && info "  执行 Tasks:   ./task_executor.sh"
    [ $FAIL_COUNT -gt 0 ]              && info "  重试失败:     ./task_executor.sh --retry-failed"
fi
bold "═══════════════════════════════════════════"
