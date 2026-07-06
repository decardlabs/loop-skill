# PRD → SPEC → Issues → Tasks 自动化管道

## 总览图

```
                                     prd_to_spec.sh
  ┌──── PRD.md ────┐  ──────────────────────────────────────►  ┌──── SPEC.md ────┐
  │ 产品需求文档     │                                            │ 技术规格文档      │
  └────────────────┘                                            └────────┬────────┘
                                                                         │ spec_to_issues.sh
                                                                         ▼
  ┌──────────────────────────────────────────────────────────────────────┐
  │                           ISSUES.md                                 │
  │                 功能单元（每个是一个独立可交付的特性）                  │
  └────────┬──────────────────────────────┬──────────────────────────────┘
           │  issue_to_tasks.sh           │  issue_to_tasks.sh --direct
           ▼                              ▼
  ┌────────────────────┐        ┌────────────────────┐
  │ 多个 Task 文件      │        │ 1 Issue → 1 Task   │
  │ (Claude 拆解)       │        │ (直接包装)          │
  └────────┬───────────┘        └────────┬───────────┘
           │                             │
           └──────────┬──────────────────┘
                      ▼ task_executor.sh
           ┌──────────────────────────────────┐
           │ 循环 · 重试 · 拓扑排序 · 断点续跑  │
           │ Git变更跟踪 · 结构化报告 · AC验证   │
           └──────────────────────────────────┘
```

## 四级分解原则

| 层级 | 产出物 | 粒度 | 谁来写 | 目的 |
|------|--------|------|--------|------|
| **PRD** | `PRD.md` | 整个产品特性 | 产品经理 | 定义需求、背景、验收标准 |
| **SPEC** | `SPEC.md` | 技术架构方案 | Claude Code | 架构决策、模块划分、接口设计 |
| **Issues** | `ISSUES.md` | 独立可交付特性 | Claude Code | 每个 issue 是一个垂直切片 |
| **Tasks** | `tasks/TASK-NNN.md` | 原子操作（<30min） | Claude Code | 每条 task 是一次 Claude Code 调用 |

**核心原则：每一级分解都由上一级驱动。**

- PRD 驱动 SPEC 的结构
- SPEC 驱动 Issues 的划分
- Issues 驱动 Task 的拆解
- Task 驱动 Claude Code 的实际执行

这样即使中间某一步跑偏，回归到上一级的"契约"就能纠偏。

## 文件结构

### 平面模式（默认，未指定 `--target-dir`）

```
prd-pipeline/
├── README.md
├── prd_pipeline.sh            ← 主编排器（一键到底）
├── prd_to_spec.sh             ← PRD → SPEC 拆解
├── spec_to_issues.sh          ← SPEC → Issues 拆解
├── issue_to_tasks.sh          ← Issues → Task 文件生成
├── task_executor.sh           ← Task 循环/重试/断点执行器
├── progress.sh                ← 实时进度查看
├── lib.sh                     ← 共享函数库
│
├── SPEC.md                    ← 产出：技术规格
├── ISSUES.md                  ← 产出：Issue 列表
├── tasks/                     ← 生成的 task 文件
│   ├── task_board.md
│   ├── TASK-001-some-name.md
│   └── ...
└── logs/                      ← 执行日志
    ├── prd_to_spec/
    ├── spec_to_issues/
    ├── issue_to_tasks/
    └── task_exec/
        └── TASK-001/
            ├── run_1.log
            └── run_1.err
```

### 项目模式（指定 `--target-dir <path>`）

```
prd-pipeline/
├── ...（脚本同上）
├── projects/
│   └── <project-name>/
│       ├── 01-spec/SPEC.md
│       ├── 02-issues/ISSUES.md
│       ├── 03-tasks/
│       │   ├── task_board.md
│       │   └── TASK-001-*.md
│       └── 04-execution/
│           ├── logs/               ← per-task 执行日志
│           │   └── TASK-001/
│           │       ├── run_1.log
│           │       ├── run_1.err
│           │       ├── git_diff.json   ← 变更文件快照
│           │       └── ac_verify.json  ← AC 验证结果
│           ├── run-manifest.json  ← PRD→Issues→Tasks 映射
│           ├── summary.json        ← 机器可读（含 commit hash）
│           └── summary.md          ← 人类可读 + Git 合并指引
```

