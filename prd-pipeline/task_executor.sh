#!/bin/bash
# ============================================================
# task_executor.sh — Task 循环执行器（loop + 重试 + 断点续跑）
# ============================================================
# 用法:
#   ./task_executor.sh                          # 执行所有 pending task
#   ./task_executor.sh --resume                 # 断点续跑
#   ./task_executor.sh --retry-failed           # 重试失败的
#   ./task_executor.sh --tasks TASK-001,TASK-003 # 只跑指定的
#   ./task_executor.sh --parallel 3             # 最多 3 个并行
#   ./task_executor.sh --verify-ac             # 执行后验证验收标准
#   ./task_executor.sh --git-branch feat/task-1 # 自定义 git 分支名
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
# 加载 .agentrc（如果存在）
load_agentrc "$(dirname "$SCRIPT_DIR")"
init_project_config
if [ -n "$PROJECT_DIR" ]; then
    TASK_DIR="$TASKS_DIR"
    LOG_DIR="$EXEC_DIR/logs"
    BOARD_FILE="$TASK_DIR/task_board.md"
else
    TASK_DIR="$SCRIPT_DIR/tasks"
    LOG_DIR="$SCRIPT_DIR/logs/task_exec"
    BOARD_FILE="$TASK_DIR/task_board.md"
fi
MAX_RETRIES="${MAX_RETRIES:-3}"
PARALLEL="${PARALLEL:-1}"
MODE="all"
TASK_FILTER=""
VERIFY_AC=false
GIT_BRANCH=""
AGENT_CMD="${AGENT_CMD:-claude -p --dangerously-skip-permissions --no-session-persistence --output-format text}"

# ─── 参数解析 ───
while [ $# -gt 0 ]; do
    case "$1" in
        --resume)       MODE="resume"; shift ;;
        --retry-failed) MODE="retry-failed"; shift ;;
        --tasks)        MODE="filtered"; TASK_FILTER="$2"; shift 2 ;;
        --parallel)     PARALLEL="$2"; shift 2 ;;
        --verify-ac)    VERIFY_AC=true; shift ;;
        --git-branch)   GIT_BRANCH="$2"; shift 2 ;;
        -h|--help)      head -15 "$0"; exit 0 ;;
        *)              err "未知参数: $1"; exit 1 ;;
    esac
done

mkdir -p "$LOG_DIR"

# ─── YAML frontmatter 解析（纯 bash，不依赖 yq） ───
parse_frontmatter() {
    local file="$1"
    awk '
    BEGIN { in_fm=0; in_prompt=0; prompt_lines=0 }
    /^---$/ && !in_fm { in_fm=1; next }
    /^---$/ && in_fm  { in_fm=0; next }
    in_fm && !in_prompt {
        if ($0 ~ /^prompt: \|/) { in_prompt=1; next }
        if ($0 ~ /^prompt: /) {
            val=substr($0, index($0,":")+2)
            print "prompt:" val
            next
        }
        print
    }
    in_fm && in_prompt {
        if ($0 ~ /^  / || $0 ~ /^$/) {
            prompt_lines++
            print
        } else {
            in_prompt=0
            if ($0 ~ /^---$/) { in_fm=0 }
        }
    }
    ' "$file"
}

get_field() {
    local file="$1"; local field="$2"
    parse_frontmatter "$file" | grep "^${field}:" | sed "s/^${field}://" | sed 's/^ *//;s/ *$//' | head -1
}

get_prompt() {
    local file="$1"
    parse_frontmatter "$file" | awk '/^prompt:/{found=1; next} found{print}' | sed 's/^  //'
}

# ─── 读取所有 Task 的元数据 ───
load_tasks() {
    local files=("$@")
    TASK_IDS=(); TASK_FILES=(); TASK_STATUSES=(); TASK_DEPS=(); TASK_PROMPTS=(); TASK_ISSUES=(); TASK_ACS=()
    for f in "${files[@]}"; do
        local id status deps
        id=$(get_field "$f" "id")
        status=$(get_field "$f" "status")
        deps=$(get_field "$f" "dependencies" | sed 's/^\[//;s/\]$//;s/"//g')
        local issue ac
        issue=$(get_field "$f" "issue")
        ac=$(get_field "$f" "ac")
        local prompt
        prompt=$(get_prompt "$f")

        TASK_IDS+=("$id")
        TASK_FILES+=("$f")
        TASK_STATUSES+=("$status")
        TASK_DEPS+=("$deps")
        TASK_PROMPTS+=("$prompt")
        TASK_ISSUES+=("$issue")
        TASK_ACS+=("$ac")
    done
}

