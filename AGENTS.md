# loop — AI Agent 指南 · v0.1.0

这个项目是一套**自动化流水线**：把产品需求文档（PRD）通过 Claude Code 逐级拆解成可执行的原子 Task，并循环驱动 Claude Code 完成实际编码。

## 项目结构

```
prd-pipeline/
  prd_pipeline.sh        # 主编排器（一键全流程）
  prd_to_spec.sh         # PRD → SPEC（技术规格）
  spec_to_issues.sh      # SPEC → ISSUES（功能单元列表）
  issue_to_tasks.sh      # ISSUES → tasks/TASK-NNN-*.md（原子任务文件）
  task_executor.sh       # 执行器（循环/重试/断点续跑/并行/AC验证/报告）
  progress.sh            # 进度查看（支持平面和项目模式）
  lib.sh                 # 共享函数库（色彩输出 + 项目配置 + 技术栈检测）
  tasks/                 # 生成的 task 文件（YAML frontmatter + Markdown）
  logs/                  # 每轮执行日志
  projects/              # 项目模式下各项目的中间文档 + 报告
    <name>/
      01-spec/
      02-issues/
      03-tasks/
      04-execution/      # logs + summary.json + summary.md
  PRD-example.md         # PRD 示例
  TASK-TEMPLATE.md       # Task 文件格式说明

claude_loop.sh           # 轻量版：直接驱动多步骤任务循环
```

## 运行方式

### 平面模式（默认）

```bash
# 一键全流程
./prd-pipeline/prd_pipeline.sh PRD.md

# 细粒度 + 直接模式（Issue 足够小时，跳过 Claude 拆解调用）
./prd-pipeline/prd_pipeline.sh PRD.md --granularity fine --direct
```

### 项目模式（新增 `--target-dir`）

```bash
# 中间文档归入 projects/<name>/，prompt 自动注入目标路径
./prd-pipeline/prd_pipeline.sh PRD.md --target-dir /path/to/code

# 启用 AC 验证
./prd-pipeline/prd_pipeline.sh PRD.md --target-dir /path/to/code
./prd-pipeline/task_executor.sh --verify-ac
```

### 分步执行

```bash
./prd-pipeline/prd_to_spec.sh PRD.md
./prd-pipeline/spec_to_issues.sh SPEC.md                          # 标准粒度 (5-10 task/issue)
./prd-pipeline/spec_to_issues.sh SPEC.md --granularity fine       # 细粒度 (2-4 task/issue)
./prd-pipeline/issue_to_tasks.sh SPEC.md ISSUES.md                # 标准模式（Claude 拆解）
./prd-pipeline/issue_to_tasks.sh SPEC.md ISSUES.md --direct       # 直接模式（每 Issue→1 Task）
./prd-pipeline/task_executor.sh
./prd-pipeline/task_executor.sh --verify-ac                       # 带 AC 验证执行
```

### 查看进度 + 报告

```bash
# 平面进度
./prd-pipeline/progress.sh

# 项目进度（自动检测最新项目）
./prd-pipeline/progress.sh

# 指定项目
./prd-pipeline/progress.sh --project my-app

# 查看执行报告（项目模式）
cat prd-pipeline/projects/<name>/04-execution/summary.md
```

### 只跑指定 task / 重试失败

```bash
./prd-pipeline/task_executor.sh --tasks TASK-001,TASK-003
./prd-pipeline/task_executor.sh --retry-failed
```

### 轻量循环（无需 PRD 流水线）

```bash
./claude_loop.sh task_list.txt
./claude_loop.sh "单条 prompt"
```

## Task 文件格式

每个 Task 是一个带 YAML frontmatter 的 Markdown 文件，格式见 [prd-pipeline/TASK-TEMPLATE.md](prd-pipeline/TASK-TEMPLATE.md)。

状态机：`pending → running → done / failed`（`failed` 可重试，最多 `MAX_RETRIES` 次）。

## 新增功能（v2）

### 项目模式