## 核心机制设计

### 1. Task 文件格式（YAML frontmatter + Markdown）

每个 Task 文件是**自包含的指令单元**——Claude Code 能直接执行它。

```yaml
---
id: TASK-001
issue: "用户注册功能"
status: pending
dependencies: []
ac: "验收标准（一句话）"
prompt: |
  请实现以下功能：
  ...
  项目结构在 /path/to/project，遵循现有代码风格。
---
```

### 2. 状态机

```
pending ──► running ──► done
                 │
                 └──► failed ──► pending (retry)
```

### 3. 目标路径注入（Feature B）

项目模式下 (`--target-dir`)，每个 Task 的 prompt 自动注入目标上下文：

```
## 目标项目
项目路径: /path/to/code
项目名称: my-app
技术栈: Node.js Docker

## 项目上下文 (SPEC)
...
```

- **磁盘注入**: `issue_to_tasks.sh` 生成 Task 文件时直接写入目标上下文
- **运行时注入**: `task_executor.sh` 在内存中拼接目标上下文，不修改 Task 文件

### 4. Git 变更跟踪（Feature C）

项目模式下，每执行完一个 Task（无论成功或失败）自动运行 `git diff --stat`，记录变更文件到 `git_diff.json`，含 `headBefore` 和 `headAfter` 提交哈希。

### 5. 结构化报告（Feature D）

执行完成后自动生成两份报告（项目模式）：

**`summary.json`** — 机器可读：
```json
{
  "projectName": "my-app",
  "targetDir": "/path/to/code",
  "tasks": [
    {"id": "TASK-001", "status": "done", "acResult": "passed"},
    {"id": "TASK-002", "status": "failed", "failReason": "curl 504 超时"}
  ]
}
```

**`summary.md`** — 人类可读：
- 概览表格（完成数/失败数/剩余数）
- 失败分析（stderr 末 5 行 + 变更文件摘要）
- 下一步建议（自动生成的 retry 命令）

### 6. AC 验证（Feature E，可选 `--verify-ac`）

成功执行后发一条轻量 prompt 给 Claude，检查验收标准是否满足。结果写入 `ac_verify.json`，不影响 task 状态（始终标记为 done）。

### 7. Git 版本管理（Feature F）

项目模式下，当 `TARGET_DIR` 是 git 仓库时，执行器自动完成版本管理：

**临时分支隔离：** 执行开始时从当前 HEAD 创建独立分支（默认 `auto/task-run-<timestamp>`，或通过 `--git-branch` 指定）。主分支不受影响。

**每个 Task 独立提交：** 每个 task 成功执行后自动执行 `git add -A && git commit -m "TASK-NNN: <标题>"`，commit message 包含 task ID、issue 和 AC 验证结果。

**失败自动清理：** 达最大重试次数后，执行 `git checkout . && git clean -fd` 清理失败产生的变动，确保工作区干净。

**报告中的合并指引：** `summary.md` 自动生成以下建议：

- 全部成功 → `git merge <分支名>` 并删除临时分支
- 部分失败 → 用 `git cherry-pick` 仅提取成功 task 的 commit

**追溯链路：** `summary.json` 的每个 task 记录 `commit` 字段（commit hash 前 8 位）。`run-manifest.json` 记录 PRD→Issues→Tasks 的对应关系，可从代码 commit 追溯到原始需求。

### 8. 依赖解析 + 按层级并行

Task 之间可以声明依赖。执行器按拓扑序排序，同一依赖层级内可并行运行。

```
dependencies: [TASK-001, TASK-003]
```

### 8. 断点续跑

- 每个 task 完成后立即写入 `task_board.md` 更新状态
- 中途中断后 `--resume` 自动跳过 `done` 的 task
- 每个 task 的每轮执行都有独立日志

### 9. 重试机制

