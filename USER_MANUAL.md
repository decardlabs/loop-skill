# spec-forge 用户手册

> 从需求到代码的完整方法论与工具链

---

## 第一卷：方法论

### 第一章：AI 辅助开发的困境

当前 AI 编码的常见问题：

```
你： "帮我实现一个用户注册功能"
AI：   写了一大堆代码
你： "这不是我想要的，我要的是手机号注册，不是邮箱"
AI：   重写
你： "数据库表结构不对"
AI：   再重写
```

**问题出在哪里？**

1. **需求在聊天记录里** — 关掉终端就没了，下次从头解释
2. **没有设计阶段** — AI 直接跳到代码，跳过架构决策
3. **没有质量门禁** — AI 写完就说完成了，但可能没测试、没考虑边界情况
4. **不可追溯** — 两周后看代码，不知道当时为什么这么写

**传统软件工程解决这些问题的方法是：** 需求文档 → 架构设计 → 详细设计 → 编码 → 测试 → 代码审查 → 上线。但这套流程太重，在 AI 时代需要重新设计。

### 第二章：三层方法论

spec-forge 所代表的是一种**分层方法**，它将软件开发拆成三个独立可管理的层次：

```
┌──────────────────────────────────────────────────────────────┐
│                     第一层：规约层                            │
│                     回答"做什么"                             │
│                                                              │
│  产物: 结构化规格（Given/When/Then 场景）                     │
│  工具: OpenSpec                                              │
│  原则: 需求必须先写下来，不能只存在脑子里或聊天记录里             │
├──────────────────────────────────────────────────────────────┤
│                     第二层：执行层                            │
│                     回答"怎么做"                             │
│                                                              │
│  产物: 原子任务 → 代码 → Git commit                          │
│  工具: loop 管线                                              │
│  原则: 任务必须可执行、可重试、可追溯，每个任务独立提交           │
├──────────────────────────────────────────────────────────────┤
│                     第三层：流程层                            │
│                     回答"怎么工作"                           │
│                                                              │
│  产物: 设计文档 → 执行计划 → 代码审查 → 完成确认               │
│  工具: Superpowers                                            │
│  原则: 先设计再编码、先测试再实现、先审查再合并                  │
└──────────────────────────────────────────────────────────────┘
```

**三层之间的关系：**

```
规约层（OpenSpec）定义 WHAT
        │  specs 作为输入
        ▼
执行层（loop）实现 HOW
        │  执行结果写回
        ▼
规约层（OpenSpec）闭环——状态更新、delta 归档
        ▲
        │  Superpowers 全程管控流程合规
流程层（Superpowers）:
  设计门禁 → 计划门禁 → TDD 门禁 → 审查门禁 → 合并门禁
```

### 第三章：科学方法 — 从 PRD 到代码的完整路径

这种方法背后的科学逻辑可以概括为**"假设—验证—记录"**循环：

```
┌─────────────────────────────────────────────────────────────────┐
│  步骤          │  做什么           │  科学类比             │
├─────────────────────────────────────────────────────────────────┤
│  1. PRD       │ 写需求文档         │ 提出假说              │
│  2. SPEC      │ 设计技术方案       │ 设计实验              │
│  3. Issues    │ 拆功能单元         │ 分解实验步骤           │
│  4. Tasks     │ 拆原子任务         │ 定义可验证的断言        │
│  5. 执行      │ 逐个实现           │ 运行实验              │
│  6. AC 验证   │ 检查验收标准       │ 验证结果是否符合预期    │
│  7. 测试      │ 自动运行测试       │ 回归检验              │
│  8. Review    │ 代码审查           │ 同行评议              │
│  9. 报告      │ 汇总执行结果       │ 记录实验报告           │
│  10. 归档     │ 更新规约、合并分支  │ 发表结论              │
└─────────────────────────────────────────────────────────────────┘
```

**为什么必须分层：**

如果你把所有步骤混在一起，就像医生不做诊断就直接开刀。每一层解决的问题不同：

