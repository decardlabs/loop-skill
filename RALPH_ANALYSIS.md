# Ralph 实现深度分析

> 来自 https://github.com/snarktank/ralph — 一个具体的 Ralph 实现。
> 基于 Geoffrey Huntley 的 Ralph 模式，支持 Amp + Claude Code 双工具。

---

## 一、总体架构

```
ralph/
├── ralph.sh              ← 核心循环脚本（~110 行 bash）
├── prd.json              ← 任务列表（JSON 格式，含 passes 状态）
├── prd.json.example      ← 示例格式
├── progress.txt           ← 追加式学习日志
├── CLAUDE.md              ← Claude Code 的 prompt 模板
├── prompt.md              ← Amp 的 prompt 模板
├── skills/prd/            ← PRD 生成技能
│   └── SKILL.md
├── skills/ralph/          ← PRD→JSON 转换技能
│   └── SKILL.md
├── .claude-plugin/        ← Claude Code 插件市场
└── flowchart/             ← 交互式流程图
```

---

## 二、核心循环（ralph.sh）

```bash
for i in $(seq 1 $MAX_ITERATIONS); do
    # 1. 用管道模式调 AI
    OUTPUT=$(cat prompt.md | amp --dangerously-allow-all 2>&1 | tee /dev/stderr)
    # 或
    OUTPUT=$(claude --dangerously-skip-permissions --print < CLAUDE.md 2>&1 | tee /dev/stderr)

    # 2. 检查完成信号
    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
        exit 0
    fi

    # 3. 继续循环
    sleep 2
done
```

### 和 loop 的对比

| 维度 | Ralph | loop | 分析 |
|------|-------|------|------|
| 循环逻辑 | for 循环，固定次数 | while + 重试 | loop 更健壮 |
| 任务列表 | `prd.json`（JSON） | `TASK-NNN.md`（YAML frontmatter） | 格式不同，目标相同 |
| 完成信号 | `<promise>COMPLETE</promise>` 魔法字符串 | 全部 task status=done | Ralph 方式更脆弱 |
| 输出视图 | `tee /dev/stderr` 实时显示 | 写入文件，事后查看 | Ralph 方式更好 |
| AI 工具 | Amp + Claude（`--tool` 参数） | AGENT_CMD 环境变量 | loop 更灵活 |
| 重试 | 无 | 最多 3 次 + 换方式 | loop 更可靠 |
| 质量检查 | 在 prompt 中要求 AI 做 | 脚本内置 typecheck/lint/test | loop 更强制 |
| 学习记录 | `progress.txt` 追加式 | ❌ 无 | **Ralph 领先** |
| AGENTS.md 更新 | 每次迭代后更新 | ❌ 无 | **Ralph 领先** |

---

## 三、Ralph 值得借鉴的设计

### 3.1 progress.txt — 结构化的学习日志

Ralph 的 `progress.txt` 不是普通的日志文件，而是**跨迭代的知识传递介质**：

```
## 2026-07-08 10:30 — US-001
- Added priority column to tasks table
- Files: db/migrations/xxx_add_priority.sql, src/models/task.rs

## Codebase Patterns（顶部区域，持续累积）
- Use `sql` template for aggregations
- Always use `IF NOT EXISTS` for migrations
- Export types from actions.ts for UI components
```

**AI 每次启动时先读 `progress.txt` 的 `## Codebase Patterns` 区域。** 这意味着：
- AI 不会重复犯同样的错误
- AI 了解代码库的隐含约定
- 跨迭代的知识不会丢失

**对我们的启示：** loop 可以在 `04-execution/logs/` 下增加 `learnings.md`，每次任务完成后追加经验。

### 3.2 迭代间知识传递（AGENTS.md 更新）

Ralph 的 CLAUDE.md（prompt）明确要求 AI 在每次迭代后更新 AGENTS.md：

```markdown
## Update CLAUDE.md Files
Before committing, check if any edited files have learnings
worth preserving in nearby CLAUDE.md files:
- API patterns or conventions specific to that module
- Gotchas or non-obvious requirements
- Dependencies between files
```

**这是 Ralph 最聪明的设计。** 不是把所有知识放在一个文件里，而是**就近存放**——修改了 `src/api/tasks.rs`，就在该目录下的 `CLAUDE.md` 中记录该模块的约定。

