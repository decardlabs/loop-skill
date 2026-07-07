#!/bin/bash
# ============================================================
# spec_to_issues.sh — SPEC → Issues 功能单元拆解
# ============================================================
# 输入: SPEC.md（技术规格文档）
# 输出: ISSUES.md（结构化 Issue 列表，含依赖关系和验收标准）
# 用法:
#   ./spec_to_issues.sh SPEC.md
#   ./spec_to_issues.sh SPEC.md --granularity fine    # 细粒度(2-4 task/issue，适合直接执行)
#   ./spec_to_issues.sh SPEC.md --granularity medium  # 标准粒度(5-10 task/issue，默认)
#   ./spec_to_issues.sh SPEC.md --granularity coarse  # 粗粒度(10-20 task/issue，复杂项目)
#   ISSUE_GRANULARITY=fine ./spec_to_issues.sh SPEC.md
# ============================================================
set -euo pipefail

_SPECDIR="$(cd "$(dirname "$0")" && pwd)"
source "$_SPECDIR/lib.sh"
load_agentrc "$_SPECDIR"

SPEC_FILE=""
ISSUE_GRANULARITY="${ISSUE_GRANULARITY:-medium}"
AGENT_CMD="${AGENT_CMD:-claude -p --dangerously-skip-permissions --no-session-persistence --output-format text}"

while [ $# -gt 0 ]; do
    case "$1" in
        --granularity) ISSUE_GRANULARITY="$2"; shift 2 ;;
        -h|--help) head -15 "$0"; exit 0 ;;
        -*) err "未知参数: $1"; exit 1 ;;
        *) SPEC_FILE="$1"; shift ;;
    esac
done

if [ -z "$SPEC_FILE" ] || [ ! -f "$SPEC_FILE" ]; then
    err "用法: $0 <SPEC.md> [--granularity fine|medium|coarse]"
    exit 1
fi

OUTPUT_DIR="$(cd "$(dirname "$0")" && pwd)"
init_project_config
if [ -n "$PROJECT_DIR" ]; then
    OUTPUT_FILE="$ISSUES_DIR/ISSUES.md"
    LOG_DIR="$EXEC_DIR/logs/spec_to_issues"
else
    OUTPUT_FILE="$OUTPUT_DIR/ISSUES.md"
    LOG_DIR="$OUTPUT_DIR/logs/spec_to_issues"
fi
mkdir -p "$LOG_DIR"

# ─── SPEC 内容验证 ───
SPEC_CONTENT="$(cat "$SPEC_FILE")"
SPEC_SIZE="${#SPEC_CONTENT}"
if [ "$SPEC_SIZE" -lt 100 ]; then
    err "SPEC 内容过短 (${SPEC_SIZE} 字符)。请检查 SPEC.md 是否完整。"
    exit 1
fi
# 检查必需章节
for _section in "架构概览" "模块设计" "数据模型"; do
    if ! grep -q "$_section" "$SPEC_FILE" 2>/dev/null; then
        err "SPEC 缺少必需章节: ${_section}"
        info "请检查 $SPEC_FILE 是否完整。如不完整，重新运行 prd_to_spec.sh"
        exit 1
    fi
done

info "正在分析 SPEC: $SPEC_FILE"
info "SPEC 大小: ${SPEC_SIZE} 字符"
info "将输出 Issues 到: $OUTPUT_FILE"

# ─── 粒度提示 ───
case "$ISSUE_GRANULARITY" in
    fine)   TASK_COUNT_HINT="2-4 个 Task（细粒度，每个 Issue 可由 Claude Code 一次直接执行，配合 issue_to_tasks.sh --direct 使用）" ;;
    coarse) TASK_COUNT_HINT="10-20 个 Task（粗粒度，适合复杂大型功能）" ;;
    *)      TASK_COUNT_HINT="5-10 个 Task（标准粒度）" ;;
esac
info "Issue 粒度: ${ISSUE_GRANULARITY} (${TASK_COUNT_HINT})"

# ─── 调用 Claude Code 做 SPEC → Issues 拆解 ───
PROMPT="你是一个资深项目经理。请分析以下技术规格文档 (SPEC)，拆解成一份**Issue 列表**。

## 输入：SPEC
\`\`\`
${SPEC_CONTENT}
\`\`\`

## 输出要求

写入文件 \`${OUTPUT_FILE}\`，格式如下：

\`\`\`markdown
# Issue 列表

## ISSUE-001: <标题>
- **模块**: <所属模块>
- **优先级**: P0/P1/P2
- **依赖**: ISSUE-xxx, ISSUE-yyy
- **预估工作量**: <人天>
- **描述**: 一句话描述

### 验收标准
- [ ] 标准1
- [ ] 标准2

### 技术要点
- 关键实现细节
- 需要注意的坑

---

## ISSUE-002: <标题>
...
\`\`\`

## 拆解原则

1. **垂直切片**：每个 Issue 是一个端到端的可交付特性，从前端到后端到数据库，而不是按层拆分。
   - ✅ 好: '用户注册功能'（含前端页面 + 后端 API + 数据库表 + 测试）
   - ❌ 差: '写用户表' / '写注册API'（这是 Task 粒度）

2. **独立性**：Issue 之间尽量减少运行时依赖，便于并行开发。

3. **MVP 优先**：标出 P0（MVP 必需）、P1（重要）、P2（锦上添花）。

4. **Issue 粒度目标**：每个 Issue 应能拆出约 ${TASK_COUNT_HINT}。

5. **跟踪 Issue 间的依赖关系**：依赖必须构成 DAG（有向无环图）。

请严格按以上原则拆解。
"

echo "$PROMPT" | \
    eval "$AGENT_CMD" \
        >"${LOG_DIR}/claude_output.log" 2>"${LOG_DIR}/claude_err.log"

if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
    ISSUE_COUNT=$(grep -c '^## ISSUE-' "$OUTPUT_FILE" || true)
    ok "ISSUES.md 已生成，共 $ISSUE_COUNT 个 Issue"
    echo ""
    echo "──────────── Issue 列表 ────────────"
    grep '^## ISSUE-' "$OUTPUT_FILE" || true
    echo "────────────────────────────────────"
else
    warn "Claude Code 未直接写入 $OUTPUT_FILE，尝试从日志提取..."
    cat "${LOG_DIR}/claude_output.log" > "$OUTPUT_FILE"
    if [ -s "$OUTPUT_FILE" ]; then
        ISSUE_COUNT=$(grep -c '^## ISSUE-' "$OUTPUT_FILE" || true)
        ok "从日志提取，共 $ISSUE_COUNT 个 Issue"
    else
        err "拆解失败，查看日志: ${LOG_DIR}/claude_err.log"
        exit 1
    fi
fi
