#!/bin/bash
# ============================================================
# issue_to_tasks.sh — Issues → Task 文件生成
# ============================================================
# 输入: SPEC.md ISSUES.md
# 输出: tasks/TASK-NNN-<name>.md (每个 task 一个文件)
#       tasks/task_board.md (聚合看板)
# 用法:
#   ./issue_to_tasks.sh SPEC.md ISSUES.md            # 标准模式（Claude 拆解，每 Issue 拆为多个 Task）
#   ./issue_to_tasks.sh SPEC.md ISSUES.md --direct   # 直接模式（每个 Issue 直接包装为 1 Task）
# ============================================================
set -euo pipefail

_ISSDIR="$(cd "$(dirname "$0")" && pwd)"
source "$_ISSDIR/lib.sh"
load_agentrc "$_ISSDIR"

SPEC_FILE=""
ISSUES_FILE=""
DIRECT_MODE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --direct)   DIRECT_MODE=true; shift ;;
        -h|--help)  head -15 "$0"; exit 0 ;;
        -*)         err "未知参数: $1"; exit 1 ;;
        *)
            if   [ -z "$SPEC_FILE"   ]; then SPEC_FILE="$1"
            elif [ -z "$ISSUES_FILE" ]; then ISSUES_FILE="$1"
            else err "多余参数: $1"; exit 1
            fi
            shift ;;
    esac
done

if [ -z "$SPEC_FILE" ] || [ ! -f "$SPEC_FILE" ]; then
    err "用法: $0 <SPEC.md> <ISSUES.md> [--direct]"
    exit 1
fi
if [ -z "$ISSUES_FILE" ] || [ ! -f "$ISSUES_FILE" ]; then
    err "用法: $0 <SPEC.md> <ISSUES.md> [--direct]"
    exit 1
fi

OUTPUT_DIR="$(cd "$(dirname "$0")" && pwd)"
init_project_config
if [ -n "$PROJECT_DIR" ]; then
    TASK_DIR="$TASKS_DIR"
    LOG_DIR="$EXEC_DIR/logs/issue_to_tasks"
else
    TASK_DIR="$OUTPUT_DIR/tasks"
    LOG_DIR="$OUTPUT_DIR/logs/issue_to_tasks"
fi
mkdir -p "$TASK_DIR" "$LOG_DIR"

SPEC_CONTENT="$(cat "$SPEC_FILE")"

# ─── 从 ISSUES.md 提取所有 Issue 标题 ───
# 支持 "## ISSUE-NNN: 标题" 格式
extract_issues() {
    grep -E '^## ISSUE-' "$ISSUES_FILE" | while IFS= read -r line; do
        # 提取 ISSUE-XXX 和标题
        id=$(echo "$line" | sed -n 's/^## \(ISSUE-[0-9]*\).*/\1/p')
        title=$(echo "$line" | sed -n 's/^## ISSUE-[0-9]*: *\(.*\)/\1/p')
        echo "$id|$title"
    done
}

# ─── 提取单个 Issue 的完整内容 ───
get_issue_content() {
    local issue_id="$1"
    awk -v id="$issue_id" '
        /^## ISSUE-/ { found = 0 }
        $0 ~ "^## " id ":" || $0 ~ "^## " id "$" { found = 1; print; next }
        found { print }
    ' "$ISSUES_FILE"
}

# ─── 解析 Issue 的依赖 ───
get_issue_deps() {
    local issue_id="$1"
    get_issue_content "$issue_id" | grep -i '依赖' | grep -oE 'ISSUE-[0-9]+' | tr '\n' ',' | sed 's/,$//'
}

# ─── 提取 Issue 的验收标准（用于 --direct 模式） ───
get_issue_ac() {
    local issue_id="$1"
    get_issue_content "$issue_id" | \
        awk '/### 验收标准/{found=1; next} found && /^###/{exit} found && /- \[ \]/{sub(/.*- \[ \] /,""); printf "%s; ", $0}' | \
        sed 's/; $//'
}

info "从 ISSUES.md 中提取 Issue..."
ISSUES=()
while IFS= read -r line; do
    ISSUES+=("$line")