- 默认最多重试 3 次（`MAX_RETRIES`）
- 失败后切换 prompt 视角（加一句"前面的尝试失败了，请换一种方式实现"）
- 达到最大重试次数后标记为 `failed`，**不阻塞**后续 task

### 10. 拦截检查点

在关键层级转换点设置**人工审核**是可选项：

```
PRD → SPEC     ◄── 建议审核：架构方案是否合理
SPEC → Issues  ◄── 建议审核：功能拆分是否合理
Issues → Tasks ◄── 可选审核：Task 粒度是否合适
Tasks → 执行   ◄── 自动执行
```

在 `prd_pipeline.sh` 中通过 `MANUAL_APPROVAL=true` 开启。

## 使用方式

### 一键全自动

```bash
# 平面模式（默认）
./prd_pipeline.sh PRD.md

# 项目模式（中间文档隔离 + 自动路径注入 + 结构化报告）
./prd_pipeline.sh PRD.md --target-dir /path/to/code

# 项目模式 + 指定项目名
./prd_pipeline.sh PRD.md --target-dir /path/to/code --project-name my-app

# 细粒度 + 直接模式（跳过 Claude 拆解 Task）
./prd_pipeline.sh PRD.md --granularity fine --direct
```

### 分步执行

```bash
# 第1步：拆解出 SPEC
./prd_to_spec.sh PRD.md

# 第2步：拆解出 Issues
./spec_to_issues.sh SPEC.md

# 第3步：拆解出 Task 文件
./issue_to_tasks.sh SPEC.md ISSUES.md

# 第4步：执行所有 Task
./task_executor.sh

# 可选：启用 AC 验证
./task_executor.sh --verify-ac
```

### 查看进度

```bash
# 平面模式
./progress.sh

# 项目模式（自动检测最新项目）
./progress.sh

# 查看指定项目
./progress.sh --project my-project
```

### 自定义 Git 分支

```bash
# 使用自动分支名 auto/task-run-<ts>（默认）
./task_executor.sh

# 指定分支名
./task_executor.sh --git-branch feat/my-feature

# 全部成功后的合并操作（示例）
cd ~/projects/todo-app
git checkout main && git merge auto/task-run-20260706-153000
```

### 只跑某几个 Task

```bash
./task_executor.sh --tasks TASK-001,TASK-003,TASK-007
```

### 重跑失败的 Task

```bash
./task_executor.sh --retry-failed
```

### 查看异执行报告

```bash
# 项目模式执行后
cat projects/<name>/04-execution/summary.md
```

## 完整示例

下面用一个具体的"智能待办清单"项目，演示从 PRD 到代码执行的完整流程。

### 1. 编写 PRD

```markdown
# PRD: 智能待办清单应用

## 核心需求
1. 任务管理 CRUD（创建、编辑、删除、标记完成）
2. 智能排序（按截止日期 + 优先级自动排序）
3. 分类/标签（自定义标签 + 筛选）

## 技术约束
- Web 应用，响应式设计
- 前后端分离（React + FastAPI）
- 数据实时同步
```

保存为 `prd-pipeline/PRD.md`。

### 2. 一键执行

```bash
cd prd-pipeline
./prd_pipeline.sh PRD.md --target-dir ~/projects/todo-app --granularity fine --direct
```

### 3. 发生了什么

**步骤① — PRD→SPEC:** Claude Code 分析 PRD，生成技术规格文档：

```bash
[INFO]  步骤1/4: PRD → SPEC 技术规格拆解
[INFO]  正在分析 PRD: PRD.md
[INFO]  将输出 SPEC 到: projects/todo-app/01-spec/SPEC.md
[OK]    SPEC → projects/todo-app/01-spec/SPEC.md

──────────── SPEC 预览 ────────────
# 技术规格: 智能待办清单应用

## 1. 架构概览
- 前端: React + TypeScript + Tailwind CSS
- 后端: FastAPI + SQLAlchemy + SQLite
- 实时: WebSocket 连接
...

## 2. 数据模型
### Task 表
- id, title, description, due_date, priority, status, tags
...
────────────────────────────────────
```

