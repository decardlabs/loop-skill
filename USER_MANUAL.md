# spec-forge 用户手册

> 从需求到代码的自动化锻造炉

---

## 一、概念

### spec-forge 是什么？

spec-forge 是一个 AI 辅助的自动编码流程。它接收你的需求描述，自动完成以下工作：

1. **理解需求** → 2. **拆解任务** → 3. **逐个执行** → 4. **质量检查** → 5. **交付代码**

整个过程像一条流水线：你输入需求，它输出代码 + 测试 + Git commit + 执行报告。

### 四个组件的关系

```
你写的需求（PRD.md 或 自然语言）
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│                     spec-forge Skill                          │
│  一个 Skill 定义文件（SKILL.md），告诉 AI 怎么按 5 步流程工作   │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐              │
│  │ SPEC │→│ PLAN │→│ FORGE│→│CLOSE │→│FINISH│              │
│  │ 定需求│ │ 拆任务│ │ 执行+│ │ 写回 │ │ 交付 │              │
│  └──────┘ └──────┘ └──┬───┘ └──────┘ └──────┘              │
└────────────────────────┼──────────────────────────────────────┘
                         │ 调用
                         ▼
┌──────────────────────────────────────────────────────────────┐
│                   loop 管线（执行引擎）                        │
│  bash 脚本，实际驱动整个流程。不依赖任何 AI 框架。              │
│  prd_pipeline.sh → task_executor.sh → summary.md              │
│  AGENT_CMD 抽象：支持 Claude / Codex / Copilot 等多种 CLI     │
└──────────────────────────────────────────────────────────────┘
```

**可选的两层增强：**

| 层 | 提供什么 | 不装会怎样 |
|----|---------|-----------|
| **Superpowers** | skill 自动加载、代码审查流程、分支完成管理 | skill 需手动加载，review/finish 流程手动操作 |
| **OpenSpec CLI** | 结构化规格、delta 变更管理、自动 archive | 用自由格式 PRD.md 输入，功能不受影响 |

### 核心设计原则

1. **文件是接口** — 三个项目之间通过 `.md` 和 `.json` 文件交换数据，不跨语言调用
2. **向后兼容** — 不加新参数时行为零变化
3. **渐进采用** — 可以从裸 loop 开始，逐步加入 Superpowers 和 OpenSpec
4. **Agent 无关** — 执行引擎不绑定 Claude，支持任何 CLI 管道模式

---

## 二、推荐使用方式

### 路径 A：个人开发者（推荐起步）

**目标：** 快速从需求到代码，不关心复杂流程。

```
安装: loop 管线
技能: 手动加载 spec-forge 或 使用 Superpowers
输入: PRD.md 或 直接说需求
```

```bash
# 1. 确保 loop 管线在项目目录下
cd my-project
ls prd-pipeline/ 2>/dev/null || cp -r /path/to/loop/prd-pipeline .

# 2. 写一份 PRD
cat > prd-pipeline/PRD.md <<EOF
# PRD: 用户注册功能
## 需求
- 手机号+密码注册
- 验证码发送
- 登录/登出
EOF

# 3. 运行（使用 Claude Code）
claude
# 在 Claude Code 中:
# /forge "prd-pipeline/PRD.md 中的需求"
```

**推荐指数：** ⭐⭐⭐⭐⭐

### 路径 B：团队协作（推荐标准）

**目标：** 可追溯的需求→代码链路，代码审查。

```
安装: loop 管线 + Superpowers
技能: Superpowers 自动加载
输入: PRD.md 或 OpenSpec specs
```

```bash
# 1. 安装 Superpowers 插件
# 按 Superpowers 文档安装

# 2. 复制 spec-forge skill
cp -r superpowers/skills/spec-forge .claude/plugins/superpowers/skills/

# 3. 配置 .agentrc
cp .agentrc.example .agentrc
# 编辑 AGENT_CMD 匹配你的 Agent

# 4. 启动 Claude Code
claude
# skill 自动加载，直接 /forge "实现用户注册功能"
# Superpowers 会在执行后自动触发代码审查
```

**推荐指数：** ⭐⭐⭐⭐⭐

### 路径 C：完整规约驱动（推荐进阶）

**目标：** 结构化规格、全链路追溯、自动归档。

```
安装: loop 管线 + Superpowers + OpenSpec CLI
技能: Superpowers 自动加载 + OpenSpec 斜杠命令
输入: 结构化 specs
```

