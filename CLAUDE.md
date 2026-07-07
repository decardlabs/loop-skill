# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**loop** is an automated coding pipeline system. It takes a Product Requirements Document (PRD) and iteratively decomposes it through Claude Code into executable atomic tasks, then drives Claude Code to implement them.

The decomposition chain is: `PRD → SPEC → Issues → Tasks → Execution`

## Architecture

```
                               prd_to_spec.sh
  ┌──── PRD.md ────┐  ──────────────────────────►  ┌──── SPEC.md ────┐
  │ 产品需求文档     │                                │ 技术规格文档      │
  └────────────────┘                                └────────┬────────┘
                                                             │ spec_to_issues.sh
                                                             ▼
  ┌──────────────────────────────────────────────────────────┐
  │                    ISSUES.md                             │
  │          功能单元列表（独立可交付的垂直切片）                │
  └────────┬──────────────────────────────┬──────────────────┘
           │  issue_to_tasks.sh           │  issue_to_tasks.sh --direct
           ▼                              ▼
  ┌──────────────────┐          ┌──────────────────┐
  │ 多个 Task 文件    │          │ 1 Issue → 1 Task  │
  │ (Claude 拆解)     │          │ (直接包装)        │
  └────────┬─────────┘          └────────┬─────────┘
           │                             │
           └──────────┬──────────────────┘
                      ▼ task_executor.sh
           ┌──────────────────────┐
           │ 循环、重试、拓扑排序   │
           │ 断点续跑、并行执行     │
           └──────────────────────┘
```

### Key Files

| File | Role |
|------|------|
| `prd-pipeline/prd_pipeline.sh` | Main orchestrator — one command runs the full chain |
| `prd-pipeline/prd_to_spec.sh` | PRD → technical specification |
| `prd-pipeline/spec_to_issues.sh` | SPEC → feature unit list |
| `prd-pipeline/issue_to_tasks.sh` | Issues → atomic task files |
| `prd-pipeline/task_executor.sh` | Task executor (loop + retry + resume) |
| `prd-pipeline/progress.sh` | Real-time progress display |
| `prd-pipeline/lib.sh` | Shared color/output functions |
| `claude_loop.sh` | Lightweight task loop (no PRD pipeline needed) |

### Task File Format

Each task is a Markdown file with YAML frontmatter under `prd-pipeline/tasks/TASK-NNN-slug.md`:

```yaml
---
id: TASK-001
issue: "ISSUE-001: 用户注册功能"
status: pending          # pending → running → done | failed
dependencies: [TASK-001]
ac: "验收标准（一句话）"
prompt: |
  发给 Claude Code 的完整执行指令
---
```

## Usage

### Full Pipeline (PRD → Code)

```bash
# One-click full pipeline
./prd-pipeline/prd_pipeline.sh PRD.md

# Project mode: intermediate docs organized, prompts include target path
./prd-pipeline/prd_pipeline.sh PRD.md --target-dir /path/to/code

# With granularity control + direct issue→task mapping
./prd-pipeline/prd_pipeline.sh PRD.md --granularity fine --direct

# Step-by-step with manual approval
MANUAL_APPROVAL=true ./prd-pipeline/prd_pipeline.sh PRD.md
```

### Individual Steps

```bash
./prd-pipeline/prd_to_spec.sh PRD.md
./prd-pipeline/spec_to_issues.sh SPEC.md --granularity fine
./prd-pipeline/issue_to_tasks.sh SPEC.md ISSUES.md --direct
./prd-pipeline/task_executor.sh
```

### Task Execution Options

```bash
# Execute all pending tasks
./prd-pipeline/task_executor.sh

# Resume from breakpoint (skips done, retries failed)
./prd-pipeline/task_executor.sh --resume

# Retry only failed tasks
./prd-pipeline/task_executor.sh --retry-failed

# Run specific tasks by ID
./prd-pipeline/task_executor.sh --tasks TASK-001,TASK-003

# Verify acceptance criteria after each successful task
./prd-pipeline/task_executor.sh --verify-ac

# Auto-commit to a custom git branch (project mode only)
./prd-pipeline/task_executor.sh --git-branch feat/my-feature

# Check flat-layout progress
./prd-pipeline/progress.sh

# Check project-layout progress
./prd-pipeline/progress.sh --project my-project
```

### Agent Abstraction (AGENT_CMD)

The pipeline no longer hardcodes `claude -p`. Set `AGENT_CMD` env var to use a different AI agent:

```bash
# Claude (default)
AGENT_CMD="claude -p --dangerously-skip-permissions --no-session-persistence --output-format text"

# Codex CLI
AGENT_CMD="codex -p"

# Copilot CLI
AGENT_CMD="copilot -p --allow-tool"

# Gemini CLI
AGENT_CMD="gemini -p --skip-confirm --no-history"
```

All 3 pipeline scripts (`task_executor.sh`, `prd_to_spec.sh`, `spec_to_issues.sh`) use this variable.

### .agentrc Config File

Place `.agentrc` at the project root for persistent agent config:

```bash
AGENT_TYPE=claude
AGENT_CMD="claude -p --dangerously-skip-permissions ..."
AGENT_CONFIG=CLAUDE.md
```

See `.agentrc.example` for all options.

### Quality Gates (Project Mode)

After each successful task, the executor automatically:
1. **Runs tests** — detects pytest/jest/cargo test/go test and runs them
2. **Records results** — test pass/fail counts in task summary
3. **Generates delta spec** — OpenSpec-format delta for traceability