**对我们的启示：** loop 的 SKILL.md 可以要求 AI 在每次 commit 前更新被修改模块的 `CLAUDE.md`。

### 3.3 JSON 格式的任务列表

与 loop 的 YAML frontmatter 相比：

```json
// ralph prd.json — JSON 数组，结构化
{
  "userStories": [
    {
      "id": "US-001",
      "title": "Add priority field to database",
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

```yaml
# loop TASK-NNN.md — YAML frontmatter + Markdown prompt
---
id: TASK-001
title: "Add priority field"
status: pending
dependencies: []
prompt: |
  完整执行指令...
---
```

| 对比 | Ralph (JSON) | loop (YAML + MD) |
|------|-------------|------------------|
| 可读性 | 机器友好 | 人机都友好 |
| prompt 存储 | 外部 CLAUDE.md | 内嵌在 task 文件中 |
| 状态跟踪 | passes: bool | status: pending/running/done/failed |
| 依赖管理 | ❌ 无（优先级排序） | ✅ 拓扑排序 |
| 解析难度 | jq 即可 | 需自写 awk 解析器 |

**loop 的 YAML frontmatter 更灵活**（嵌入完整 prompt、依赖列表），但 Ralph 的 JSON 格式在脚本中处理更简单（`jq` 一行搞定）。

### 3.4 `tee /dev/stderr` 技巧

```bash
OUTPUT=$(cat prompt.md | amp ... 2>&1 | tee /dev/stderr)
```

这行命令同时做到：
- `OUTPUT=$(...)` — 捕获 AI 输出到变量
- `tee /dev/stderr` — 同时实时显示在终端
- `2>&1` — 合并 stderr 到 stdout，确保全部捕获

**loop 的做法是写入文件后 `cat` 查看，Ralph 的做法让用户实时看到 AI 在做什么。**

---

## 四、Ralph 的不足

| 不足 | 说明 | loop 的做法 |
|------|------|------------|
| 无重试 | 失败就直接下次迭代 | 最多 3 次 + 换方式 |
| 无拓扑排序 | 按 priority 字段排序（无依赖解析） | DAG 拓扑排序 |
| 无质量门禁 | 质量检查交给 AI 自觉执行 | shell 脚本强制执行 |
| 无断点续跑 | 重新开始时不知道上次进度 | task_board.md + --resume |
| 无报告 | 只有 progress.txt | summary.json + summary.md |
| completion 信号脆弱 | 依赖 AI 输出精确的魔法字符串 | 基于文件状态的确定性检查 |
| 单目录 | 所有文件在 ralph/ 下 | projects/ 目录隔离 |
| set -e 危险 | 没有 set -euo pipefail | 更严格的错误处理 |

---

## 五、可以借鉴的具体改动

### 1. 实时输出显示

```bash
# loop 当前：写入文件
echo "$actual_prompt" | eval "$AGENT_CMD" > "$log_file" 2>"$err_file"

# 借鉴 Ralph：实时显示 + 同时写入
echo "$actual_prompt" | eval "$AGENT_CMD" 2>&1 | tee -a "$log_file"
```

### 2. 学习日志（learnings.md）

在 `04-execution/` 下增加 `learnings.md`，每次任务完成后：

```markdown
## 2026-07-08 — TASK-003: 注册页面
实现要点：
- 使用 TanStack Query 管理 API 状态
- 表单校验用 react-hook-form + zod
- 主色 #2563EB（来自 DESIGN.md）
```

### 3. 就近 CLAUDE.md 更新

SKILL.md 中要求 AI 在每次 commit 前检查被修改的目录是否有 `CLAUDE.md`，如有则更新学习到的约定。

---

## 六、总结

```
Ralph 最值得学的东西：
1. progress.txt — 非结构化但有效的跨迭代知识传递
2. AGENTS.md 更新 — 就近记录模块级约定
3. tee /dev/stderr — 实时显示 AI 输出
4. 简洁性 — 110 行 bash 实现了核心循环

loop 已经做得更好的东西：
1. 重试机制（3 次 + 换方式）
2. 拓扑排序（DAG 依赖解析）
3. 质量门禁（typecheck/lint/test 强制执行）
4. 结构化报告（summary.json + summary.md）
5. 断点续跑（task_board.md + --resume）
6. 向后兼容（不加参数行为不变）
```