```bash
# 1. 安装 OpenSpec CLI
npm install -g @fission-ai/openspec

# 2. 初始化 OpenSpec
openspec init
# 生成 openspec/specs/ + openspec/changes/

# 3. 提出需求
openspec propose "用户注册功能"
# 生成 proposal.md → specs → design → tasks.md

# 4. 创建 .agentrc
cp .agentrc.example .agentrc
echo 'AGENT_CMD="claude -p ..."' >> .agentrc

# 5. 启动 Claude Code，执行 /forge
claude
# /forge 会自动读取 openspec/specs/ 作为输入
# 执行完毕后自动写回 status.md，触发 archive
```

**推荐指数：** ⭐⭐⭐⭐（安装步骤稍多）

### 快速选择表

| 你的情况 | 推荐路径 | 安装耗时 | 功能完整度 |
|---------|---------|---------|-----------|
| 个人项目，快速出活 | **A** | 2 分钟 | ★★★ |
| 团队项目，需要 code review | **B** | 15 分钟 | ★★★★★ |
| 大型项目，需要需求追溯 | **C** | 30 分钟 | ★★★★★★ |
| "先试试好不好用" | **A** | 2 分钟 | ★★★ |
| "我已经有 Superpowers 了" | **B** | 1 分钟 | ★★★★★ |
| "我已经有 OpenSpec 了" | **C → 直接可用** | 0 分钟 | ★★★★★★ |

---

## 三、完整流程演示

### 用户视角：一次典型的 /forge 会话

```
$ claude

[Claude Code 启动，Superpowers 自动加载 spec-forge]

> /forge "给博客系统添加标签功能"

  [1/5] SPEC 阶段 — 理解需求...
    检测到：
    ├─ openspec/  → 已初始化
    ├─ PRD.md     → 未找到
    └─ 使用 OpenSpec propose 生成规格

    正在分析你的需求...
    → 生成 proposal.md
    → 生成 specs/blog/tags.md
    → 生成 design.md
    → 生成 tasks.md

    是否继续？用户确认 → 进入下一阶段

  [2/5] PLAN 阶段 — 拆解任务...
    → TASK-001: 创建 tags 数据库表 + ORM 模型
    → TASK-002: 实现标签 CRUD API
    → TASK-003: 博客文章关联标签功能
    → TASK-004: 前端标签管理页面

    共 4 个 task，是否确认？用户确认 → 进入执行

  [3/5] FORGE 阶段 — 锻造代码...

    TASK-001: 创建 tags 表 ✅
      ├─ AC 验证: ✅ tags 表创建成功
      ├─ 测试:    ✅ pytest 2/2 通过
      └─ Commit:  a1b2c3d

    TASK-002: 标签 CRUD API ✅
      ├─ AC 验证: ✅ curl 返回 201/200/204
      ├─ 测试:    ✅ pytest 5/5 通过
      └─ Commit:  e4f5g6h

    TASK-003: 文章关联标签 ⚠️
      ├─ AC 验证: ✅ 关联关系正常
      ├─ 测试:    ⚠️ 1 个测试失败（已有 test 未更新）
      └─ Commit:  i7j8k9l

    TASK-004: 前端标签管理 ✅
      ├─ AC 验证: ✅ 页面渲染正常
      ├─ 测试:    — (无前端测试框架)
      └─ Commit:  m0n1o2p

  [4/5] CLOSE 阶段 — 写回规约...
    → status.md: 已更新 (4/4 task，AC 3/4 通过)
    → delta spec: 已生成 (3 个 ADDED)
    → archive: 可以归档

  [5/5] FINISH 阶段 — 交付...

    执行摘要:
    ├─ 全部 4/4 task 完成
    ├─ AC 通过率: 75%
    ├─ 测试通过率: 87% (7/8)
    ├─ 分支: auto/task-run-20260707-153000
    └─ 提交: 4 个 commit

    建议: git merge auto/task-run-20260707-153000
    合并到 main? [Y/n]
```

### 执行后的目录状态

```
my-blog/
├── openspec/
│   ├── specs/blog/
│   │   └── tags.md                 ← NEW: 标签功能规格
│   └── changes/add-tags/
│       ├── proposal.md             ← 原始需求
│       ├── design.md               ← 设计方案
│       ├── tasks.md                ← 任务清单
│       ├── status.md               ← NEW: 执行结果
│       └── verification.md         ← NEW: AC 验证记录
│
├── prd-pipeline/projects/my-blog/
│   ├── 03-tasks/TASK-001-*.md      ← 4 个 task 文件
│   └── 04-execution/
│       ├── summary.json            ← 机器可读报告
│       ├── summary.md              ← 人类可读报告
│       └── logs/                   ← 每 task 执行日志
│
├── src/                            ← 代码
│   └── blog/
│       ├── models/tag.py           ← NEW
│       ├── routes/tags.py          ← NEW
│       └── templates/tags.html     ← NEW
│
├── .agentrc                        ← Agent 配置
└── .git/
    └── auto/task-run-20260707-153000  ← 临时执行分支
```