# ─── 拓扑排序（按依赖，兼容 bash 3.2，无 declare -A） ───
# 用平行数组模拟关联映射：keys[i] 存 idx, values[i] 存依赖字符串
topological_sort() {
    local indices=("$@")
    local visited=()
    local result=()
    local dep_keys=() dep_values=()

    # 构建依赖图（平行数组替代 associative array）
    for idx in "${indices[@]}"; do
        local dep_str="${TASK_DEPS[$idx]}"
        dep_str="$(echo "$dep_str" | sed 's/,/\n/g' | sed 's/^ *//;s/ *$//' | grep -v '^$' || true)"
        dep_keys+=("$idx")
        dep_values+=("$dep_str")
    done

    # 查找 key 对应的 value
    _get_dep() {
        local target="$1"
        for _di in "${!dep_keys[@]}"; do
            if [ "${dep_keys[$_di]}" = "$target" ]; then
                echo "${dep_values[$_di]}"
                return
            fi
        done
    }

    # DFS 拓扑排序
    dfs() {
        local idx=$1
        for v in "${visited[@]}"; do [ "$v" = "$idx" ] && return; done
        visited+=("$idx")
        local deps
        deps="$(_get_dep "$idx")"
        if [ -n "$deps" ]; then
            while IFS= read -r dep; do
                [ -z "$dep" ] && continue
                local dep_found=0
                for i in "${indices[@]}"; do
                    [ "${TASK_IDS[$i]}" = "$dep" ] && { dep_found=1; dfs $i; break; }
                done
                if [ $dep_found -eq 0 ]; then
                    warn "  ${TASK_IDS[$idx]}: 依赖 ${dep} 未找到，跳过依赖检查"
                fi
            done <<< "$deps"
        fi
        result+=("$idx")
    }

    for idx in "${indices[@]}"; do
        dfs $idx
    done
    echo "${result[@]}"
}