| 层 | 解决的问题 | 如果不分层会怎样 |
|---|-----------|----------------|
| 规约 | "我们要做什么" | AI 猜需求，猜错了重写 |
| 执行 | "代码怎么写" | 任务边界模糊，失败后无处重试 |
| 流程 | "工作方式对不对" | 跳过设计、跳过测试、跳过审查 |

---

## 第二卷：工具

### 第四章：Superpowers — 流程层

#### 4.1 它解决什么问题

Superpowers 解决的是**"AI 太听话"**的问题。你让 AI 写代码，它马上就写——不问为什么、不检查依赖、不写测试、不审查自己的代码。Superpowers 通过在 AI 的思考过程中注入**硬门禁（Hard Gates）**来强制流程。

#### 4.2 14 个技能（Skills）

Superpowers 定义了 14 个技能，每个技能是一个 SKILL.md 文件，告诉 AI 在特定场景下应该怎么做：

```
技能树（按使用顺序）:

开始工作前:
  using-superpowers    — 加载所有技能，告诉 AI "做事之前先查技能"
  brainstorming        — 设计讨论：探索、提问、出方案、写设计文档
  writing-plans        — 将设计拆成 2-5 分钟的原子任务

执行工作时:
  subagent-driven-development  — 子代理模式：每个任务派一个独立 AI 执行
  executing-plans              — 手动模式：在当前会话中逐个执行任务
  test-driven-development      — TDD 强制：先写测试再写代码

处理问题时:
  systematic-debugging — 系统化调试：先找根因再修，而不是"试试这个"
  dispatching-parallel-agents  — 并行排查：多个独立问题同时调查

交付前:
  requesting-code-review  — 代码审查：派审查子代理检查代码质量
  receiving-code-review   — 接收审查意见：不盲目同意，用技术反驳
  verification-before-completion  — 完成验证：先跑测试再宣布完成
  using-git-worktrees     — Git 工作树隔离：不影响主分支
  finishing-a-development-branch  — 分支完成：合并/PR/保留/丢弃

维护技能本身:
  writing-skills         — 写新技能：用 TDD 方式写 SKILL.md
```

#### 4.3 硬门禁（Hard Gates）

Superpowers 最核心的概念是**硬门禁**——在代码里写死的规则，AI 不能绕过：

```
🔴 设计门禁（brainstorming）:
   没有经过用户确认的设计文档之前，不能写任何代码

🔴 TDD 铁律（test-driven-development）:
   没有失败的测试之前，不能写实现代码。如果代码已经存在，删掉

🔴 调试门禁（systematic-debugging）:
   没有找到根因之前，不能修 bug

🔴 验证门禁（verification-before-completion）:
   没有重新运行验证之前，不能说"修好了"

🔴 审查门禁（requesting-code-review）:
   没有代码审查之前，不能合并到主分支
```

#### 4.4 自动加载机制

Superpowers 通过 `session-start` hook 自动注入——每次 Claude Code 启动时，hook 脚本读取 `using-superpowers/SKILL.md` 并将其注入到 AI 的上下文开头。AI 被告知"在所有响应之前，先查技能"。

这就是为什么 Superpowers 被称为**"AI 开发方法论"**——它不是工具，而是一套行为指南。

---

### 第五章：OpenSpec — 规约层

#### 5.1 它解决什么问题

OpenSpec 解决的是**"需求只存在于对话中"**的问题。你和 AI 聊了一个小时确定了需求，下次打开终端全忘了。OpenSpec 把需求写成**结构化的、版本化的、可审查的 Markdown 文件**。

#### 5.2 核心数据模型

```
openspec/
├── config.yaml                 ← 项目配置
├── specs/                      ← 主规约（版本化的需求）
│   └── <domain>/
│       └── spec.md             ← 使用 Given/When/Then 格式
│
└── changes/                    ← 变更集（一次开发的工作单元）
    ├── <change-name>/
    │   ├── .openspec.yaml      ← 元数据
    │   ├── proposal.md         ← 为什么要改
    │   ├── specs/              ← delta 规约（只描述差异）
    │   │   └── <domain>/
    │   │       └── spec.md     ← ADDED / MODIFIED / REMOVED
    │   ├── design.md           ← 怎么改
    │   └── tasks.md            ← 具体任务清单
    └── archive/                ← 已归档的变更
```