**步骤② — SPEC→Issues:** Claude Code 将 SPEC 拆解为功能单元：

```bash
[INFO]  步骤2/4: SPEC → Issues 功能单元拆解
[INFO]  Issue 粒度: fine (2-4 个 Task/Issue)
[OK]    ISSUES.md → projects/todo-app/02-issues/ISSUES.md

──────────── Issue 列表 ────────────
## ISSUE-001: 任务 CRUD 后端 API
## ISSUE-002: 任务列表前端页面
## ISSUE-003: 智能排序与标签筛选
## ISSUE-004: WebSocket 实时同步
────────────────────────────────────
```

**步骤③ — Issues→Tasks（`--direct` 模式）:** 每个 Issue 直接包装为 1 个 Task，prompt 自动注入目标路径：

```bash
[INFO]  步骤3/4: Issues → Task 文件拆解
[OK]    直接打包: projects/todo-app/03-tasks/TASK-001-任务-CRUD-后端-API.md
[OK]    直接打包: projects/todo-app/03-tasks/TASK-002-任务列表前端页面.md
[OK]    直接打包: projects/todo-app/03-tasks/TASK-003-智能排序与标签筛选.md
[OK]    直接打包: projects/todo-app/03-tasks/TASK-004-WebSocket-实时同步.md
```

生成的一个 Task 文件内容：

```yaml
---
id: TASK-001
issue: "ISSUE-001: 任务 CRUD 后端 API"
status: pending
dependencies: []
ac: "任务 CRUD 后端 API 所有验收标准通过"
prompt: |
  ## 目标项目
  项目路径: /Users/me/projects/todo-app
  项目名称: todo-app
  技术栈: Node.js

  ## 项目上下文 (SPEC)
  # 技术规格: 智能待办清单应用
  ...

  ## 执行目标
  ## ISSUE-001: 任务 CRUD 后端 API
  - **模块**: 后端服务
  - **优先级**: P0
  ...
---
```

**步骤④ — 执行所有 Task:**

```bash
[INFO]  步骤4/4: 执行所有 Task
[INFO]  Task 目录: projects/todo-app/03-tasks
[INFO]  最大重试: 3
[INFO]  待执行: 4 个 Task

[INFO]  ▶ TASK-001: ISSUE-001: 任务 CRUD 后端 API
[INFO]     尝试 #1/3...
[OK]    ✓ TASK-001: 成功 (attempt #1)

[INFO]  ▶ TASK-002: ISSUE-002: 任务列表前端页面
[INFO]     尝试 #1/3...
[OK]    ✓ TASK-002: 成功 (attempt #1)

[INFO]  ▶ TASK-003: ISSUE-003: 智能排序与标签筛选
[INFO]     尝试 #1/3...
[WARN]    TASK-003: 失败 (attempt #1, exit=1)
[INFO]     等待 3 秒后重试...
[INFO]     尝试 #2/3...
[OK]    ✓ TASK-003: 成功 (attempt #2)
...
```

### 4. 查看结果

```bash
# 查看进度
./progress.sh --project todo-app

# 输出示例:
═══════════════════════════════════════════
  项目进度报告: todo-app
═══════════════════════════════════════════

  ✓ PRD: PRD.md
  ✓ SPEC: SPEC.md (186 行)
  ✓ ISSUES: 4 个 Issue
  ✓ TASKS: 共 4 个 Task
    ✅ 完成:  4
    进度: [██████████████████████████████] 100%
```

```bash
# 查看执行报告
cat projects/todo-app/04-execution/summary.md

# 输出示例:
# 执行报告: todo-app
#
# **目标项目:** `/Users/me/projects/todo-app`
# **生成时间:** 2026-07-06 15:30:00
#
# ## 概览
# | 状态 | 数量 |
# |------|------|
# | ✅ 完成 | 4 |
# | ❌ 失败 | 0 |
# | ⏳ 剩余 | 0 |
#
# ## 已完成 Task
# | Task | Issue | 文件变更 |
# |------|-------|----------|
# | TASK-001 | ISSUE-001: 任务 CRUD 后端 API | app/models.py, app/routes/tasks.py, ... |
# | TASK-002 | ISSUE-002: 任务列表前端页面 | src/pages/TodoList.tsx, ... |
# | TASK-003 | ISSUE-003: 智能排序与标签筛选 | src/components/SortBar.tsx, ... |
# | TASK-004 | ISSUE-004: WebSocket 实时同步 | app/ws.py, src/hooks/useWebSocket.ts |
```