# ─── 更新单个 Task 文件的状态 ───
update_task_status() {
    local file="$1" new_status="$2"
    local tmp="${file}.tmp"
    awk -v ns="$new_status" '
    /^status: / { print "status: " ns; next }
    { print }
    ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# ─── 更新聚合看板 ───
update_board() {
    [ ! -f "$BOARD_FILE" ] && return
    local tmp="${BOARD_FILE}.tmp"
    {
        while IFS= read -r line; do
            if echo "$line" | grep -qE '^\| \[TASK-'; then
                local tid
                tid=$(echo "$line" | sed 's/| \[\(TASK-[0-9]*\)\].*/\1/')
                # 找到当前状态
                for i in "${!TASK_IDS[@]}"; do
                    if [ "${TASK_IDS[$i]}" = "$tid" ]; then
                        echo "| [${tid}](${tid}-*.md) | $(get_field "${TASK_FILES[$i]}" "ac" | head -c 40) | ${TASK_ISSUES[$i]} | ${TASK_STATUSES[$i]} |"
                        break
                    fi
                done
            else
                echo "$line"
            fi
        done < "$BOARD_FILE"
    } > "$tmp" && mv "$tmp" "$BOARD_FILE"
}

# ─── Git 变更跟踪 ───
get_git_head() {
    [ -z "$TARGET_DIR" ] && return 0
    [ ! -d "$TARGET_DIR/.git" ] && return 0
    (cd "$TARGET_DIR" && git rev-parse HEAD 2>/dev/null) || echo ""
}

capture_git_diff() {
    local task_log_dir="$1" head_before="$2"
    [ -z "$TARGET_DIR" ] && return 0
    [ ! -d "$TARGET_DIR/.git" ] && return 0
    local diff_stat="" diff_cached="" head_after="" commit_msg=""
    head_after="$(cd "$TARGET_DIR" && git rev-parse HEAD 2>/dev/null || echo "")"
    diff_stat="$(cd "$TARGET_DIR" && git diff --stat 2>/dev/null || true)"
    diff_cached="$(cd "$TARGET_DIR" && git diff --cached --stat 2>/dev/null || true)"
    # 如果 HEAD 变了（有新的 commit），用 commit-to-commit diff 作为补充
    local commit_diff=""
    if [ -n "$head_before" ] && [ -n "$head_after" ] && [ "$head_before" != "$head_after" ]; then
        commit_diff="$(cd "$TARGET_DIR" && git diff "$head_before".."$head_after" --stat 2>/dev/null || true)"
        commit_msg="$(cd "$TARGET_DIR" && git log "$head_before".."$head_after" --oneline 2>/dev/null || true)"
    fi
    {
        echo '{'
        echo '  "headBefore": "'"$head_before"'",'
        echo '  "headAfter": "'"$head_after"'",'
        echo '  "diffStat": "'"$(echo "$diff_stat" | tr '\n' ';' | sed 's/"/\\"/g')"'",'
        echo '  "diffCachedStat": "'"$(echo "$diff_cached" | tr '\n' ';' | sed 's/"/\\"/g')"'",'
        echo '  "commitDiff": "'"$(echo "$commit_diff" | tr '\n' ';' | sed 's/"/\\"/g')"'",'
        echo '  "commitMsg": "'"$(echo "$commit_msg" | tr '\n' ';' | sed 's/"/\\"/g')"'"'
        echo '}'
    } > "$task_log_dir/git_diff.json"
}

# ─── Git 分支管理 ───
# 在目标代码仓库中创建临时分支，每个 task 执行后自动 commit
# 保护基线分支不被污染，失败后可干净重置

GIT_RUN_BRANCH=""   # 实际使用的分支名（可能在运行时被赋值为自动名）

init_git_branch() {
    [ -z "$TARGET_DIR" ] && return 0
    [ ! -d "$TARGET_DIR/.git" ] && return 0
    if [ -n "$GIT_BRANCH" ]; then
        GIT_RUN_BRANCH="$GIT_BRANCH"
    else
        GIT_RUN_BRANCH="auto/task-run-$(date '+%Y%m%d-%H%M%S')"
    fi
    (
        cd "$TARGET_DIR"
        # 确保工作区干净（有未提交变更则 stash）
        if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
            git stash push -m "auto-stash before task-run $(date '+%Y%m%d-%H%M%S')" 2>/dev/null || true
        fi
        # 从当前 HEAD 创建分支
        git checkout -b "$GIT_RUN_BRANCH" 2>/dev/null || \
        git checkout "$GIT_RUN_BRANCH" 2>/dev/null || {
            warn "  Git: 无法创建/切换分支 $GIT_RUN_BRANCH"
            GIT_RUN_BRANCH=""
            return 1
        }
        ok "  Git: 分支 $GIT_RUN_BRANCH 就绪"
    )
}

# 每个 task 成功后提交变更
git_commit_task() {
    local id="$1" issue="$2" ac="$3" ac_res="$4"
    [ -z "$TARGET_DIR" ] && return 0
    [ ! -d "$TARGET_DIR/.git" ] && return 0
    [ -z "$GIT_RUN_BRANCH" ] && return 0
    (
        cd "$TARGET_DIR"
        # 如果没有变更，跳过
        if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
            return 0
        fi
        git add -A
        local commit_msg="${id}: ${issue}"
        [ -n "$ac_res" ] && commit_msg="${commit_msg}

ac: ${ac_res}"
        git commit -m "$commit_msg" >/dev/null 2>&1
        local chash="$(git rev-parse --short HEAD 2>/dev/null || echo "")"
        ok "  Git: 已提交 ${id} → commit ${chash} (${GIT_RUN_BRANCH})"
    )
}

# 失败后清理工作区
git_cleanup_after_failure() {
    [ -z "$TARGET_DIR" ] && return 0
    [ ! -d "$TARGET_DIR/.git" ] && return 0
    [ -z "$GIT_RUN_BRANCH" ] && return 0
    (
        cd "$TARGET_DIR"
        git checkout . 2>/dev/null || true
        git clean -fd 2>/dev/null || true
    )
}

# ─── 质量门禁：自动运行测试 ───
# 返回: "pass|fail|skip:test_count:fail_count:summary_text"
run_quality_gates() {
    local task_id="$1" task_log_dir="$2"
    local result="skip:0:0:no_tests"

    # 检测并运行测试
    local test_cmd
    test_cmd="$(detect_test_command)"
    if [ -z "$test_cmd" ]; then
        echo "$result"
        return 0
    fi

    info "    ${task_id}: 质量门禁 — 运行测试..."
    local test_out="$task_log_dir/test_output.log"
    eval "$test_cmd" > "$test_out" 2>&1 || true

    local pass_count=0 fail_count=0
    pass_count="$(grep -cE '^(PASS|\.|ok|✓|✅)' "$test_out" 2>/dev/null || echo 0)"
    fail_count="$(grep -cE '^(FAIL|ERROR|✗|❌|failed)' "$test_out" 2>/dev/null || echo 0)"
    # 更准确：从 pytest 输出提取
    if grep -qE 'passed|failed' "$test_out" 2>/dev/null; then
        pass_count="$(grep -oE '[0-9]+ passed' "$test_out" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo 0)"
        fail_count="$(grep -oE '[0-9]+ failed' "$test_out" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo 0)"
    fi

    if [ "$fail_count" -gt 0 ]; then
        warn "    ${task_id}: ⚠️ 测试 ${fail_count} 个失败"
        result="fail:${pass_count}:${fail_count}:$(tail -3 "$test_out" 2>/dev/null | tr '\n' ' ' | head -c 100)"
    else
        ok "    ${task_id}: ✅ 测试 ${pass_count} 个通过"
        result="pass:${pass_count}:0:all_passed"
    fi

    echo "$result"
}

# ─── 生成 delta spec（OpenSpec 格式） ───
generate_delta_spec() {
    local task_id="$1" task_log_dir="$2" target_dir="${3:-}"
    local delta_file="$task_log_dir/delta_spec.md"
    {
        echo "## Task ${task_id}"
        echo ""
        echo "### ADDED Requirements"
        echo "- 由 task ${task_id} 实现"
        echo ""
        echo "### MODIFIED Requirements"
        echo "- （需从 git diff 推断具体变更）"
        echo ""
        echo "### 变更文件"
        if [ -f "$task_log_dir/git_diff.json" ]; then
            awk -F'"' '/commitDiff/{print $4}' "$task_log_dir/git_diff.json" | tr ';' '\n' | sed 's/^/- /'
        fi
    } > "$delta_file"
    echo "$delta_file"
}

# ─── 构建目标上下文块（运行时注入） ───
build_task_target_ctx() {
    [ -z "$TARGET_DIR" ] && return 0
    local stack_info="$(detect_tech_stack)"
    echo "## 目标项目
项目路径: ${TARGET_DIR}
项目名称: ${PROJECT_NAME}
技术栈: ${stack_info}
"
}

# ─── 执行单个 Task ───
execute_task() {
    local idx=$1
    local id="${TASK_IDS[$idx]}"
    local file="${TASK_FILES[$idx]}"
    local prompt="${TASK_PROMPTS[$idx]}"
    local ac="${TASK_ACS[$idx]}"

    local task_log_dir="$LOG_DIR/${id}"
    mkdir -p "$task_log_dir"

    local status="${TASK_STATUSES[$idx]}"
    # 跳过已完成（除非 --retry-failed）
    if [ "$status" = "done" ] && [ "$MODE" != "retry-failed" ]; then
        ok "  ${id}: 已完成，跳过"
        return 0
    fi

    info "  ▶ ${id}: ${TASK_ISSUES[$idx]}"
    info "    验收: ${ac}"

    update_task_status "$file" "running"
    TASK_STATUSES[$idx]="running"
    update_board

    # Feature B: 运行时注入目标上下文（不修改 task 文件）
    local target_ctx="$(build_task_target_ctx)"
    local actual_prompt="${target_ctx}${prompt}"

    # Feature C: 记录 git HEAD
    local head_before="$(get_git_head)"

    local retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        local attempt=$((retries + 1))
        local log_file="$task_log_dir/run_${attempt}.log"
        local err_file="$task_log_dir/run_${attempt}.err"

        info "    尝试 #${attempt}/${MAX_RETRIES}..."

        echo "$actual_prompt" | \
            eval "$AGENT_CMD" \
                >"$log_file" 2>"$err_file"

        local rc=${PIPESTATUS[1]}
        if [ $rc -eq 0 ]; then
            ok "  ✓ ${id}: 成功 (attempt #${attempt})"

            # Git: 先 commit，再捕捉 diff（这样 git_diff.json 包含 commit hash）
            local ac_res="skipped"
            if [ "$VERIFY_AC" = true ] && [ -n "$ac" ]; then
                info "    ${id}: 验证验收标准..."
                local verify_prompt="请验证以下验收标准是否已满足：\n\n${ac}\n\n请在项目 ${TARGET_DIR} 中检查实际代码和运行结果。只回答 PASS/FAIL/UNKNOWN 和简短理由。"
                local verify_out="$task_log_dir/ac_verify.log"
                echo "$verify_prompt" | \
                    eval "$AGENT_CMD" \
                    >"$verify_out" 2>>"$err_file"
                if grep -qi 'PASS' "$verify_out" 2>/dev/null; then
                    ac_res="passed"; ok "    ${id}: AC 验证通过"
                elif grep -qi 'FAIL' "$verify_out" 2>/dev/null; then
                    ac_res="failed"; warn "    ${id}: AC 验证失败"
                else
                    ac_res="unknown"; warn "    ${id}: AC 验证结果不确定"
                fi
                echo "{\"ac_result\":\"$ac_res\"}" > "$task_log_dir/ac_verify.json"
            fi
            git_commit_task "$id" "${TASK_ISSUES[$idx]}" "$ac" "$ac_res"

            # Feature C: 捕捉 git diff（commit 后，git_diff.json 包含 commit hash）
            capture_git_diff "$task_log_dir" "$head_before"

            # 质量门禁：自动运行测试（不阻塞 pipeline）
            local gate_result="$(run_quality_gates "$id" "$task_log_dir")"
            echo "$gate_result" > "$task_log_dir/quality_gate.txt"

            # 生成 delta spec（OpenSpec 格式）
            generate_delta_spec "$id" "$task_log_dir" "$TARGET_DIR" > /dev/null

            update_task_status "$file" "done"
            TASK_STATUSES[$idx]="done"
            update_board
            return 0
        fi

        warn "    ${id}: 失败 (attempt #${attempt}, exit=$rc)"
        warn "    stderr: $(tail -3 "$err_file" 2>/dev/null | tr '\n' ' ')"

        retries=$((retries + 1))
        if [ $retries -lt $MAX_RETRIES ]; then
            # 重试也注入目标上下文
            actual_prompt="${actual_prompt}

注意：之前的尝试失败了。请换一种实现方式，避免重复同样的错误。"
            info "    等待 3 秒后重试..."
            sleep 3
        fi
    done

    # 失败也捕捉 git diff（可能改了部分代码）
    capture_git_diff "$task_log_dir" "$head_before"
    # Git: 清理失败产物
    git_cleanup_after_failure

    err "  ✗ ${id}: 已达最大重试次数 (${MAX_RETRIES})"
    update_task_status "$file" "failed"
    TASK_STATUSES[$idx]="failed"
    update_board
    return 1
}

# ─── 并发控制（受控并行） ───
# 简单实现: 按依赖层次分批串行，同一层内可并行
# 更精确的并发控制用 GNU parallel，这里保持 bash 原生兼容
execute_batch() {
    local batch_indices=("$@")

    if [ "$PARALLEL" -le 1 ]; then
        # 串行执行
        for idx in "${batch_indices[@]}"; do
            execute_task "$idx" || true
        done
    else
        # 并行执行（后台进程 + wait）
        local running=0 pids=()
        for idx in "${batch_indices[@]}"; do
            execute_task "$idx" &
            pids+=($!)
            running=$((running + 1))
            if [ $running -ge "$PARALLEL" ]; then
                wait "${pids[@]}" 2>/dev/null || true
                running=0; pids=()
            fi
        done
        wait 2>/dev/null || true
    fi
}

# ─── 按依赖层级分批（兼容 bash 3.2，无 declare -A） ───
batch_by_dependency_level() {
    local sorted_indices=("$@")
    local lkeys=() lvals=()
    local max_level=0

    # 平行数组替代 associative array: lkeys[i]=idx, lvals[i]=level
    _set_level() { local k=$1 v=$2; lkeys+=("$k"); lvals+=("$v"); }
    _get_level() {
        local k=$1
        for _li in "${!lkeys[@]}"; do
            [ "${lkeys[$_li]}" = "$k" ] && { echo "${lvals[$_li]}"; return; }
        done
        echo "-1"
    }

    for idx in "${sorted_indices[@]}"; do
        local dep_str="${TASK_DEPS[$idx]}"
        if [ -z "$dep_str" ] || [ "$dep_str" = "[]" ]; then
            _set_level "$idx" 0
        else
            local lev=0
            while IFS= read -r dep; do
                [ -z "$dep" ] && continue
                for i in "${sorted_indices[@]}"; do
                    if [ "${TASK_IDS[$i]}" = "$dep" ] || [ "${TASK_IDS[$i]}" = "$dep" ]; then
                        local dl=$(_get_level "$i")
                        [ "$dl" -lt 0 ] && dl=0
                        [ $((dl + 1)) -gt $lev ] && lev=$((dl + 1))
                    fi
                done
            done <<< "$(echo "$dep_str" | tr ',' '\n' | sed 's/^ *//;s/ *$//')"
            _set_level "$idx" "$lev"
        fi
        local this_lv=$(_get_level "$idx")
        [ "$this_lv" -gt "$max_level" ] && max_level="$this_lv"
    done

    for lv in $(seq 0 $max_level); do
        local batch=()
        for idx in "${sorted_indices[@]}"; do
            [ "$(_get_level "$idx")" -eq "$lv" ] && batch+=("$idx")
        done
        if [ ${#batch[@]} -gt 0 ]; then
            echo ""
            info "═══════ 依赖层级 ${lv} (${#batch[@]} 个 Task) ═══════"
            execute_batch "${batch[@]}"
        fi
    done
}

# ═══════════════════════════════════════════
#  主执行逻辑
# ═══════════════════════════════════════════

info "Task 目录: $TASK_DIR"
info "最大重试: ${MAX_RETRIES}"
info "并行数:   ${PARALLEL}"
info "模式:     ${MODE}"
if [ -n "$TARGET_DIR" ] && [ -d "$TARGET_DIR/.git" ]; then
    init_git_branch
fi
echo ""

# 扫描
ALL_FILES=()
while IFS= read -r -d '' f; do
    ALL_FILES+=("$f")
done < <(find "$TASK_DIR" -maxdepth 1 -name 'TASK-*.md' -print0 | sort -z)
if [ ${#ALL_FILES[@]} -eq 0 ]; then
    err "没有找到 Task 文件 (${TASK_DIR}/TASK-*.md)"
    exit 1
fi
info "共 ${#ALL_FILES[@]} 个 Task 文件"

# 加载元数据
load_tasks "${ALL_FILES[@]}"

# 筛选要执行的 Task
SELECTED_INDICES=()
case "$MODE" in
    all|resume)
        for i in "${!TASK_IDS[@]}"; do
            if [ "${TASK_STATUSES[$i]}" = "pending" ] || [ "${TASK_STATUSES[$i]}" = "failed" ]; then
                SELECTED_INDICES+=("$i")
            fi
        done
        ;;
    retry-failed)
        for i in "${!TASK_IDS[@]}"; do
            if [ "${TASK_STATUSES[$i]}" = "failed" ]; then
                SELECTED_INDICES+=("$i")
            fi
        done
        ;;
    filtered)
        IFS=',' read -ra FILTER_ARRAY <<< "$TASK_FILTER"
        for filter_id in "${FILTER_ARRAY[@]}"; do
            filter_id="$(echo "$filter_id" | sed 's/^ *//;s/ *$//')"
            for i in "${!TASK_IDS[@]}"; do
                if [ "${TASK_IDS[$i]}" = "$filter_id" ]; then
                    SELECTED_INDICES+=("$i")
                fi
            done
        done
        # 去重
        SELECTED_INDICES=($(echo "${SELECTED_INDICES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
        ;;
esac

if [ ${#SELECTED_INDICES[@]} -eq 0 ]; then
    ok "没有待执行的 Task"
    exit 0
fi

info "待执行: ${#SELECTED_INDICES[@]} 个 Task"

# 拓扑排序
SORTED=($(topological_sort "${SELECTED_INDICES[@]}"))
info "执行顺序（拓扑排序）:"
for idx in "${SORTED[@]}"; do
    info "  ${TASK_IDS[$idx]} ← ${TASK_DEPS[$idx]:-无}"
done

# 按依赖层级分批执行
batch_by_dependency_level "${SORTED[@]}"

# ─── 生成结构化报告 ───
generate_summary() {
    local md_file="" json_file=""
    if [ -n "$EXEC_DIR" ]; then
        md_file="$EXEC_DIR/summary.md"
        json_file="$EXEC_DIR/summary.json"
    else
        md_file="$LOG_DIR/summary.md"
        json_file="$LOG_DIR/summary.json"
    fi

    local dc=0 fc=0 pc=0
    for s in "${TASK_STATUSES[@]}"; do
        case "$s" in done) dc=$((dc+1));; failed) fc=$((fc+1));; *) pc=$((pc+1));; esac
    done

    # 获取 git 分支信息
    local run_branch="${GIT_RUN_BRANCH:-}"
    local git_commits=""
    if [ -n "$run_branch" ] && [ -n "$TARGET_DIR" ] && [ -d "$TARGET_DIR/.git" ]; then
        git_commits="$(cd "$TARGET_DIR" && git log --oneline "${run_branch}" 2>/dev/null | head -20 || true)"
    fi

    # JSON 报告
    {
        echo '{'
        echo '  "projectName": "'"${PROJECT_NAME:-}"'",'
        echo '  "targetDir": "'"${TARGET_DIR:-}"'",'
        echo '  "gitBranch": "'"$run_branch"'",'
        echo '  "generatedAt": "'"$(date '+%Y-%m-%dT%H:%M:%S')"'",'
        echo '  "summary": { "done": '"$dc"', "failed": '"$fc"', "pending": '"$pc"' },'
        echo '  "tasks": ['
        local first=true
        for i in "${!TASK_IDS[@]}"; do
            $first || echo ','
            first=false
            local fail_reason=""
            if [ "${TASK_STATUSES[$i]}" = "failed" ]; then
                for ef in "$LOG_DIR/${TASK_IDS[$i]}"/run_*.err; do
                    [ -f "$ef" ] && fail_reason="$(tail -5 "$ef" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g')"
                done
            fi
            local ac_res="skipped"
            [ -f "$LOG_DIR/${TASK_IDS[$i]}/ac_verify.json" ] && ac_res="$(awk -F'"' '/ac_result/{print $4}' "$LOG_DIR/${TASK_IDS[$i]}/ac_verify.json")"
            # 读取该 task 的 commit hash
            local task_commit=""
            [ -f "$LOG_DIR/${TASK_IDS[$i]}/git_diff.json" ] && task_commit="$(awk -F'"' '/headAfter/{print $4}' "$LOG_DIR/${TASK_IDS[$i]}/git_diff.json" | head -c 8)"
            # 读取质量门禁结果
            local gate_res=""
            [ -f "$LOG_DIR/${TASK_IDS[$i]}/quality_gate.txt" ] && gate_res="$(cat "$LOG_DIR/${TASK_IDS[$i]}/quality_gate.txt" | cut -d: -f1)"
            echo -n '    {"id":"'"${TASK_IDS[$i]}"'","issue":"'"${TASK_ISSUES[$i]}"'","status":"'"${TASK_STATUSES[$i]}"'","acResult":"'"$ac_res"'","commit":"'"$task_commit"'","gateResult":"'"$gate_res"'","failReason":"'"$fail_reason"'"}'
        done
        echo ''
        echo '  ]'
        echo '}'
    } > "$json_file"

    # Markdown 报告
    {
        echo "# 执行报告: ${PROJECT_NAME:-pipeline}"
        echo ""
        if [ -n "$TARGET_DIR" ]; then
            echo "**目标项目:** \`$TARGET_DIR\`"
            echo ""
        fi
        echo "**生成时间:** $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        if [ -n "$run_branch" ]; then
            echo "**Git 分支:** \`$run_branch\`"
            echo ""
        fi
        echo "## 概览"
        echo ""
        echo "| 状态 | 数量 |"
        echo "|------|------|"
        echo "| ✅ 完成 | $dc |"
        echo "| ❌ 失败 | $fc |"
        echo "| ⏳ 剩余 | $pc |"
        echo ""

        if [ $fc -gt 0 ]; then
            echo "## 失败分析"
            echo ""
            for i in "${!TASK_IDS[@]}"; do
                [ "${TASK_STATUSES[$i]}" != "failed" ] && continue
                local reason=""
                for ef in "$LOG_DIR/${TASK_IDS[$i]}"/run_*.err; do
                    [ -f "$ef" ] && reason="$(tail -5 "$ef" 2>/dev/null | tr '\n' ' ' | head -c 200)"
                done
                local diff_files=""
                [ -f "$LOG_DIR/${TASK_IDS[$i]}/git_diff.json" ] && diff_files="$(awk -F'"' '/commitDiff/{print $4}' "$LOG_DIR/${TASK_IDS[$i]}/git_diff.json" | head -c 100)"
                echo "- **${TASK_IDS[$i]}** (${TASK_ISSUES[$i]})"
                [ -n "$reason" ] && echo "  - 错误: ${reason}"
                [ -n "$diff_files" ] && echo "  - 已变更: ${diff_files}"
            done
            echo ""
            echo "## 下一步建议"
            echo ""
            echo "重试失败的 Task:"
            echo '```bash'
            echo "cd $(dirname "$0") && ./task_executor.sh --retry-failed"
            echo '```'
            echo "单独重试特定 Task:"
            echo '```bash'
            for i in "${!TASK_IDS[@]}"; do
                [ "${TASK_STATUSES[$i]}" = "failed" ] && echo "./task_executor.sh --tasks ${TASK_IDS[$i]}"
            done
            echo '```'
        fi

        if [ $dc -gt 0 ]; then
            echo "## 已完成 Task"
            echo ""
            echo "| Task | Issue | Commit | Tests | 文件变更 |"
            echo "|------|-------|--------|-------|----------|"
            for i in "${!TASK_IDS[@]}"; do
                [ "${TASK_STATUSES[$i]}" != "done" ] && continue
                local task_commit="—"
                local changes="—"
                local gate_display="—"
                if [ -f "$LOG_DIR/${TASK_IDS[$i]}/git_diff.json" ]; then
                    changes="$(awk -F'"' '/commitDiff/{print $4}' "$LOG_DIR/${TASK_IDS[$i]}/git_diff.json" | head -c 80)"
                    task_commit="$(awk -F'"' '/headAfter/{print $4}' "$LOG_DIR/${TASK_IDS[$i]}/git_diff.json" | head -c 8)"
                fi
                if [ -f "$LOG_DIR/${TASK_IDS[$i]}/quality_gate.txt" ]; then
                    local _gr="$(cat "$LOG_DIR/${TASK_IDS[$i]}/quality_gate.txt" | cut -d: -f1)"
                    [ "$_gr" = "pass" ] && gate_display="✅"
                    [ "$_gr" = "fail" ] && gate_display="⚠️"
                    [ "$_gr" = "skip" ] && gate_display="—"
                fi
                [ -z "$changes" ] && changes="—"
                [ -z "$task_commit" ] && task_commit="—"
                echo "| ${TASK_IDS[$i]} | ${TASK_ISSUES[$i]} | \`${task_commit}\` | ${gate_display} | ${changes} |"
            done
            echo ""
        fi

        # Git 分支管理建议
        if [ -n "$run_branch" ] && [ -n "$TARGET_DIR" ] && [ -d "$TARGET_DIR/.git" ]; then
            echo "## Git 版本管理"
            echo ""
            echo "所有成功的 Task 已在分支 \`${run_branch}\` 上独立提交。"
            echo ""
            if [ $fc -eq 0 ] && [ $dc -gt 0 ]; then
                echo "全部任务成功，合并到主分支："
                echo '```bash'
                echo "cd $TARGET_DIR"
                echo "git checkout main"
                echo "git merge $run_branch"
                echo "git branch -d $run_branch"
                echo '```'
                echo ""
                echo "提交历史："
                echo '```'
                echo "$git_commits"
                echo '```'
            elif [ $fc -gt 0 ]; then
                echo "有失败的 Task。建议先 cherry-pick 成功提交到主分支，再修复重试失败的任务："
                echo '```bash'
                echo "cd $TARGET_DIR"
                echo "git checkout main"
                for i in "${!TASK_IDS[@]}"; do
                    [ "${TASK_STATUSES[$i]}" != "done" ] && continue
                    local ch=""
                    [ -f "$LOG_DIR/${TASK_IDS[$i]}/git_diff.json" ] && ch="$(awk -F'"' '/headAfter/{print $4}' "$LOG_DIR/${TASK_IDS[$i]}/git_diff.json" | head -c 8)"
                    [ -n "$ch" ] && echo "git cherry-pick $ch"
                done
                echo '```'
                echo ""
                echo "修复失败任务后重跑："
                echo '```bash'
                echo "cd $(dirname "$0") && ./task_executor.sh --retry-failed"
                echo '```'
            fi
        fi
    } > "$md_file"

    info "报告已生成: $md_file"
}

# ─── 最终汇总 ───
echo ""
info "═══════════════════════════════════════"
info "  执行完毕"
info "═══════════════════════════════════════"
local done_count=0 fail_count=0 pending_count=0
for s in "${TASK_STATUSES[@]}"; do
    case "$s" in
        done)    done_count=$((done_count+1)) ;;
        failed)  fail_count=$((fail_count+1)) ;;
        pending) pending_count=$((pending_count+1)) ;;
    esac
done
ok   "  ✅ 完成: ${done_count}"
err  "  ❌ 失败: ${fail_count}" 2>/dev/null || true
warn "  ⏳ 剩余: ${pending_count}"
if [ -n "$GIT_RUN_BRANCH" ]; then
    ok   "  Git: 分支 ${GIT_RUN_BRANCH}"
fi
echo ""

if [ "$fail_count" -gt 0 ]; then
    warn "失败的 Task:"
    for i in "${!TASK_IDS[@]}"; do
        [ "${TASK_STATUSES[$i]}" = "failed" ] && warn "    ${TASK_IDS[$i]} — ${TASK_ISSUES[$i]}"
    done
    echo ""
    warn "重试命令: $0 --retry-failed"
fi

# Feature D: 生成结构化报告
generate_summary

[ "$fail_count" -eq 0 ] && ok "全部完成！" || true