Spec 文件格式：

```markdown
# 用户认证 Specification

## Purpose
处理用户注册和登录

## Requirements
### Requirement: 手机号注册
用户SHALL使用手机号注册账号
#### Scenario: 成功注册
- GIVEN 用户使用未注册的手机号
- WHEN 用户提交注册请求
- THEN 系统创建账号并返回 JWT token
```

Delta spec 格式（change 内部）：

```markdown
## ADDED Requirements
### Requirement: 社交账号登录
用户SHALL支持微信/Google 登录

## MODIFIED Requirements
### Requirement: 登录频率限制
从 5次/分钟 改为 10次/分钟

## REMOVED Requirements
### Requirement: 短信验证
移除短信验证，改用邮件验证
```

#### 5.3 Change 生命周期

```
proposal → specs (delta) → design → tasks → apply → archive
    │          │            │        │        │       │
    ▼          ▼            ▼        ▼        ▼       ▼
  提议      定义变更      设计方案   任务清单  实现   归档合并
```

这个流程对应了"讨论—设计—执行—归档"的自然节奏。关键在于：

- **Delta 机制**：每次 change 只描述"和当前有什么不同"，不是从头写一遍
- **Archive 合并**：归档时 delta 自动合并到主 specs，ADDED 追加、MODIFIED 替换、REMOVED 删除
- **DAG 依赖**：proposal → specs/design → tasks → apply，每步可独立推进

#### 5.4 两种交互方式

```
终端 CLI（手动操作）:              AI 斜杠命令（在聊天中触发）:
  openspec init                    /opsx:explore
  openspec propose <name>          /opsx:propose
  openspec list                    /opsx:apply
  openspec validate                /opsx:sync
  openspec archive                 /opsx:archive
  openspec doctor                  /opsx:verify
```

OpenSpec 支持 30+ AI 工具——同一套 specs 可以被 Claude、Cursor、Codex、Copilot 等读取。

---

### 第六章：loop — 执行层

#### 6.1 它解决什么问题

loop 解决的是**"AI 执行不可靠"**的问题。AI 写代码可能失败、可能超时、可能跑偏。loop 用 shell 脚本实现了可靠的执行引擎：

- 失败自动重试（最多 3 次）
- 断点续跑（关了终端也不丢进度）
- Git 自动 commit（每个 task 独立提交）
- 结构化报告（summary.json + summary.md）

#### 6.2 核心流程

```
PRD.md 或 OpenSpec specs
        │
        ▼
prd_pipeline.sh（主编排器）
        │
        ├─→ prd_to_spec.sh      ← 理解需求，生成技术规格
        ├─→ spec_to_issues.sh   ← 拆功能单元
        ├─→ issue_to_tasks.sh   ← 拆原子任务
        │
        ▼
task_executor.sh（核心执行器）
        ├─ 拓扑排序（按依赖顺序）
        ├─ 每个 task:
        │   ├─ echo prompt | $AGENT_CMD  ← 调 AI 执行
        │   ├─ git commit                 ← 自动提交
        │   ├─ 质量门禁: 运行测试         ← 自动验证
        │   └─ 失败则重试（最多 3 次）
        │
        ▼
summary.md + summary.json（执行报告）
```

#### 6.3 关键设计

- **AGENT_CMD 抽象**：不绑定 Claude，支持 Codex、Copilot、Gemini 等任何支持管道模式的 CLI
- **Git 分支隔离**：每次执行在 `auto/task-run-<ts>` 分支上操作，不影响 main
- **质量门禁**：执行后自动检测并运行测试（pytest/jest/cargo/go）
- **向后兼容**：不加参数时行为与原始版本完全一致

---

## 第三卷：融合

### 第七章：三层融合原理

三个工具各自解决一个层面的问题，融合后形成完整的开发方法论：