done < <(extract_issues)

if [ ${#ISSUES[@]} -eq 0 ]; then
    err "没有找到 Issue（格式应为: ## ISSUE-NNN: 标题）"
    exit 1
fi

info "共 ${#ISSUES[@]} 个 Issue，开始逐个拆解为 Task..."

TASK_COUNTER=0
ALL_TASKS=""

# ─── 预扫描：构建 Issue → Task ID 映射（用于依赖解析） ───
ISSUE_ID_LIST=()
TASK_ID_FOR_ISSUE=()
tmp_counter=0
for tmp_entry in "${ISSUES[@]}"; do
    tmp_iid="${tmp_entry%%|*}"
    tmp_counter=$((tmp_counter + 1))
    ISSUE_ID_LIST+=("$tmp_iid")
    TASK_ID_FOR_ISSUE+=($(printf "TASK-%03d" $tmp_counter))
done

# ─── 将 ISSUE 级依赖映射为 TASK 级依赖 ───
map_issue_deps_to_task() {
    local issue_deps_str="$1"
    [ -z "$issue_deps_str" ] && echo "[]" && return
    local task_refs=""
    local IFS_Save="$IFS"
    IFS=','
    for dep_id in $issue_deps_str; do
        dep_id="$(echo "$dep_id" | sed 's/^ *//;s/ *$//')"
        [ -z "$dep_id" ] && continue
        local found=""
        for j in "${!ISSUE_ID_LIST[@]}"; do
            if [ "${ISSUE_ID_LIST[$j]}" = "$dep_id" ]; then
                found="${TASK_ID_FOR_ISSUE[$j]}"
                break
            fi
        done
        if [ -n "$found" ]; then
            [ -n "$task_refs" ] && task_refs="${task_refs},"
            task_refs="${task_refs}${found}"
        fi
    done
    IFS="$IFS_Save"
    if [ -n "$task_refs" ]; then
        echo "[$(echo "$task_refs" | sed 's/,/","/g; s/^/"/; s/$/"/')]"
    else
        echo "[]"
    fi
}

# ─── 目标上下文块（当 TARGET_DIR 设置时，注入 task prompt） ───
build_target_context() {
    [ -z "$TARGET_DIR" ] && return 0
    local stack_info="$(detect_tech_stack)"
    echo "## 目标项目
项目路径: ${TARGET_DIR}
项目名称: ${PROJECT_NAME}
技术栈: ${stack_info}
"
}

for issue_entry in "${ISSUES[@]}"; do
    issue_id="${issue_entry%%|*}"
    issue_title="${issue_entry##*|}"
    issue_content="$(get_issue_content "$issue_id")"
    issue_deps="$(get_issue_deps "$issue_id")"

    echo ""
    info "─────────────────────────────────────────"

    # ═══ --direct 模式：每个 Issue 直接包装为 1 个 Task ═══
    if [ "$DIRECT_MODE" = true ]; then
        info "直接打包: $issue_id — $issue_title"

        TASK_COUNTER=$((TASK_COUNTER + 1))
        task_id=$(printf "TASK-%03d" $TASK_COUNTER)
        slug=$(echo "$issue_title" | sed 's/[^a-zA-Z0-9]/-/g' | sed 's/-\+/-/g;s/^-//;s/-$//' | sed 's/^\(.\{1,40\}\).*/\1/')
        task_file="$TASK_DIR/${task_id}-${slug}.md"

        # 从 Issue 提取验收标准
        task_ac=$(get_issue_ac "$issue_id")
        [ -z "$task_ac" ] && task_ac="${issue_title} 所有验收标准通过"

        # 将 ISSUE 依赖映射为 TASK 依赖
        task_deps="$(map_issue_deps_to_task "$issue_deps")"

        # Prompt = 目标上下文 + SPEC 上下文 + Issue 内容
        target_ctx="$(build_target_context)"
        task_prompt_body="${target_ctx}## 项目上下文 (SPEC)
${SPEC_CONTENT}

## 执行目标
${issue_content}"

        cat > "$task_file" <<TASKFILE
---
id: ${task_id}
issue: "${issue_id}: ${issue_title}"
status: pending
dependencies: ${task_deps}
ac: "${task_ac}"
prompt: |
$(printf '%s\n' "$task_prompt_body" | sed 's/^/  /')
---

# ${task_id}: ${issue_title}

## 所属 Issue
${issue_id}: ${issue_title}

## 验收标准
${task_ac}

## 执行日志
<!-- 执行器会自动追加日志 -->
TASKFILE

        ok "  直接打包: ${task_file}"
        ALL_TASKS="${ALL_TASKS}${task_id}|${issue_title}|${issue_id}|pending
"
        continue
    fi

    # ═══ 标准模式：调用 Claude Code 拆解这个 Issue ═══
    info "拆解: $issue_id — $issue_title"

    # ─── 调用 Claude Code 拆解这个 Issue ───
    target_ctx="$(build_target_context)"
    PROMPT="你是一个资深工程师，负责将一个 Issue 拆解为可执行的原子 Task。

${target_ctx}## 项目上下文 (SPEC)
\`\`\`
${SPEC_CONTENT}
\`\`\`

## 待拆解的 Issue
\`\`\`
${issue_content}
\`\`\`

## 输出要求

将这个 Issue 拆解为 3-10 个原子 Task。**不要直接写入文件**，只需输出每个 Task 的定义，格式如下：

\`\`\`
【TASK】: <简短的动词短语标题>
【PROMPT】: <发给 AI 编程助手的完整执行指令>
【DEPS】: <依赖的 TASK 编号列表，如 TASK-001,TASK-003，或 无>
【AC】: <验收标准，一行>
\`\`\`

### 拆解原则
1. **原子性**：每个 Task 应能在一次 Claude Code 调用中完成（约 3-5 分钟）。
2. **自包含**：每个 Task 的 prompt 应包含所有必要上下文，包括项目路径、代码约定等。
3. **依赖可见**：标注 Task 间的依赖关系。
4. **可验证**：每个 Task 有明确的验收标准。
5. **合理的 prompt 长度**：prompt 要具体到能直接执行，不含糊。

### 示例
\`\`\`
【TASK】: 实现用户注册 API 端点
【PROMPT】: 在项目 ${TARGET_DIR:-/path/to/project} 中，在 app/api/v1/auth.py 中添加 POST /register 端点...（详细指令）
【DEPS】: 无
【AC】: curl 测试注册接口返回 201 + 用户数据写入数据库
\`\`\`"

    task_output_file="${LOG_DIR}/${issue_id}_tasks.log"
    echo "$PROMPT" | \
        claude -p --dangerously-skip-permissions --no-session-persistence \
            --output-format text \
            >"$task_output_file" 2>"${task_output_file%.log}.err"

    # ─── 解析 Claude 输出的 Task 定义 ───
    # 用 awk 按 【TASK】 分割记录
    task_block=""
    task_blocks=()
    while IFS= read -r line; do
        if echo "$line" | grep -q '【TASK】'; then
            [ -n "$task_block" ] && task_blocks+=("$task_block")
            task_block="$line"
        elif echo "$line" | grep -qE '【PROMPT】|【DEPS】|【AC】'; then
            task_block="$task_block"$'\n'"$line"
        else
            task_block="$task_block"$'\n'"$line"
        fi
    done < "$task_output_file"
    [ -n "$task_block" ] && task_blocks+=("$task_block")

    if [ ${#task_blocks[@]} -eq 0 ]; then
        warn "  $issue_id: 拆解失败或未输出 Task 定义"
        continue
    fi

    # ─── 为每个 Task 生成独立文件 ───
    for block in "${task_blocks[@]}"; do
        task_title=$(echo "$block" | grep '【TASK】' | sed 's/.*【TASK】:[[:space:]]*//')
        task_prompt=$(echo "$block" | grep '【PROMPT】' | sed 's/.*【PROMPT】:[[:space:]]*//' | head -1)
        task_deps=$(echo "$block" | grep '【DEPS】' | sed 's/.*【DEPS】:[[:space:]]*//' | head -1)
        task_ac=$(echo "$block" | grep '【AC】' | sed 's/.*【AC】:[[:space:]]*//' | head -1)

        [ -z "$task_title" ] && continue

        TASK_COUNTER=$((TASK_COUNTER + 1))
        task_id=$(printf "TASK-%03d" $TASK_COUNTER)

        # 文件名：用 ID + 标题的简短 slug
        slug=$(echo "$task_title" | sed 's/[^a-zA-Z0-9]/-/g' | sed 's/-\+/-/g;s/^-//;s/-$//' | sed 's/^\(.\{1,40\}\).*/\1/')
        task_file="$TASK_DIR/${task_id}-${slug}.md"

        # 处理依赖：将 ISSUE 级依赖继承过来
        if [ "$task_deps" = "无" ] || [ -z "$task_deps" ]; then
            task_deps="[]"
        else
            # 把 TASK-xxx 转成 YAML 数组
            task_deps="[$(echo "$task_deps" | sed 's/,/","/g; s/^/"/; s/$/"/')]"
        fi

        cat > "$task_file" <<TASKFILE
---
id: ${task_id}
issue: "${issue_id}: ${issue_title}"
status: pending
dependencies: ${task_deps}
ac: "${task_ac}"
prompt: |
  ${task_prompt}
---

# ${task_id}: ${task_title}

## 所属 Issue
${issue_id}: ${issue_title}

## 验收标准
${task_ac}

## 执行日志
<!-- 执行器会自动追加日志 -->
TASKFILE

        ok "  生成: ${task_file}"
        ALL_TASKS="${ALL_TASKS}${task_id}|${task_title}|${issue_id}|pending
"
    done
done

# ─── 生成聚合看板 task_board.md ───
{
    echo "# Task 聚合看板"
    echo ""
    echo "> 自动生成于 $(date '+%Y-%m-%d %H:%M')"
    echo ""
    echo "## 进度"
    echo ""
    echo "| Task ID | 标题 | 所属 Issue | 状态 |"
    echo "|---------|------|------------|------|"
    while IFS='|' read -r tid title iid status; do
        [ -z "$tid" ] && continue
        echo "| [$tid](${tid}-*.md) | $title | $iid | $status |"
    done <<< "$ALL_TASKS"
    echo ""
    echo "## 状态说明"
    echo "- **pending**: 等待执行"
    echo "- **running**: 正在执行"
    echo "- **done**: 已完成"
    echo "- **failed**: 执行失败（可重试）"
} > "$TASK_DIR/task_board.md"

# ─── 生成 run-manifest.json（关联 PRD→Issues→Tasks） ───
manifest_file=""
if [ -n "$EXEC_DIR" ]; then
    manifest_file="$EXEC_DIR/run-manifest.json"
elif [ -n "$OUTPUT_DIR" ]; then
    manifest_file="$TASK_DIR/run-manifest.json"
fi
if [ -n "$manifest_file" ]; then
    {
        echo '{'
        echo '  "generatedAt": "'"$(date '+%Y-%m-%dT%H:%M:%S')"'",'
        echo '  "specFile": "'"$(basename "$SPEC_FILE")"'",'
        echo '  "issuesFile": "'"$(basename "$ISSUES_FILE")"'",'
        echo '  "directMode": '"$DIRECT_MODE"','
        echo '  "taskCount": '"$TASK_COUNTER"','
        echo '  "taskMapping": ['
        local _first=true
        while IFS='|' read -r _tid _title _iid _status; do
            [ -z "$_tid" ] && continue
            $_first || echo ','
            _first=false
            echo -n '    {"task":"'"$_tid"'","issue":"'"$_iid"'","title":"'"$_title"'"}'
        done <<< "$ALL_TASKS"
        echo ''
        echo '  ]'
        echo '}'
    } > "$manifest_file"
    ok "  manifest → $manifest_file"
fi

echo ""
info "═══════════════════════════════════════"
info "拆解完成: 共 $TASK_COUNTER 个 Task"
info "Task 文件: $TASK_DIR/"
info "聚合看板: $TASK_DIR/task_board.md"
[ -n "$manifest_file" ] && info "关联映射: $manifest_file"
info "═══════════════════════════════════════"