加 `--target-dir <path>` 后：
- 中间文档写入 `projects/<project-name>/` 分层目录（`01-spec/` → `02-issues/` → `03-tasks/` → `04-execution/`）
- Task prompt 自动注入目标路径和技术栈信息
- 执行后生成结构化 JSON + Markdown 报告
- 每 task 记录 git diff 变更文件

### AC 验证

`task_executor.sh --verify-ac` 在成功执行后发送验证 prompt 检查验收标准。结果写入 `ac_verify.json`，不影响 task 状态。

### 进度查看

`progress.sh` 支持 `--project <name>` 参数，自动检测 `projects/` 目录。

## 关键约定

- **所有脚本兼容 bash 3.2**（macOS 系统默认版本）。禁用 `mapfile`，使用 `while IFS= read -r` 代替。`local` 仅限在函数内使用。
- **文件路径操作**必须用 null-safe 方式（`find -print0` + `read -r -d ''`），防止空格裂开。
- **调用 Claude 的管道命令**取退出码必须用 `${PIPESTATUS[1]}`，因为 `echo "$prompt" | claude ...` 中 `PIPESTATUS[0]` 是 `echo` 的退出码（永远 0）。
- **`--skip-to` 语义**：`--skip-to <step>` 表示从该步骤开始执行，之前的步骤全部跳过。例如 `--skip-to issues` 跳过 spec 生成，直接从 issues 拆解开始。
- **`--direct` 语义**：跳过 Claude 对 Issue→Task 的拆解调用，每个 Issue 直接包装成 1 个 Task 文件。适合 Issue 粒度已足够细（`--granularity fine`）的场景，节省 API 调用。
- **`--granularity` 语义**：控制 `spec_to_issues.sh` 生成 Issue 的粒度。`fine`=2-4 task/issue，`medium`=5-10（默认），`coarse`=10-20。
- **`--target-dir` 语义**：启用项目模式。中间文档写入 `projects/<name>/` 分层目录。Task prompt 自动注入目标路径。`<name>` 默认从目标目录 basename 推导，可被 `--project-name` 覆盖。
- **`--verify-ac` 语义**：启用 AC 验证。成功执行后发验证 prompt 给 Claude，结果不改变 task 状态（task 仍标记为 done）。
- **并行模式**（`--parallel N`）在共享全局数组和 `task_board.md` 时存在竞争条件，生产环境建议串行（默认）。
- SPEC/ISSUES 生成脚本通过 prompt 要求 Claude Code 主动写入文件；若文件未生成，脚本会报错退出。

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CLAUDE` | `claude` | Claude CLI 路径 |
| `CLAUDE_OPTS` | `--dangerously-skip-permissions` | 传给 `claude` 的额外参数 |
| `WORK_DIR` | `$(pwd)` | claude_loop.sh 的工作目录 |
| `MAX_RETRIES` | `3` | task_executor.sh 最大重试次数 |
| `PARALLEL` | `1` | task_executor.sh 并行数 |
| `MANUAL_APPROVAL` | `false` | prd_pipeline.sh 是否在关键步骤暂停等待人工确认 |

## 产出物清单（项目模式）

| 产出物 | 路径 | 说明 |
|--------|------|------|
| SPEC | `projects/<name>/01-spec/SPEC.md` | 技术规格 |
| Issues | `projects/<name>/02-issues/ISSUES.md` | 功能单元列表 |
| Task 文件 | `projects/<name>/03-tasks/TASK-*.md` | 原子任务 |
| 看板 | `projects/<name>/03-tasks/task_board.md` | 全量状态聚合 |
| 执行日志 | `projects/<name>/04-execution/logs/` | per-task 多轮日志 |
| Git 变更快照 | `.../logs/<TASK-ID>/git_diff.json` | 每 task 前后 diff |
| AC 验证结果 | `.../logs/<TASK-ID>/ac_verify.json` | AC 验证结果 |
| 结构化报告 | `projects/<name>/04-execution/summary.json` | 机器可读 |
| 可读报告 | `projects/<name>/04-execution/summary.md` | 人类可读 + 下一步建议 |