```
你: "给博客加标签功能"
  │
  ▼
┌─────────────────────────────────────────────────────────────────────┐
│  1. SPEC 阶段 ── 定义"做什么"                                       │
│                                                                     │
│  OpenSpec 自动（或你有 PRD.md）:                                     │
│    openspec propose "add-tag"                                        │
│    → proposal.md: 为什么要加标签                                     │
│    → specs/blog/tags.md: Given/When/Then 场景                        │
│    → design.md: 数据模型 + API + 前端方案                             │
│    → tasks.md: 任务清单                                              │
│                                                                     │
│  Superpowers 门禁: 用户必须 approve 设计才能进入下一阶段               │
├─────────────────────────────────────────────────────────────────────┤
│  2. PLAN 阶段 ── 定义"怎么做"                                        │
│                                                                     │
│  loop 拆解:                                                         │
│    issue_to_tasks.sh → TASK-001-*.md                                │
│    每个 task 包含: 精确文件路径 + 验收标准 + 完整 prompt              │
│                                                                     │
│  Superpowers 门禁: task 必须用户 approve 才能执行                     │
├─────────────────────────────────────────────────────────────────────┤
│  3. FORGE 阶段 ── 执行 + 质量门禁（核心）                             │
│                                                                     │
│  loop 自动执行:                                                      │
│    task_executor.sh → $AGENT_CMD → 代码 → git commit                  │
│    质量门禁: 运行测试 → 记录结果                                      │
│    失败重试: 最多 3 次，每次换方式                                     │
│                                                                     │
│  Superpowers 门禁（在 spec-forge 设计中被补偿）:                       │
│    TDD 铁律 → 自动测试门禁                                           │
│    审查门禁 → 执行后 review 触发                                      │
│    验证门禁 → AC 验证                                                │
├─────────────────────────────────────────────────────────────────────┤
│  4. CLOSE 阶段 ── 写回规约                                           │
│                                                                     │
│  loop 自动写回:                                                      │
│    status.md: 每个 task 的执行状态 + commit hash                     │
│    delta spec: ADDED/MODIFIED/REMOVED                                │
│                                                                     │
│  OpenSpec（可选）:                                                    │
│    openspec archive → delta 合并到主 specs → change 移入 archive     │
├─────────────────────────────────────────────────────────────────────┤
│  5. FINISH 阶段 ── 交付                                              │
│                                                                     │
│  Superpowers finishing-a-development-branch:                         │
│    验证测试 → 展示摘要 → merge/PR/keep/discard 选项                  │
│                                                                     │
│  git merge auto/task-run-<ts> → 代码合并到 main                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 第八章：目录结构全景（完整融合后）

一个项目在完整融合后的目录结构：

```
my-project/
│
├── .agentrc                       ← Agent 配置
├── CLAUDE.md                      ← Agent 项目配置
│
├── openspec/                      ← ===== 规约层（OpenSpec）=====
│   ├── config.yaml                ← 项目背景、规则
│   ├── specs/                     ← 主规约（版本化的需求）
│   │   ├── auth/spec.md           ← 用户认证规范
│   │   └── blog/spec.md           ← 博客功能规范
│   └── changes/
│       └── add-tag/
│           ├── proposal.md        ← 原始需求
│           ├── specs/blog/spec.md ← delta（ADDED）
│           ├── design.md          ← 设计方案
│           ├── tasks.md           ← 任务清单
│           ├── status.md          ← NEW: loop 执行结果
│           └── verification.md    ← NEW: AC 验证记录
│
├── prd-pipeline/                  ← ===== 执行层（loop）=====
│   ├── task_executor.sh           ← 核心执行器
│   ├── projects/
│   │   └── my-project/
│   │       ├── 03-tasks/          ← 原子任务文件
│   │       └── 04-execution/      ← 执行报告
│   │           ├── summary.json   ← 机器可读
│   │           ├── summary.md     ← 人类可读
│   │           └── logs/          ← 每 task 日志
│   └── ...
│
├── .claude/                       ← ===== 流程层（Superpowers）=====
│   ├── plugins/superpowers/       ← Superpowers 插件
│   │   ├── skills/
│   │   │   ├── spec-forge/        ← NEW: 融合技能
│   │   │   ├── brainstorming/
│   │   │   ├── writing-plans/
│   │   │   └── ...                ← 其他 14 个技能
│   │   └── hooks/session-start    ← 自动注入 hook
│   └── hooks/hooks.json           ← hook 配置
│
├── src/                           ← ===== 实际代码 =====
│   ├── api/tags.py                ← NEW: 由 spec-forge 生成
│   └── templates/tags.html        ← NEW: 由 spec-forge 生成
│
└── .git/
    └── refs/heads/
        ├── main                   ← 主分支
        └── auto/task-run-20260707-*  ← 临时执行分支