### 5. 查看代码变更

```bash
cd ~/projects/todo-app
git log --oneline -5
git diff --stat HEAD~4..HEAD
```

---

## 全部参数

| 参数 | 归属 | 说明 |
|------|------|------|
| `--skip-to <step>` | `prd_pipeline.sh` | 从指定步骤开始（跳过之前所有步骤） |
| `--direct` | `prd_pipeline.sh` / `issue_to_tasks.sh` | 每个 Issue 直接包装为 1 个 Task，跳过 Claude 拆解 |
| `--granularity fine/medium/coarse` | `prd_pipeline.sh` / `spec_to_issues.sh` | Issue 拆解粒度控制 |
| `--target-dir <path>` | `prd_pipeline.sh` | 启用项目模式，指定目标代码目录 |
| `--project-name <name>` | `prd_pipeline.sh` | 覆盖自动推导的项目名 |
| `--resume` | `task_executor.sh` | 断点续跑 |
| `--retry-failed` | `task_executor.sh` | 只重试失败的 Task |
| `--tasks <ids>` | `task_executor.sh` | 只跑指定 ID 的 Task |
| `--parallel <N>` | `task_executor.sh` | 并行执行（实验性，见下文） |
| `--verify-ac` | `task_executor.sh` | 执行后验证验收标准 |
| `--git-branch <name>` | `task_executor.sh` | 指定 git 分支名（项目模式），默认 `auto/task-run-<ts>` |
| `--project <name>` | `progress.sh` | 查看指定项目进度 |

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CLAUDE` | `claude` | Claude CLI 路径 |
| `CLAUDE_OPTS` | `--dangerously-skip-permissions` | 传给 `claude` 的额外参数 |
| `MAX_RETRIES` | `3` | 最大重试次数 |
| `PARALLEL` | `1` | 并行数（实验性） |
| `MANUAL_APPROVAL` | `false` | 是否在关键步骤暂停等待人工确认 |
| `ISSUE_GRANULARITY` | `medium` | 默认 Issue 拆解粒度 |

## 最佳实践

### 1. Task 粒度控制

每条 task 的 prompt 应该让 Claude Code **一次调用 3-5 分钟能完成**。太大则容易超时/跑偏，太小则调度开销过大。

**好的粒度：** "实现用户注册的后端 API"  
**太粗：** "实现整个用户系统"  
**太细：** "创建一个空文件"  

### 2. 依赖怎么写

- 基础组件 → 上层功能（基础设施先做）
- 无依赖的 task 可以并行
- 注意环形依赖，task 生成脚本应该检测

### 3. Prompt 工程

Task 的 prompt 应包括：
- **上下文锚点**：项目路径、代码风格、已有约定（项目模式下自动注入）
- **具体指令**：要做什么，不要做什么
- **验收标准**：怎么做才算完成
- **约束条件**：不许引入新依赖、必须写测试等

### 4. 失败处理策略

- **重试**：相同 task 换种方式再试
- **跳过**：标记为 failed，继续后续 task（适用于非关键路径）
- **中止**：关键 task 失败时整个管道停止，等待人工介入

### 5. 大项目拆分

如果 PRD 涉及 30+ 个 task，建议：
1. 先执行核心功能 task（搭建骨架）
2. 再执行边缘功能 task（填充血肉）
3. 分批执行，每批结束后用 `./progress.sh` 验证

通过 `--tasks` 参数可以指定批次。

## Claude CLI 调用注意事项

本管道的执行器通过 `claude -p "prompt"` 管道模式调用 Claude Code。以下是关键注意事项：

### 1. Claude CLI 必须可用

```bash
# 确认 claude 已安装且在 PATH 中
which claude

