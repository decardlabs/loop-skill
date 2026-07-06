#!/bin/bash
# ============================================================
# claude_loop.sh — 多轮循环调用 Claude Code 完成任务
# ============================================================
# 用法：
#   ./claude_loop.sh                     # 使用内置任务列表
#   ./claude_loop.sh task_list.txt       # 从文件读取任务
#   ./claude_loop.sh "单条prompt"        # 执行单条指令
# ============================================================
set -euo pipefail

CLAUDE="${CLAUDE:-claude}"
WORK_DIR="${WORK_DIR:-$(pwd)}"
LOG_DIR="${LOG_DIR:-./.claude_loop_logs}"
CLAUDE_OPTS="${CLAUDE_OPTS:---dangerously-skip-permissions}"

mkdir -p "$LOG_DIR"

# --------------- 颜色输出 ---------------
red()   { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
blue()  { printf "\033[34m%s\033[0m\n" "$*"; }

# --------------- 调用 Claude Code ---------------
run_claude() {
    local task="$1"
    local step_name="$2"
    local log_file="$LOG_DIR/${step_name//\//_}.log"
    local err_file="$LOG_DIR/${step_name//\//_}.err"

    blue "[${step_name}] 正在调用 Claude Code..."
    echo "$task" | $CLAUDE -p $CLAUDE_OPTS --no-session-persistence \
        >"$log_file" 2>"$err_file"

    local rc=${PIPESTATUS[1]}
    if [ $rc -eq 0 ]; then
        green "[${step_name}] ✓ 成功"
    else
        red   "[${step_name}] ✗ 失败 (exit=$rc)"
        echo "--- stderr ---" >&2
        cat "$err_file" >&2
    fi
    return $rc
}

# --------------- 内置任务模板 ---------------
builtin_tasks() {
    cat <<'TASKS'
步骤1: 读取当前项目结构，输出目录树到 project_tree.txt
步骤2: 分析 project_tree.txt，识别主要模块，输出到 modules.md
步骤3: 基于 modules.md 生成项目的 README.md
TASKS
}

# --------------- 主循环 ---------------
main() {
    local tasks=""
    local mode="list"

    # 确定任务来源
    if [ $# -eq 0 ]; then
        tasks="$(builtin_tasks)"
    elif [ -f "$1" ]; then
        tasks="$(cat "$1")"
    else
        tasks="$*"
        mode="single"
    fi

    cd "$WORK_DIR"
    echo "工作目录: $(pwd)"
    echo "日志目录: $LOG_DIR"
    echo ""

    if [ "$mode" = "single" ]; then
        # ---------- 单条指令模式 ----------
        run_claude "$tasks" "single_task"
        exit $?
    fi

    # ---------- 多步骤循环模式 ----------
    local total=0 success=0 fail=0
    local IFS=$'\n'
    for task in $tasks; do
        # 跳过空行
        [ -z "${task// }" ] && continue

        total=$((total + 1))
        local step_name="step_$(printf '%02d' $total)"

        if run_claude "$task" "$step_name"; then
            success=$((success + 1))
        else
            fail=$((fail + 1))
        fi
        echo ""
    done

    echo "========================================"
    green "任务完成: 总计 $total | 成功 $success | 失败 $fail"
    echo "日志目录: $LOG_DIR"
    echo "========================================"
    [ $fail -eq 0 ] && return 0 || return 1
}

main "$@"