```

### 第九章：融合的价值链

为什么三层融合比单用任何一个工具都强：

| 维度 | 只用 loop | 只用 Superpowers | 只用 OpenSpec | 三合一 |
|------|----------|-----------------|--------------|--------|
| 需求管理 | PRD.md 在聊天记录里 | 在对话中讨论设计 | **结构化 specs 持久化** | ✅ 最完整 |
| 任务拆解 | 自动拆 | 手动在 plan 里写 | 只有复选框 | ✅ 自动 + 可执行 |
| 执行 | **自动循环** | 手动逐个跑 | 手动 apply | ✅ 最省心 |
| 重试 | **自动 3 次** | 失败了重来 | 无 | ✅ 最可靠 |
| Git 管理 | **自动 commit** | 手动 commit | 不涉及 | ✅ 最省心 |
| 质量门禁 | 运行测试 | **TDD + Review** | 无 | ✅ 最全面 |
| 报告 | **summary.md** | 人工看 | 无 | ✅ 最清晰 |
| 追溯 | commit → task | 无 | **spec→change** | ✅ **全链路** |

---

## 第四卷：学习路径

### 第十章：推荐学习顺序

如果你是第一次接触这套体系，**不要一次性全部安装**。按以下顺序逐步学习：

#### 第一阶段：感受 loop（第 1 天）

```bash
# 1. 下载 loop 管线
cd my-project
git clone https://github.com/decardlabs/loop-skill.git /tmp/loop
cp -r /tmp/loop/prd-pipeline .

# 2. 写一个简单的 PRD
cat > prd-pipeline/PRD.md <<EOF
# PRD: 添加用户头像上传
- 用户可在个人设置页上传头像
- 支持 jpg/png，最大 2MB
- 后端存储到本地文件系统
EOF

# 3. 执行全流程
cd prd-pipeline
./prd_pipeline.sh PRD.md --target-dir .. --granularity fine --direct

# 4. 查看结果
./progress.sh
```

**学到的概念：** PRD→SPEC→Issues→Tasks 四级分解、自动执行、Git 自动 commit、执行报告。

#### 第二阶段：理解 Superpowers 的流程理念（第 2-3 天）

**不需要安装 Superpowers！** 先理解它在理念上强调什么：

- **先设计再编码** — 看到需求不要急着让 AI 写代码，先问："设计文档在哪里？"
- **先测试再实现** — 写代码之前先写测试
- **先审查再合并** — 代码完成后要审查
- **验证后宣布** — 跑完测试并确认通过后再说"完成了"

把这四条原则记在脑子里。就算只用 loop，也可以按这个节奏手动操作。

#### 第三阶段：安装 Superpowers（第 3-4 天）

```bash
# 按 Superpowers 文档安装插件
# 在 Claude Code 中: /plugin install <superpowers-url>

# 验证
ls .claude/plugins/superpowers/skills/
# 应该看到 14 个 skill 目录
```

在 Claude Code 中体验 `/brainstorming` 和 `/requesting-code-review`，感受硬门禁的工作方式。

#### 第四阶段：理解 OpenSpec 的价值（第 4-5 天）

先不急着安装，想想你的项目有没有遇到过这些问题：

- "这个功能当时为什么这么设计？" → OpenSpec 的 design.md 记录了决策
- "这个需求是什么时候加的？" → OpenSpec 的 change 记录了时间线
- "这个接口的验收标准是什么？" → OpenSpec 的 spec.md 定义了 Given/When/Then

如果这些问题困扰你，再安装 OpenSpec。

```bash
npm install -g @fission-ai/openspec
cd my-project
openspec init
openspec propose "了解 OpenSpec"
# 在 openspec/changes/ 里查看生成的文件
```

#### 第五阶段：完整融合（第 5-7 天）

```bash
# 确保三者都已就绪
ls prd-pipeline/task_executor.sh      ← loop 管线
ls .claude/plugins/superpowers/       ← Superpowers
openspec --version                    ← OpenSpec CLI

