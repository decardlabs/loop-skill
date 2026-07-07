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
load_agentrc "$_PRDDIR"

PRD_FILE="${1:-}"
if [ -z "$PRD_FILE" ] || [ ! -f "$PRD_FILE" ]; then
    err "用法: $0 <PRD.md>"
    exit 1
fi

OUTPUT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRD_BASENAME="$(basename "$PRD_FILE" .md)"
AGENT_CMD="${AGENT_CMD:-claude -p --dangerously-skip-permissions --no-session-persistence --output-format text}"
init_project_config
if [ -n "$PROJECT_DIR" ]; then
    OUTPUT_FILE="$SPEC_DIR/SPEC.md"
    LOG_DIR="$EXEC_DIR/logs/prd_to_spec"
else
    OUTPUT_FILE="${OUTPUT_DIR}/${PRD_BASENAME}-SPEC.md"
    LOG_DIR="$OUTPUT_DIR/logs/prd_to_spec"
fi
mkdir -p "$LOG_DIR"

# ─── 输入验证 ───
PRD_CONTENT="$(cat "$PRD_FILE")"
PRD_SIZE="${#PRD_CONTENT}"
if [ "$PRD_SIZE" -lt 50 ]; then
    err "PRD 内容过短 (${PRD_SIZE} 字符)。请提供更详细的需求描述。"
    exit 1
fi
if [ "$PRD_SIZE" -gt 50000 ]; then
    warn "PRD 内容较长 (${PRD_SIZE} 字符)。AI 可能截断，建议精简到 50000 字符以内。"
fi
info "PRD 大小: ${PRD_SIZE} 字符"
info "正在分析 PRD: $PRD_FILE"
info "将输出 SPEC 到: $OUTPUT_FILE"

# ─── 构建上下文块（技术栈 + 设计约束注入） ───
PRD_CONTEXT=""
# 如果 TARGET_DIR 或其父目录有技术栈规范，附加到 prompt 中
for _ctx_file in "$TARGET_DIR/技术栈规范说明.md" "$(dirname "$TARGET_DIR" 2>/dev/null)/技术栈规范说明.md"; do
    if [ -f "$_ctx_file" ]; then
        PRD_CONTEXT="
## 项目技术约束（来自 ${_ctx_file##*/}）
$(head -40 "$_ctx_file" 2>/dev/null | grep -E '^\|.*\|.*\|' | head -10)

AI 在生成 SPEC 时，技术方案应优先参考上述约束。
"
        break
    fi
done

# 如果 TARGET_DIR 或其父目录有 DESIGN.md，也注入
for _ctx_file in "$TARGET_DIR/DESIGN.md" "$(dirname "$TARGET_DIR" 2>/dev/null)/DESIGN.md"; do
    if [ -f "$_ctx_file" ]; then
        PRIMARY_COLOR="$(grep -i 'primary.*#' "$_ctx_file" 2>/dev/null | head -1 | sed 's/.*#/#/' | sed 's/[" ,].*//')"
        [ -n "$PRIMARY_COLOR" ] && PRD_CONTEXT="${PRD_CONTEXT}
## 设计约束（来自 ${_ctx_file##*/}）
- 主色: ${PRIMARY_COLOR}
- 完整设计 Token 见项目 DESIGN.md 文件
"
        break
    fi
done

# ─── AI 调用（最多重试 2 次，应对输出格式问题） ───
SPEC_GENERATED=false
MAX_SPEC_RETRIES=2
SPEC_ATTEMPT=0

while [ $SPEC_ATTEMPT -lt $MAX_SPEC_RETRIES ] && [ "$SPEC_GENERATED" = false ]; do
    SPEC_ATTEMPT=$((SPEC_ATTEMPT + 1))

    # prompt 设计要点:
    #   1. 明确输入输出格式
    #   2. 给出 SPEC 的骨架模板
    #   3. 约束输出范围（不要越界设计）
    #   4. 注入项目约束（技术栈 + 设计）

    PROMPT="你是一个资深软件架构师。请分析以下 PRD，生成一份**技术规格文档 (SPEC)**。

## 输入：PRD
\`\`\`
${PRD_CONTENT}
\`\`\`
${PRD_CONTEXT}
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
- **文件完整性**：SPEC.md 必须包含上述 6 个章节的全部内容，缺少任何章节都视为不完整
"

    echo "$PROMPT" | \
        eval "$AGENT_CMD" \
            >"${LOG_DIR}/claude_output.log" 2>"${LOG_DIR}/claude_err.log"

    # ─── 输出检查：优先检查 AI 是否直接写入了文件 ───
    if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
        SPEC_GENERATED=true
    else
        # 从日志提取
        warn "尝试 #${SPEC_ATTEMPT}: 未检测到直接写入，从日志提取..."
        cat "${LOG_DIR}/claude_output.log" > "$OUTPUT_FILE"
        if [ -s "$OUTPUT_FILE" ]; then
            SPEC_GENERATED=true
        fi
    fi

    # ─── 内容验证：检查 SPEC 是否包含必需章节 ───
    if [ "$SPEC_GENERATED" = true ]; then
        local _missing=""
        for _section in "架构概览" "模块设计" "数据模型" "关键流程" "非功能需求" "实现优先级"; do
            grep -q "$_section" "$OUTPUT_FILE" 2>/dev/null || _missing="${_missing} ${_section}"
        done
        if [ -n "$_missing" ]; then
            warn "SPEC 缺少以下章节:${_missing}"
            if [ $SPEC_ATTEMPT -lt $MAX_SPEC_RETRIES ]; then
                info "将重试（添加"补充缺少章节"的提示）..."
                SPEC_GENERATED=false
            fi
        fi
    fi

    if [ "$SPEC_GENERATED" = false ] && [ $SPEC_ATTEMPT -lt $MAX_SPEC_RETRIES ]; then
        info "等待 3 秒后重试..."
        sleep 3
    fi
done

# ─── 最终检查 ───
if [ "$SPEC_GENERATED" = true ] && [ -s "$OUTPUT_FILE" ]; then
    ok "SPEC 已生成: $OUTPUT_FILE ($(wc -l < "$OUTPUT_FILE") 行)"
    echo ""
    echo "──────────── SPEC 预览 ────────────"
    head -30 "$OUTPUT_FILE"
    echo "────────────────────────────────────"
else
    err "拆解失败，查看日志: ${LOG_DIR}/claude_err.log"
    exit 1
fi
