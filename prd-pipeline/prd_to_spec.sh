#!/bin/bash
# ============================================================
# prd_to_spec.sh — PRD → SPEC 技术规格拆解
# ============================================================
# 输入: PRD.md（产品需求文档）
# 输出: SPEC.md（技术规格文档）
# 机制: 调用 Claude Code 分析 PRD，生成结构化技术方案
# ============================================================
set -euo pipefail

# source 共享库前先确定本脚本所在目录
_PRDDIR="$(cd "$(dirname "$0")" && pwd)"
source "$_PRDDIR/lib.sh"

PRD_FILE="${1:-}"
if [ -z "$PRD_FILE" ] || [ ! -f "$PRD_FILE" ]; then
    err "用法: $0 <PRD.md>"
    exit 1
fi

OUTPUT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRD_BASENAME="$(basename "$PRD_FILE" .md)"
init_project_config
if [ -n "$PROJECT_DIR" ]; then
    OUTPUT_FILE="$SPEC_DIR/SPEC.md"
    LOG_DIR="$EXEC_DIR/logs/prd_to_spec"
else
    OUTPUT_FILE="${OUTPUT_DIR}/${PRD_BASENAME}-SPEC.md"
    LOG_DIR="$OUTPUT_DIR/logs/prd_to_spec"
fi
mkdir -p "$LOG_DIR"

# 读取 PRD 内容
PRD_CONTENT="$(cat "$PRD_FILE")"

info "正在分析 PRD: $PRD_FILE"
info "将输出 SPEC 到: $OUTPUT_FILE"

# ─── 调用 Claude Code 做 PRD → SPEC 拆解 ───
# prompt 设计要点:
#   1. 明确输入输出格式
#   2. 给出 SPEC 的骨架模板
#   3. 约束输出范围（不要越界设计）

PROMPT="你是一个资深软件架构师。请分析以下 PRD，生成一份**技术规格文档 (SPEC)**。

## 输入：PRD
\`\`\`
${PRD_CONTENT}
\`\`\`

## 输出要求

输出一份完整的 Markdown 文档到文件 \`${OUTPUT_FILE}\`。

SPEC 必须包含以下结构：

\`\`\`markdown
# 技术规格: <项目名称>

## 1. 架构概览
- 整体架构图（用文本描述）
- 核心模块划分
- 技术栈选择与理由

## 2. 模块设计
- 每个模块的职责、接口、数据流
- 模块间的依赖关系

## 3. 数据模型
- 核心实体定义
- 数据库表设计（如适用）
- API 契约（RESTful / GraphQL 等）

## 4. 关键流程
- 核心业务时序图（文本描述）
- 状态机（如适用）

## 5. 非功能需求
- 性能要求
- 安全考虑
- 可扩展性

## 6. 实现优先级
- 按依赖关系排列的模块实现顺序
- MVP 范围 vs 后续迭代
\`\`\`

## 约束
- 保持合理的技术判断，不要过度设计
- 如果 PRD 信息不足以做决策，做合理假设并标注
- 输出格式必须严格遵循 Markdown
"

echo "$PROMPT" | \
    claude -p --dangerously-skip-permissions --no-session-persistence \
        --output-format text \
        >"${LOG_DIR}/claude_output.log" 2>"${LOG_DIR}/claude_err.log"

# 检查 Claude Code 是否生成了输出文件
if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
    ok "SPEC 已生成: $OUTPUT_FILE"
    echo ""
    echo "──────────── SPEC 预览 ────────────"
    head -30 "$OUTPUT_FILE"
    echo "────────────────────────────────────"
else
    warn "Claude Code 未直接写入 $OUTPUT_FILE"
    warn "尝试从日志提取输出..."

    # 如果 Claude 没有直接写入文件，从日志提取
    cat "${LOG_DIR}/claude_output.log" > "$OUTPUT_FILE"
    if [ -s "$OUTPUT_FILE" ]; then
        ok "从日志提取输出: $OUTPUT_FILE"
    else
        err "拆解失败，查看日志: ${LOG_DIR}/claude_err.log"
        exit 1
    fi
fi