# 或通过环境变量指定自定义路径
CLAUDE=/path/to/claude ./prd_pipeline.sh PRD.md
```

如果没有安装，请参考 [Claude Code 安装文档](https://docs.anthropic.com/en/docs/claude-code/overview) 安装 CLI。

### 2. 每次调用是独立会话

`--no-session-persistence` 使每次调用从头开始，不继承历史。这意味着：

- **Prompt 必须自包含**。如果 task 依赖前面步骤的输出，prompt 中必须显式描述。项目模式下 `--target-dir` 会自动注入目标路径和技术栈，减少手动编写。
- **没有跨 task 的上下文累积**。每个 task 是独立的 Claude Code 调用，不会因为前面 task 执行过就自动"记住"项目状态。
- **小 task 更浪费**。每个 task 都重新加载模型，过小的 task（如"创建空文件"）会导致频繁冷启动。建议每个 task 的预期执行时间在 3-5 分钟。

### 3. 退出码的正确使用

管道命令的退出码必须取 `${PIPESTATUS[1]}` 而非 `$?`：

```bash
echo "$prompt" | claude -p ... > log 2> err
rc=${PIPESTATUS[1]}    # claude 的退出码
# PIPESTATUS[0] 是 echo 的退出码（永远 0）
```

管道脚本中已正确处理此模式。如果 fork 修改，务必注意。

### 4. `--dangerously-skip-permissions` 是自动化的前提

在自动化流水线中，Claude Code 的权限弹窗会阻塞执行。此选项跳过所有权限确认。**仅在该 pipeline 脚本可控的环境中使用此选项。**

### 5. 输出格式

`--output-format text` 确保 Claude 的响应以纯文本返回，不包含控制字符，便于日志记录和错误分析。

### 6. 成本与限频

- 每次 `claude -p` 调用消耗 token（prompt + 生成的响应）。大 prompt（如包含完整 SPEC 内容的 task）调用 30+ 次可能消耗大量 token。
- Claude CLI 有 API 频率限制（rate limit）。如果大量并行执行，可能触发限制导致部分 task 失败。
- 建议先小规模验证，确认管道正常后再全量执行。

### 7. 重试时 prompt 会自动切换视角

执行器在重试（第 2 次、第 3 次）时，会自动在 prompt 末尾追加"注意：之前的尝试失败了。请换一种实现方式，避免重复同样的错误。"，避免 Claude 重复同样的错误模式。

## 已知限制

- **并行模式**（`--parallel N`，`N>1`）：background subshell 无法将状态数组传回父进程，且并发写 `task_board.md` 存在竞态。生产环境建议串行（`PARALLEL=1`，默认值）。

## 版本记录

### v0.1.0 (2026-07-06)

首个发布版本。核心流程可用。

**功能特性：**
- PRD → SPEC → Issues → Tasks 四级分解流水线
- 平面模式（默认）和项目模式（`--target-dir`）
- 自动目标路径注入（项目模式）
- 拓扑排序 + 依赖层级分批执行
- 断点续跑（`--resume`）和重试（`--retry-failed`）
- 结构化报告（`summary.json` + `summary.md`，含失败分析和下一步建议）
- AC 验证（`--verify-ac`，可选）
- Git 版本管理：自动分支创建、每 task 独立 commit、失败清理、合并指引
- 技术栈自动检测
- run-manifest.json（PRD→Issues→Tasks 追溯映射）
- 全部向后兼容：不加 flag 时行为零变化

**兼容性：** 要求 bash 3.2+、Claude CLI。

---

## 设计哲学

1. **契约驱动**：SPEC 是 Issues 的契约，Issues 是 Tasks 的契约。下级出问题，回看上级纠偏。
2. **状态持久化**：所有状态写入文件，不会因终端关闭丢失。
3. **可观测**：每步都有日志、进度一目了然、执行后有可读报告。
4. **渐进自动化**：可以全自动，也可以每一步插手工审核。
5. **Claude Code 拆解 Claude Code 的工作**：利用 AI 理解 AI 的输出，自动分解。
