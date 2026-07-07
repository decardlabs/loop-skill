# spec-forge Skill 部署指南

> 三种部署方式，从最简到最完整。

---

## 依赖关系总览

### 一句话总结

```text
spec-forge ❌不依赖❌ Superpowers
spec-forge ❌不依赖❌ OpenSpec CLI
spec-forge ✅依赖✅ loop 管线（执行引擎）
spec-forge ✅依赖✅ Agent CLI（实际干活的）
```

**Superpowers 和 OpenSpec 都是可选的增强层，不是必需依赖。**

### 依赖关系图

```
┌──────────────────────────────────────────────────────────────────┐
│                      spec-forge SKILL.md                         │
│            Markdown 指令文件，谁都能读，不依赖任何运行时             │
└───────┬────────────────────────────┬──────────────────────────┬──┘
        │                            │                          │
        │ 可选                        │ 可选                      │ 可选
        ▼                            ▼                          ▼
┌──────────────┐          ┌──────────────────┐       ┌──────────────────┐
│ Superpowers  │          │   OpenSpec CLI    │       │ OpenSpec specs/  │
│ (自动加载)    │          │ (archive/validate)│       │ (结构化输入)      │
│ (review)     │          │                   │       │                  │
│ (finish)     │          │ 需要 Node.js ≥20  │       │ 纯文件，无需 CLI  │
└──────────────┘          └──────────────────┘       └──────────────────┘
        │                          │                          │
        └──────────────────────────┼──────────────────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │    spec-forge 执行引擎        │
                    │  (prd-pipeline/*.sh)         │
                    │  纯 bash，零外部依赖            │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │      Agent CLI (AGENT_CMD)   │
                    │  实际执行代码生成              │
                    │  Claude / Codex / Copilot    │
                    └─────────────────────────────┘
```

### 三种运行模式

| 模式 | loop 管线 | Agent CLI | Superpowers | OpenSpec | 效果 |
|------|----------|-----------|-------------|----------|------|
| **裸奔模式** | ✅ 必须 | ✅ 必须 | ❌ | ❌ | 手动加载 skill，自由 PRD 输入 |
| **标准模式** | ✅ 必须 | ✅ 必须 | ✅ 推荐 | ❌ | skill 自动加载，review+finish 流程可用 |
| **完整模式** | ✅ 必须 | ✅ 必须 | ✅ 推荐 | ✅ 可选 | 结构化 specs + 自动 archive |

### 详细依赖表