# 复制 spec-forge skill
cp -r superpowers/skills/spec-forge .claude/plugins/superpowers/skills/

# 配置 Agent
cp .agentrc.example .agentrc

# 启动 Claude Code，输入 /forge "你的需求"
```

### 第十一章：常见学习误区

| 误区 | 真相 |
|------|------|
| "我必须一次性学完所有东西" | **不需要。** 从 loop 开始，按自己的节奏逐步加入 Superpowers 和 OpenSpec |
| "Superpowers 只是在 Claude Code 里加了一堆规则" | **不对。** 它是一套经过验证的 AI 开发方法论。硬门禁的目的是"慢就是快" |
| "OpenSpec 太重了，写文档的时间比写代码还多" | **不对。** specs 是 AI 帮你生成的。你只需要 approve 或修改 |
| "自动化流程会取代我的判断" | **不对。** spec-forge 在每个关键节点都要求你确认（设计→计划→执行→交付），不是全自动 |
| "这三个项目太复杂了，我只需要一个能写代码的工具" | **简化版就是 loop 管线。** 只装 loop 就能用，5 分钟上手 |

### 第十二章：学习资源

| 资源 | 位置 | 适合 |
|------|------|------|
| loop README | `prd-pipeline/README.md` | 了解执行引擎细节 |
| Superpowers README | `superpowers/README.md` | 了解完整方法论 |
| OpenSpec README | `OpenSpec/README.md` | 了解规约系统 |
| spec-forge SKILL.md | `.claude/plugins/superpowers/skills/spec-forge/SKILL.md` | 了解 5 阶段流程 |
| DEPLOY.md | `DEPLOY.md` | 部署和安装 |
| 快速选择表 | 本手册第二章 | 选择适合你的路径 |

---

## 第五卷：附录

### 附录 A：术语对照表

| 术语 | 发音 | 说明 |
|------|------|------|
| **spec-forge** | /spek fɔːrdʒ/ | 融合技能，5 阶段流程的编排者 |
| **loop** | /luːp/ | 自动化执行管线 |
| **Superpowers** | /ˈsuːpərˌpaʊərz/ | AI 开发方法论 |
| **OpenSpec** | /ˈoʊpən spek/ | 结构化规约工具 |
| **Hard Gate** | /hɑːrd ɡeɪt/ | 硬门禁，不可绕过的质量规则 |
| **Delta Spec** | /ˈdeltə spek/ | 增量规约，只描述变更差异 |
| **SKILL.md** | /skɪl em diː/ | Superpowers 技能定义文件 |
| **AGENT_CMD** | /ˈeɪdʒənt kəˈmænd/ | Agent CLI 命令配置 |
| **PRD** | /piː ɑːr diː/ | 产品需求文档 |
| **Quality Gate** | /ˈkwɒlɪti ɡeɪt/ | 质量门禁 |
| **Session-Start Hook** | /ˈseʃən stɑːrt hʊk/ | 启动钩子，自动注入技能 |

### 附录 B：架构原则（按优先级）

1. **文件是接口** — 三个项目通过 `.md` + `.json` 交换数据，不跨语言调用
2. **向后兼容** — 不加新参数时行为零变化
3. **渐进采用** — 可以从裸 loop 开始，逐步加入 Superpowers 和 OpenSpec
4. **Agent 无关** — 执行引擎不绑定 Claude，支持任何 CLI 管道模式
5. **门禁不阻塞** — 质量门禁记录结果但不阻塞 pipeline，最终由用户决策

### 附录 C：版本记录

| 版本 | 日期 | 内容 |
|------|------|------|
| v0.1.0 | 2026-07-06 | loop 管线初始版本 |
| v0.2.0 | 2026-07-07 | spec-forge 融合技能：AGENT_CMD、.agentrc、质量门禁、SKILL.md |