---

## 四、常见场景问答

### 场景 1：我只有一条简单的需求

```bash
# 不需要写 PRD，直接对 Claude 说需求
claude
> /forge "给我的 Django 项目添加用户头像上传功能"
```

spec-forge 会直接进入 SPEC 阶段，帮你生成设计文档后再执行。

### 场景 2：我只想跑已经拆好的 task 文件

```bash
cd prd-pipeline
./task_executor.sh
```

这是最简路径——不经过 SPEC 和 PLAN 阶段，直接执行已有 task。

### 场景 3：我的 task 执行到一半终端关了

```bash
# 断点续跑
cd prd-pipeline
./task_executor.sh --resume
```

loop 会自动跳过已完成的 task，只跑 pending 和 failed 的。

### 场景 4：我想看看执行得怎么样了

```bash
cd prd-pipeline
./progress.sh --project my-blog
```

或在 Claude Code 里 `/review-report`。

### 场景 5：我用 Codex 不是 Claude

```bash
# 方式一：环境变量
AGENT_CMD="codex -p" ./prd-pipeline/task_executor.sh

# 方式二：.agentrc 持久化配置
echo 'AGENT_CMD="codex -p"' > .agentrc
```

### 场景 6：执行失败了怎么办

```bash
# 查看执行报告
cat prd-pipeline/projects/*/04-execution/summary.md

# 报告会告诉你怎么做:
# - 全部成功 → git merge
# - 部分失败 → git cherry-pick 成功的 commit，修复后重跑
# - 失败 task → //forge 或 ./task_executor.sh --retry-failed
```

### 场景 7：怎么多人协作

```
开发者 A: 写 PRD → /forge → 生成代码
              ↓
Git push 到远程仓库
              ↓
开发者 B: git pull → 看 summary.md → 看 git log
          → 知道哪些 task 执行过、改了什么文件
          → 在合并前做人工 code review
```

每一轮执行都是独立的分支（`auto/task-run-<ts>`），不影响 main 分支。

---

## 五、规格说明

### Agent 要求

| 要求 | 最低 | 推荐 |
|------|------|------|
| CLI 管道模式 | `echo prompt | cmd -p` | ✅ 所有 AI CLI 都支持 |
| 退出码 | 成功 0，失败 非 0 | ✅ POSIX 标准 |
| 无确认执行 | 无确认模式 | Claude: `--dangerously-skip-permissions`
| 自动加载 | 不需要 | Superpowers session-start hook |

### 输入格式

| 格式 | 示例 | 适用阶段 |
|------|------|---------|
| 自然语言 | "给博客加标签功能" | SPEC 阶段 |
| PRD.md | 自由格式 Markdown | SPEC 阶段 |
| OpenSpec specs/ | 结构化 Given/When/Then | SPEC 阶段（跳过 PRD→SPEC 拆解） |
| OpenSpec tasks.md | 复选框列表 | PLAN 阶段（跳过拆解，直接转换） |

### 输出产物

| 产物 | 位置 | 用途 |
|------|------|------|
| 执行报告 | `04-execution/summary.md` | 人类阅读，了解执行结果 |
| 机器报告 | `04-execution/summary.json` | 其他工具读取 |
| 执行日志 | `04-execution/logs/<TASK-NNN>/` | 排查失败原因 |
| Git commit | `auto/task-run-<ts>` 分支 | 代码版本管理 |
| delta spec | `openspec/changes/<name>/specs/` | 需求变更追踪（OpenSpec 模式） |
| status | `openspec/changes/<name>/status.md` | 执行状态写回（OpenSpec 模式） |

---

## 六、名词对照

| 术语 | 说明 |
|------|------|
| **spec-forge** | 融合技能，协调 loop、Superpowers、OpenSpec 三个项目的 5 阶段流程 |
| **loop** | 自动化执行管线，bash 脚本，不依赖任何 AI 框架 |
| **Superpowers** | AI 开发方法论，提供质量门禁和流程管控 |
| **OpenSpec** | 结构化规约工具，用 Given/When/Then 格式定义需求 |
| **AGENT_CMD** | 环境变量，指定实际执行代码生成的 AI CLI 命令 |
| **.agentrc** | 配置文件，统一管理 Agent 类型和参数 |
| **quality gate** | 质量门禁—执行后自动运行测试和代码检查 |
| **delta spec** | 增量规格，记录 ADDED/MODIFIED/REMOVED 的需求变更 |