Quality gates do NOT block the pipeline — results are recorded in `summary.json` and visible in `summary.md`.

### Git Integration (Project Mode)

When `TARGET_DIR` is a git repository, the executor automatically:

1. **Creates a temporary branch** from HEAD (default: `auto/task-run-<timestamp>`, or use `--git-branch`)
2. **Commits each successful task** independently: `git add -A && git commit -m "TASK-NNN: <title>"`
3. **Cleans up after failed tasks**: `git checkout . && git clean -fd` so retries start clean
4. **Generates merge instructions** in the summary report:
   - All success → merge the branch to main
   - Partial failure → cherry-pick successful commits, then retry failed tasks

### Lightweight Loop (No PRD)

```bash
./claude_loop.sh tasks_example.txt
./claude_loop.sh "Read src/ and analyze code structure"
```

## Critical Conventions

### Bash Compatibility

All scripts target **bash 3.2** (macOS default). This means:
- No `mapfile` / `readarray` — use `while IFS= read -r`
- No associative arrays (`declare -A`) — use indexed arrays + linear scan
- Use `local` only inside functions

### File Path Safety

Always use null-safe patterns for file operations:
```bash
# ✅ Correct
while IFS= read -r -d '' f; do
    files+=("$f")
done < <(find "$DIR" -name '*.md' -print0 | sort -z)

# ❌ Wrong — breaks on filenames with spaces
files=($(find "$DIR" -name '*.md'))
```

### Exit Code Extraction from Pipelines

When piping into `claude`, the pipeline exit code is from `claude`, not `echo`:
```bash
echo "$prompt" | claude -p ...
rc=${PIPESTATUS[1]}   # ← claude's exit code, PIPESTATUS[0] is echo's
```

### `--skip-to` Semantics

`--skip-to <step>` means "start from this step, skip everything before it":
```bash
./prd_pipeline.sh PRD.md --skip-to tasks    # skip spec + issues, go to task generation
./prd_pipeline.sh PRD.md --skip-to execute  # skip to execution only (tasks must exist)
```

### `--direct` Semantics

Skips the Claude-based Issue→Task decomposition. Each Issue is directly wrapped into one Task file. Use when `--granularity fine` already made issues atomic enough.

### `--granularity`

Controls how many sub-tasks each issue decomposes into:
- `fine` (2-4 task/issue)
- `medium` (5-10 task/issue, default)
- `coarse` (10-20 task/issue)

### Project Mode (`--target-dir`)

When `--target-dir <path>` is passed, the pipeline operates in **project mode**:
- Intermediate documents are stored in `prd-pipeline/projects/<project-name>/`
- Task prompts automatically include the target project context (path, tech stack)
- After execution, a structured report (`summary.json` + `summary.md`) is generated in `04-execution/`
- The `--target-dir` must point to an existing directory (the codebase to modify)

Directory structure:
```
prd-pipeline/projects/<project-name>/
├── 01-spec/SPEC.md
├── 02-issues/ISSUES.md
├── 03-tasks/
│   ├── TASK-NNN-slug.md
│   └── task_board.md
└── 04-execution/
    ├── logs/               (per-task logs)
    ├── summary.json        (machine-readable)
    └── summary.md          (human-readable + next-step suggestions)
```

### New Flags

| Flag | Applies to | Description |
|------|------------|-------------|
| `--target-dir <path>` | `prd_pipeline.sh` | Enable project mode, point to code directory |
| `--project-name <name>` | `prd_pipeline.sh` | Override auto-detected project name |
| `--verify-ac` | `task_executor.sh` | Verify acceptance criteria after each successful task |

### Output Files (project mode only)

| File | Content |
|------|---------|
| `04-execution/summary.json` | Per-task structured data (id, status, files changed, failure reason, AC result) |
| `04-execution/summary.md` | Human-readable overview with failure analysis and next-step suggestions |
| `logs/<TASK-ID>/git_diff.json` | Git diff stats captured after each task execution (before/after HEAD) |
| `logs/<TASK-ID>/ac_verify.json` | AC verification result (passed/failed/unknown) |

### State Machine

```
pending ──► running ──► done
                 │
                 └──► failed ──► pending (retry, max MAX_RETRIES=3)
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_RETRIES` | `3` | Max retry attempts per task |
| `PARALLEL` | `1` | Parallel task count (experimental — see note below) |
| `MANUAL_APPROVAL` | `false` | Pause between pipeline steps for manual review |
| `ISSUE_GRANULARITY` | `medium` | Issue decomposition granularity |
| `CLAUDE` | `claude` | Claude CLI path |
| `CLAUDE_OPTS` | `--dangerously-skip-permissions` | Extra args to claude CLI |
| `TARGET_DIR` | — | Target code directory (set by `--target-dir` flag) |
| `PROJECT_NAME` | — | Override auto-detected project name |
| `WORK_DIR` | `$(pwd)` | Working directory for `claude_loop.sh` |
| `LOG_DIR` | `./.claude_loop_logs` | Log directory for `claude_loop.sh` |

## Known Limitations

- **Parallel execution** (`PARALLEL > 1`): Background subshells cannot propagate in-memory status arrays back to the parent, and concurrent writes to `task_board.md` race. Only use serial mode (`PARALLEL=1`, the default) in production.
- **Log directory** for `claude_loop.sh` defaults to `./.claude_loop_logs/` — set `LOG_DIR` to override.