| 组件 | spec-forge 是否依赖 | 依赖性质 | 如果缺失的后果 |
|------|-------------------|---------|--------------|
| **loop 管线** (`prd-pipeline/`) | ✅ **必须** | 执行引擎 | ❌ 无法执行。skill 只剩空指令 |
| **Agent CLI** (`claude`/`codex`/`copilot`) | ✅ **必须** | 实际执行者 | ❌ 无法调 Agent。任务卡住 |
| **bash 3.2+** | ✅ **必须** | 运行时 | ❌ 脚本无法运行 |
| **git** | ✅ **必须** | 分支管理和 commit | ❌ 自动 commit、分支隔离不可用 |
| **Superpowers** | ❌ **不必须** | 可选增强 | skill 需要手动加载，review/finish 流程不可用（退化） |
| **Superpowers hooks** | ❌ **不必须** | 可选增强 | skill 不会自动注入，需手动 `/skill` |
| **OpenSpec CLI** (`openspec`) | ❌ **不必须** | 可选增强 | delta archive 不可用，退化为只写 status.md |
| **OpenSpec specs/** 目录 | ❌ **不必须** | 可选增强 | 退化为使用自由格式 PRD.md（多花 2 次 Claude 调用） |
| **Node.js** | ❌ **不必须** | 仅 OpenSpec 需要 | OpenSpec CLI 不可用，不影响其他功能 |

### 常见误解

```
❌ "spec-forge 是 Superpowers 的一个 skill，所以必须安装 Superpowers"
→ 不对。SKILL.md 是独立文件，任何 Agent 都可以读它的内容并执行。
  Superpowers 只是让加载更方便（自动注入）。

❌ "spec-forge 依赖 OpenSpec，没安装就不能用"
→ 不对。OpenSpec specs 是可选的输入格式。没有它就用 PRD.md。
  测试、质量门禁、Git 管理都不需要 OpenSpec。

❌ "没有 Claude Code 就不能用"
→ 不对。AGENT_CMD 支持 Codex、Copilot、Gemini 等。
  执行引擎不绑定特定 Agent。

❌ "spec-forge 需要 Superpowers 的 session-start hook"
→ 不对。hook 只是自动加载机制。手动 /forge 或直接读 SKILL.md 也一样。
```

---

## 方式一：手动加载（最简，无需安装）

---

## 方式一：手动加载（最简，无需安装）

**适用场景：** 快速试用，不安装 Superpowers。

**原理：** 在 Claude Code 会话中直接告诉它 spec-forge skill 的位置。

### 步骤

```bash
# 1. 在目标代码项目中，确认 loop pipeline 存在
ls prd-pipeline/task_executor.sh

# 2. 在目标代码项目中，确认 spec-forge SKILL.md 存在
ls superpowers/skills/spec-forge/SKILL.md

# 3. 启动 Claude Code 并手动加载 skill
cd your-project
claude

# 在 Claude Code 中输⼊：
# /skill superpowers:spec-forge
#
# 或直接告诉 Claude:
# "请使用 spec-forge 技能。SKILL.md 在 superpowers/skills/spec-forge/SKILL.md"
```

**优点：** 零安装。
**缺点：** 每次新会话都要手动加载。

---

## 方式二：作为 Superpowers 插件部署（推荐）

**适用场景：** 长期使用，技能自动加载。

### 前提

已安装 [Superpowers](https://github.com/prime-radiant/superpowers)。

```bash
# 检查 Superpowers 是否已安装
ls .claude/plugins/superpowers/ 2>/dev/null && echo "已安装" || echo "未安装"
```

### 步骤

```bash
# 1. 将 spec-forge skill 复制到 Superpowers skills 目录
cp -r superpowers/skills/spec-forge .claude/plugins/superpowers/skills/spec-forge

# 2. 确认结构
ls .claude/plugins/superpowers/skills/spec-forge/SKILL.md

# 3. 配置 Agent
cp .agentrc.example .agentrc
# 编辑 .agentrc 匹配你用的 Agent
```

### 验证

启动 Claude Code，输入 `/forge "查看我的项目结构"`。如果技能自动加载，终端会显示：

```
  ╔═══════════════════════════════════╗
  ║    spec-forge v0.2               ║
  ║    从规约到代码的自动化锻造炉       ║
  ╚═══════════════════════════════════╝

  [1/5] SPEC 阶段...
```

### 自动加载

Superpowers 的 `session-start` hook 会自动注入可用技能列表。如果 spec-forge skill 在 skills 目录下，Claude Code 会在需要时自动匹配 `/forge` 或其他触发词。

**不自动加载怎么办？**

```bash
# 检查 hook 是否工作
.claude/hooks/session-start 2>&1 | grep spec-forge || echo "未检测到 spec-forge"

# 手动注册（临时）
# 在 Claude Code 中: /skill superpowers:spec-forge
```

---

## 方式三：独立项目部署（最完整）

**适用场景：** 把 spec-forge 作为一个独立项目安装到任意目标代码项目。

### 自动化安装脚本

将以下内容保存为 `install-spec-forge.sh`：

```bash
#!/bin/bash
set -euo pipefail

# spec-forge 部署脚本
REPO_URL="https://github.com/decardlabs/loop-skill.git"
TARGET="${1:-$(pwd)}"

cd "$TARGET"

echo "==> 安装 spec-forge 到 $TARGET"

# 1. 确认目标目录是 git 仓库
if [ ! -d ".git" ]; then
    echo "初始化 git 仓库..."
    git init
fi

# 2. 下载 loop pipeline（如果没有）
if [ ! -f "prd-pipeline/task_executor.sh" ]; then
    echo "下载 loop pipeline..."
    git clone --depth 1 "$REPO_URL" /tmp/loop-skill-tmp
    cp -r /tmp/loop-skill-tmp/prd-pipeline .
    cp /tmp/loop-skill-tmp/.agentrc.example .
    rm -rf /tmp/loop-skill-tmp
fi

# 3. 配置 Agent
if [ ! -f ".agentrc" ]; then
    echo "创建 .agentrc..."
    cp .agentrc.example .agentrc
    echo "请编辑 .agentrc 匹配你用的 Agent"
fi

# 4. 验证安装
echo ""
echo "==> 验证安装..."
ls prd-pipeline/task_executor.sh 2>/dev/null && echo "  ✅ loop pipeline"
ls .agentrc 2>/dev/null && echo "  ✅ .agentrc"
echo ""
echo "==> 安装完成"
echo "启动 Claude Code 后输入 /forge <需求描述>"
```

### 安装依赖检查

```bash
# 目标代码项目需要的环境
claude --version 2>/dev/null || echo "❌ Claude CLI 未安装"
git --version 2>/dev/null || echo "❌ git 未安装"
bash --version | head -1

# 推荐安装（可选）
openspec --version 2>/dev/null || echo "⚠️ OpenSpec CLI 未安装（可选）"
```

---

## 四种场景的配置对照

| 场景 | loop pipeline | spec-forge SKILL.md | .agentrc | OpenSpec |
|------|-------------|-------------------|----------|----------|
| 仅 loop 管线 | ✅ 必须 | ❌ 不必须 | ❌ 不必须 | ❌ 不必须 |
| loop + 手动 skill | ✅ 必须 | ✅ 必须（手动加载） | ❌ 不必须 | ❌ 不必须 |
| loop + Superpowers | ✅ 必须 | ✅ 自动加载 | ❌ 不必须 | ❌ 不必须 |
| 完整融合 | ✅ 必须 | ✅ 自动加载 | ✅ 推荐 | ✅ 推荐 |

---

## 常见问题

### Q: 技能没有自动触发？

检查：
1. SKILL.md 是否在正确的路径：`.claude/plugins/superpowers/skills/spec-forge/SKILL.md`
2. Superpowers 的 session-start hook 是否工作：`.claude/hooks/session-start`
3. 手动测试：在 Claude Code 中输入 `/forge`

### Q: 提示 AGENT_CMD not set？

运行前 export：
```bash
export AGENT_CMD="claude -p --dangerously-skip-permissions --no-session-persistence --output-format text"
```
或者创建 `.agentrc` 文件。

### Q: 想在其他 Agent 上用（Codex/Copilot）？

```bash
# 修改 .agentrc
AGENT_CMD="codex -p"

# 或环境变量
AGENT_CMD="codex -p" ./prd-pipeline/task_executor.sh
```

注意：Cursor 不支持无确认模式，不适合自动化 pipeline。
