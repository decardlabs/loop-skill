# loop — AI 自动化编码管道

> **从 PRD 到代码，全自动分解与执行**

[![Version](VERSION)](VERSION)

**loop** 是一个自动化编码管道系统。它接受一份产品需求文档（PRD），通过 Claude Code 逐层分解为原子任务，然后驱动 Claude Code 逐个实现。整个过程可观测、可重试、可追溯。

```
PRD ──► SPEC ──► Issues ──► Tasks ──► 执行 ──► 完成
```

---

## 目录

- [核心价值](#核心价值)
- [使用方法](#使用方法)
- [分解流程](#分解流程)
- [项目模式](#项目模式)
- [Agent 抽象层](#agent-抽象层)
- [质量门禁](#质量门禁)
- [Git 集成](#git-集成)
- [环境变量](#环境变量)
- [轻量任务循环](#轻量任务循环)
- [项目结构](#项目结构)
- [设计哲学](#设计哲学)
- [已知限制](#已知限制)
- [版本记录](#版本记录)

---

## 核心价值

| 痛点 | loop 的解法 |
|------|------------|
| **AI 写出的代码总不是想要的** | 分层分解：PRD → SPEC → 架构决策 → 任务，每层有质量检查 |
| **关掉终端就丢了上下文** | 所有中间产物持久化为文档文件，随时可回溯 |
| **AI 可能跑偏** | 验收标准（AC）验证 + 状态机跟踪 + 可重试 |
| **无法追溯决策** | PRD 到 commit 的双向追溯链路 |
| **不支持多种 AI 工具** | AGENT_CMD 抽象层，Claude / Codex / Copilot / Gemini 皆可 |

---

## 使用方法

### 前置条件

- **bash 3.2+**（macOS 默认 / Linux）
- 至少一个 **AI agent CLI**（默认使用 Claude Code）
- 一份 **PRD.md** 产品需求文档

### 一键全自动

```bash
# 平面模式（所有产出在当前目录）
./prd-pipeline/prd_pipeline.sh PRD.md

# 项目模式（中间文档隔离 + 自动路径注入 + 结构化报告）
./prd-pipeline/prd_pipeline.sh PRD.md --target-dir /path/to/code

# 细粒度 + 直接模式（跳过 Claude 拆解 Task，适用于小项目）
./prd-pipeline/prd_pipeline.sh PRD.md --granularity fine --direct

# 人工审核模式（每步前暂停确认）
MANUAL_APPROVAL=true ./prd-pipeline/prd_pipeline.sh PRD.md
```

### 分步执行

```bash
# 第 1 步：PRD → SPEC（技术规格）
./prd-pipeline/prd_to_spec.sh PRD.md

# 第 2 步：SPEC → Issues（功能单元）
./prd-pipeline/spec_to_issues.sh SPEC.md --granularity fine

# 第 3 步：Issues → Tasks（原子任务）
./prd-pipeline/issue_to_tasks.sh SPEC.md ISSUES.md --direct

# 第 4 步：执行所有 Task
./prd-pipeline/task_executor.sh

# 可选：启用 AC 验证
./prd-pipeline/task_executor.sh --verify-ac
```

### 查看进度

```bash
# 平面模式
./prd-pipeline/progress.sh

# 项目模式
./prd-pipeline/progress.sh --project my-project

# 查看执行报告
cat projects/my-project/04-execution/summary.md
```

### 执行选项

```bash
# 断点续跑（跳过已完成的）
./prd-pipeline/task_executor.sh --resume

# 仅重试失败的 Task
./prd-pipeline/task_executor.sh --retry-failed

# 只执行指定 Task
./prd-pipeline/task_executor.sh --tasks TASK-001,TASK-003

# 指定 Git 分支
./prd-pipeline/task_executor.sh --git-branch feat/my-feature

# 从指定步骤开始（跳过之前步骤）
./prd-pipeline/prd_pipeline.sh PRD.md --skip-to tasks
```

> 全部参数和选项的详细说明见 [prd-pipeline/README.md](prd-pipeline/README.md)。

---

## 分解流程

```
                                 prd_to_spec.sh
  ┌──── PRD.md ────┐  ──────────────────────────────►  ┌──── SPEC.md ────┐
  │  产品需求文档    │                                    │  技术规格文档     │
  └────────────────┘                                    └───────┬─────────┘
                                                                │ spec_to_issues.sh
                                                                ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                        ISSUES.md                             │
  │              功能单元列表（独立可交付的垂直切片）                │
  └──────┬──────────────────────────────┬───────────────────────┘
         │    issue_to_tasks.sh         │  issue_to_tasks.sh --direct
         ▼                              ▼
  ┌──────────────────┐         ┌──────────────────┐
  │ 多个 Task 文件    │         │ 1 Issue → 1 Task  │
  │ (Claude 拆解)     │         │ (直接包装)         │
  └────────┬─────────┘         └────────┬──────────┘
           │                            │
           └──────────┬─────────────────┘
                      ▼ task_executor.sh
           ┌──────────────────────────────┐
           │ 循环 · 重试 · 拓扑排序       │
           │ 断点续跑 · 变更跟踪 · 报告    │
           └──────────────────────────────┘
```

### 四级分解原则

| 层级 | 产出物 | 粒度 | 目的 |
|------|--------|------|------|
| **PRD** | `PRD.md` | 整个产品特性 | 定义需求、背景、验收标准 |
| **SPEC** | `SPEC.md` | 技术架构方案 | 架构决策、模块划分、接口设计 |
| **Issues** | `ISSUES.md` | 独立可交付特性 | 每个 issue 是一个垂直切片 |
| **Tasks** | `tasks/TASK-NNN.md` | 原子操作（< 30 分钟） | 每条 task 是一次 AI agent 调用 |

**核心原则：每一级分解都由上一级驱动。** 即使中间步骤跑偏，回看上级的"契约"就能纠偏。

### 任务文件格式

每个 Task 是一个 Markdown 文件，带 YAML frontmatter：

```yaml
---
id: TASK-001
issue: "ISSUE-001: 用户注册功能"
status: pending          # pending → running → done | failed
dependencies: [TASK-000] # 依赖声明，按拓扑排序执行
ac: "验收标准（一句话）"
prompt: |
  发给 AI agent 的完整执行指令
---
```

### 状态机

```
pending ──► running ──► done
                 │
                 └──► failed ──► pending (retry, 最多 3 次)
```

---

## 项目模式

通过 `--target-dir <path>` 启用。中间文档组织到 `projects/<project-name>/` 下，Task 的 prompt 自动注入目标项目路径和技术栈上下文。

```
prd-pipeline/projects/<project-name>/
├── 01-spec/SPEC.md
├── 02-issues/ISSUES.md
├── 03-tasks/
│   ├── TASK-NNN-slug.md
│   └── task_board.md
└── 04-execution/
    ├── logs/               ← per-task 执行日志
    │   └── TASK-001/
    │       ├── run_1.log
    │       ├── run_1.err
    │       ├── git_diff.json   ← 变更文件快照
    │       └── ac_verify.json  ← AC 验证结果
    ├── summary.json        ← 机器可读执行报告
    └── summary.md          ← 人类可读报告 + 合并指引
```

---

## Agent 抽象层

loop 不再硬编码 `claude -p`。通过 `AGENT_CMD` 环境变量或 `.agentrc` 配置文件使用任意 AI agent CLI：

```bash
# Claude Code（默认）
AGENT_CMD="claude -p --dangerously-skip-permissions --no-session-persistence --output-format text"

# Codex CLI
AGENT_CMD="codex -p"

# GitHub Copilot CLI
AGENT_CMD="copilot -p --allow-tool"

# Gemini CLI
AGENT_CMD="gemini -p --skip-confirm --no-history"
```

### .agentrc 配置文件

在项目根目录创建 `.agentrc` 持久化配置：

```bash
AGENT_TYPE=claude
AGENT_CMD="claude -p --dangerously-skip-permissions --no-session-persistence --output-format text"
AGENT_CONFIG=CLAUDE.md
```

详见 [.agentrc.example](.agentrc.example)。

---

## 质量门禁

loop 在每个关键转化点设置了质量检查，确保输出质量：

| 门禁 | 位置 | 检查内容 |
|------|------|---------|
| **PRD 质量** | `prd_to_spec.sh` | 章节完整性、优先级标记、范围边界 |
| **SPEC 质量** | `spec_to_issues.sh` | 6 章节完整性、数据模型表格、API 端点 |
| **自动测试** | `task_executor.sh`（项目模式） | 检测 pytest/jest/cargo test 并运行 |
| **AC 验证** | `task_executor.sh --verify-ac` | 执行后验证验收标准是否满足 |
| **Delta 归档** | `task_executor.sh` | OpenSpec 格式变更记录 |

> 质量门禁**不阻塞**管道——结果记录在 `summary.json` 和 `summary.md` 中，供人工审查。

---

## Git 集成

项目模式下，当 `TARGET_DIR` 是 Git 仓库时，执行器自动完成版本管理：

1. **临时分支隔离** — 从当前 HEAD 创建独立分支（`--git-branch` 可自定义）
2. **每 Task 独立提交** — `git add -A && git commit -m "TASK-NNN: <title>"`
3. **失败自动清理** — 达最大重试次数后，`git checkout . && git clean -fd`
4. **合并指引** — 全部成功 → merge；部分失败 → cherry-pick；自动生成在 `summary.md` 中
5. **双向追溯** — `summary.json` 的每个 Task 记录 commit hash，`run-manifest.json` 记录 PRD→Issues→Tasks 映射

---

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `AGENT_CMD` | `claude -p --dangerously-skip-permissions --no-session-persistence --output-format text` | Agent CLI 命令 |
| `MAX_RETRIES` | `3` | 最大重试次数 |
| `PARALLEL` | `1` | 并行任务数（实验性） |
| `MANUAL_APPROVAL` | `false` | 每步前暂停确认 |
| `ISSUE_GRANULARITY` | `medium` | Issue 拆解粒度（fine/medium/coarse） |
| `TARGET_DIR` | — | 目标代码目录 |
| `PROJECT_NAME` | — | 项目名（自动推导的覆盖值） |
| `WORK_DIR` | `$(pwd)` | `claude_loop.sh` 工作目录 |
| `LOG_DIR` | `./.claude_loop_logs` | `claude_loop.sh` 日志目录 |

---

## 轻量任务循环

不需要完整 PRD 管道时，使用 `claude_loop.sh`：

```bash
# 使用内置示例任务
./claude_loop.sh

# 从文件读取任务列表
./claude_loop.sh tasks_example.txt

# 执行单条指令
./claude_loop.sh "Read src/ and analyze code structure"
```

详见 [claude_loop.sh](claude_loop.sh)。

---

## 项目结构

```
├── prd-pipeline/                      # 核心管道
│   ├── prd_pipeline.sh               # 主编排器（一键全自动）
│   ├── prd_to_spec.sh                # PRD → SPEC
│   ├── spec_to_issues.sh             # SPEC → Issues
│   ├── issue_to_tasks.sh             # Issues → Task 文件
│   ├── task_executor.sh              # Task 执行器
│   ├── progress.sh                   # 进度查看
│   ├── lib.sh                        # 共享函数库
│   ├── README.md                     # 管道详细文档
│   ├── PRD_TEMPLATE.md               # PRD 模板
│   ├── SPEC_TEMPLATE.md              # SPEC 模板
│   ├── TASK-TEMPLATE.md              # Task 模板
│   ├── PRD-example.md                # PRD 示例
│   └── tests/                        # 集成测试
│       ├── test_agent_cmd.sh
│       └── test_spec_forge.sh
│
├── claude_loop.sh                    # 轻量任务循环
├── .agentrc.example                  # Agent 配置示例
├── tasks_example.txt                 # 任务列表示例
│
├── CLAUDE.md                         # Claude Code 项目指导
├── USER_MANUAL.md                    # 完整方法论手册
├── DEPLOY.md                         # 部署指南
├── VERSION                           # 版本信息
│
├── AGENTS.md                         # Agent 配置文档
└── RALPH_*.md                        # 技术分析/参考文档
```

---

## 设计哲学

1. **契约驱动** — SPEC 是 Issues 的契约，Issues 是 Tasks 的契约。下级出问题，回看上级纠偏。
2. **状态持久化** — 所有状态写入文件，不会因终端关闭丢失。
3. **可观测** — 每步有日志、进度一目了然、执行后有结构化的可读报告。
4. **渐进自动化** — 可以全自动（一键到底），也可以在每一步插入手工审核。
5. **AI 拆解 AI 的工作** — 利用 AI 理解 AI 的输出，自动分解庞大任务。
6. **Agent 无关** — 通过 `AGENT_CMD` 抽象层支持任意 AI 编码 agent。

---

## 已知限制

- **并行执行**（`PARALLEL > 1`）：背景子 shell 无法将状态数组传回父进程，且并发写 `task_board.md` 存在竞态。生产环境建议使用串行模式（`PARALLEL=1`）。
- **macOS bash 3.2 兼容**：脚本不使用 `mapfile`、`readarray`、关联数组等 bash 4+ 特性。

---

## 版本记录

### v0.2.0 (2026-07-07)

- AGENT_CMD 抽象层（支持 Claude / Codex / Copilot / Gemini）
- .agentrc 配置文件支持
- 质量门禁（自动测试 + Delta 归档）
- Superpowers SKILL.md 集成
- 12 项集成测试

### v0.1.0 (2026-07-06)

- PRD → SPEC → Issues → Tasks 四级分解流水线
- 平面模式和项目模式
- 拓扑排序 + 依赖层级执行
- 断点续跑和重试机制
- 结构化报告
- AC 验证
- Git 版本管理

---

## 从 PRD 到代码 —— 完整示例

```bash
# 1. 编写 PRD
cat > my-prd.md << 'EOF'
# PRD: 智能待办清单应用

## 核心需求
1. 任务管理 CRUD
2. 智能排序（按截止日期 + 优先级）
3. 分类/标签

## 技术约束
- Web 应用，响应式设计
- 前后端分离（React + FastAPI）
EOF

# 2. 一键执行
./prd-pipeline/prd_pipeline.sh my-prd.md --target-dir ~/projects/todo-app

# 3. 查看结果
./prd-pipeline/progress.sh
```

详细示例见 [prd-pipeline/README.md](prd-pipeline/README.md)。

---

> **loop** 是 spec-forge 方法论的核心执行组件。完整的方法论说明见 [USER_MANUAL.md](USER_MANUAL.md)。
