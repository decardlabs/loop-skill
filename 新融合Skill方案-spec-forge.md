# 融合 Skill 方案：`spec-forge`

> 从规约到代码的自动化锻造炉

---

## 一、命名

**名称：** `spec-forge`

**含义：** Spec（规范）→ Forge（锻造）—— 将 OpenSpec 的结构化规格放入自动化管道中锻造，产出经过质量门禁验证的代码。

**斜杠命令：** `/forge`

**作为 Superpowers skill 注册名：** `spec-forge`

---

## 二、解决的问题

审查发现的 **两大缺口** 是 `spec-forge` 的核心设计目标：

| 审查缺口 | spec-forge 的应对 |
|---------|-----------------|
| 🔴 质量门禁丧失 — loop 全自动执行绕过 TDD/Review/Verification | ✅ 执行后自动触发 review + 测试运行 + 验证门禁 |
| 🟡 delta spec 写回缺失 — 只写 status 不写 delta 导致 archive 断裂 | ✅ 执行完成后生成 delta spec 并触发 archive |

---

## 三、架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                        spec-forge Skill                              │
│                                                                     │
│  用户: /forge "添加用户注册功能"                                      │
│         │                                                           │
│         ▼                                                           │
│  ┌──────────────────────────────────────────┐                      │
│  │  Phase 1: SPEC 阶段                      │                      │
│  │  ┌────────────────────┐  ┌─────────────┐ │                      │
│  │  │ OpenSpec propose   │→│ specs/ +     │ │                      │
│  │  │ (或已有 PRD.md)    │ │ design.md    │ │                      │
│  │  └────────────────────┘ └─────────────┘ │                      │
│  ├──────────────────────────────────────────┤                      │
│  │  Phase 2: PLAN 阶段                      │                      │
│  │  ┌────────────────────┐  ┌─────────────┐ │                      │
│  │  │ loop 拆解          │→│ TASK-NNN.md  │ │  ← OpenSpec 有       │
│  │  │ (或读取已有 tasks) │ │ task_board   │ │     tasks.md 可跳过   │
│  │  └────────────────────┘ └─────────────┘ │                      │
│  ├──────────────────────────────────────────┤                      │
│  │  Phase 3: FORGE 阶段（核心）              │                      │
│  │  ┌────────────────────────────────────┐ │                      │
│  │  │ task_executor.sh (AGENT_CMD 驱动)  │ │                      │
│  │  │        │                          │ │                      │
│  │  │        ▼                          │ │                      │
│  │  │  ┌──────────┐  ┌──────────────┐   │ │                      │
│  │  │  │ 每个 task │→│ 质量门禁检查   │   │ │  ← 审查缺口 #1 的修复  │
│  │  │  │ 执行成功  │  │ auto-run tests│   │ │                      │
│  │  │  │          │  │ code review   │   │ │                      │
│  │  │  └──────────┘  │ AC 验证       │   │ │                      │
│  │  │                └──────┬───────┘   │ │                      │
│  │  │                       │ 通过?     │ │                      │
│  │  │                  ┌────┴────┐      │ │                      │
│  │  │                  │ ✅ 继续  │ ❌    │ │                      │
│  │  │                  │ 下一个   │ 提醒 │ │                      │
│  │  │                  └─────────┘      │ │                      │
│  │  └────────────────────────────────────┘ │                      │
│  ├──────────────────────────────────────────┤                      │
│  │  Phase 4: CLOSE 阶段                     │                      │
│  │  ┌────────────────────┐  ┌─────────────┐ │                      │
│  │  │ delta spec 写回     │→│ OpenSpec    │ │  ← 审查缺口 #2 的修复  │
│  │  │ status.md 生成      │ │ archive 触发│ │                      │
│  │  └────────────────────┘ └─────────────┘ │                      │
│  ├──────────────────────────────────────────┤                      │
│  │  Phase 5: FINISH 阶段                    │                      │
│  │  ┌────────────────────────────────────┐ │                      │
│  │  │ git merge / PR / keep / discard    │ │                      │
│  │  └────────────────────────────────────┘ │                      │
│  └──────────────────────────────────────────┘                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 四、五个阶段详解

### Phase 1: SPEC 阶段 — 定义"做什么"

**输入：** 用户需求描述 或 PRD.md

**步骤：**

```
1. 检查项目是否已初始化 OpenSpec:
   ls openspec/config.yaml 存在?
   ├─ 是 → 使用已有的 openspec 目录
   └─ 否 → 提示用户: openspec init
            （不自动安装，尊重用户选择）

2. 检查是否有 PRD.md:
   ├─ 有 → 作为输入
   └─ 无 → 用 OpenSpec propose 生成 specs

3. 输出:
   openspec/specs/<domain>/spec.md  ← Given/When/Then
   openspec/changes/<name>/design.md ← 架构设计
   openspec/changes/<name>/tasks.md  ← 任务清单（可选）
```

**Agent 要求：** OpenSpec CLI 或 AI 辅助写 specs。如果用户有 Claude Code，可以让 AI 帮助生成 specs。

**质量门禁：** ✅ 此阶段保持 Superpowers 的 brainstorming + writing-plans 门禁。

---

### Phase 2: PLAN 阶段 — 定义"怎么做"

**输入：** OpenSpec specs/ + tasks.md（如果有）

**步骤：**

```
1. 检查是否有 tasks.md:
   ├─ 有 → 直接转换为 loop 的 TASK-NNN.md 文件
   │     ./issue_to_tasks.sh openspec/specs/ openspec/changes/<name>/tasks.md --direct
   │     ← 零 Agent 调用，纯文件转换
   │
   └─ 无 → 调用 issue_to_tasks.sh 拆解:
           ./issue_to_tasks.sh openspec/specs/ ... --spec-dir
           ← 调 Agent 1 次做拆解

2. 输出:
   prd-pipeline/projects/<name>/03-tasks/TASK-001-*.md
   prd-pipeline/projects/<name>/03-tasks/task_board.md
   prd-pipeline/projects/<name>/04-execution/run-manifest.json
```

**Agent 要求：** 拆解步骤需要 Agent 理解 specs 并规划 task。如果不设 AGENT_CMD 则用 Claude，其他 Agent 也可以。

**质量门禁：** ✅ loop 的拓扑排序确保依赖顺序正确。

---

### Phase 3: FORGE 阶段（核心）— 执行 + 质量门禁

**输入：** TASK-NNN.md 文件

**关键设计：** 这是审查发现的"质量门禁丧失"缺口的修复位置。每个 task 执行完后**不立即返回**，而是经过三道质量检查：

```
task_executor.sh 启动:
  ├─ init_git_branch() → 创建隔离分支
  │
  ├─ 对每个 task（按拓扑序）:
  │    ├─ 步骤 3.1: 执行
  │    │    echo "prompt" | $AGENT_CMD
  │    │
  │    ├─ 步骤 3.2: AC 验证（已有 --verify-ac）
  │    │    └─ 失败 → 不阻塞，记入报告
  │    │
  │    ├─ 步骤 3.3: 自动运行测试（NEW）
  │    │    if TARGET_DIR 有测试框架:
  │    │      detect: pytest / npm test / cargo test / go test
  │    │      run: cd $TARGET_DIR && <test_command>
  │    │      record: 测试通过数 / 失败数
  │    │      gate: 测试全通过 = ✅，有失败 = ⚠️ 记入报告
  │    │
  │    ├─ 步骤 3.4: 代码审查（NEW — 调用 Superpowers 的 review 流程）
  │    │    if 当前 Agent 支持:
  │    │      generate git diff
  │    │      invoke requesting-code-review (SKILL.md 已有的能力)
  │    │      record: Critical/Important/Minor 问题数
  │    │      gate: 有 Critical = ❌ 记入报告
  │    │
  │    ├─ 步骤 3.5: git commit（只有通过所有门禁才 commit）
  │    │    git add -A && git commit -m "TASK-NNN: ..."
  │    │
  │    └─ 失败（达 3 次）:
  │         git checkout . && git clean -fd
  │         记入失败报告
  │
  └─ 所有 task 完成后:
       generate_summary() → summary.json + summary.md
```

**新加的质量门禁（审查后的改进）：**

| 门禁 | 当前 loop | spec-forge 新增 | 通过条件 |
|------|----------|----------------|---------|
| AC 验证 | `--verify-ac` 可选 | 同左，改为默认启用 | Claude 返回 PASS |
| 自动测试 | ❌ 无 | ✅ `detect_tests_and_run()` | 测试全部通过 |
| Code Review | ❌ 无 | ✅ `invoke_review()` | 无 Critical 问题 |

**质量门禁的失败处理：**

```
门禁失败后不阻塞 pipeline，而是:
  ├─ 记入 summary.json 的 task.gateResults 字段
  ├─ 在 summary.md 中高亮显示
  └─ 在 Phase 5 的 FINISH 阶段提醒用户
```

**Agent 要求：** 执行层只要求 CLI 管道模式（`AGENT_CMD`）。质量门禁层对 Agent 的测试运行能力有要求（bash 执行），不依赖特定 AI。

---

### Phase 4: CLOSE 阶段 — 写回 OpenSpec

**输入：** summary.json（每个 task 的执行结果）

**审查缺口 #2 的修复：** 生成 delta spec 并触发 archive。

```
1. 读取 summary.json → 获取每个 task 的状态和变更

2. 生成 delta spec（NEW — 新增功能）:
   openspec/changes/<name>/specs/<domain>/spec.md:
     ## ADDED Requirements
     --- （从 task 的 ac 字段提取）
     ## MODIFIED Requirements
     --- （从 git diff 推断）
     ## REMOVED Requirements
     --- （从 git diff 推断）

3. 更新 status.md（已有方向 C）:
   | Task | Status | Commit | AC | Tests | Review |
   |------|--------|--------|----|-------|--------|

4. 触发 archive（NEW — 新增功能）:
   if 全部 task 成功 && 用户确认:
     openspec archive <change-name>
     → delta 合并到主 specs
     → change 移入 archive 目录
   else:
     提示用户: 有未通过的 task，暂不 archive
```

**Agent 要求：** delta spec 推断需要理解 git diff 的含义。可以用 `AGENT_CMD` 发一次 prompt 做推断，也可以由 shell 脚本做简单映射（文件名→domain）。

---

### Phase 5: FINISH 阶段 — 交付

**输入：** summary.md + git 分支状态

**复用 Superpowers 已有的 `finishing-a-development-branch` skill：**

```
1. 确认所有测试通过
   ├─ ✅ 通过 → 继续
   └─ ❌ 有失败 → 展示给用户，不阻塞

2. 展示变更摘要:
   ├─ 执行的 task 数量 / 成功 / 失败
   ├─ 提交历史: git log auto/task-run-<ts> --oneline
   ├─ 变更文件: git diff main...auto/task-run-<ts> --stat
   └─ 质量报告: AC 通过率 / 测试通过率 / Review 问题数

3. 提供选项:
   ├─ merge: 合并到 main（全部通过时推荐）
   ├─ PR: 创建 Pull Request（团队协作时）
   ├─ keep: 保留分支
   └─ discard: 丢弃变更（需确认）

4. 清理:
   ├─ 删除临时分支（merge/discard 后）
   └─ 保留 .spec/ 和 04-execution/ 目录（追溯用）
```

**Agent 要求：** 此阶段全部为 shell 命令 + git 操作，不需要调 AI。

---

## 五、Agent 适配

### 分层适配

| 阶段 | 调 Agent? | 要求 | 不适配后果 |
|------|----------|------|-----------|
| SPEC | 可选（AI 辅助写 specs） | 理解需求 | 用户手动写 PRD.md |
| PLAN | 需要（拆解 task） | 理解 specs → 规划 | 用 --direct 模式直接转换 tasks.md |
| **FORGE 执行** | **需要（核心）** | **CLI 管道模式** | **无法执行** |
| FORGE 测试 | 不需要 | bash 执行 | — |
| FORGE Review | 需要 | 理解代码变更 | 跳过 review（不阻塞） |
| CLOSE | 执行后可选（推断 delta） | 理解 git diff | 只写 status，不写 delta |
| FINISH | 不需要 | git 操作 | — |

### AGENT_CMD 兼容性

| Agent | SPEC | PLAN | FORGE | FORGE Review | 综合 |
|-------|------|------|-------|-------------|------|
| Claude Code | ✅ | ✅ | ✅ | ✅ | **A+ 完整** |
| Codex CLI | ✅ | ⚠️ | ✅ | ⚠️ | **B 部分** |
| Copilot CLI | ✅ | ⚠️ | ⚠️ | ⚠️ | **B 部分** |
| Gemini CLI | ✅ | ⚠️ | ✅ | ❌ | **C 基本** |
| OpenCode | ✅ | ⚠️ | ✅ | ❌ | **C 基本** |
| Cursor CLI | ✅ | ⚠️ | ❌ | ❌ | **D 不可用** |

### 优化建议：退化模式

如果当前 Agent 不支持某些阶段（如 Codex 不支持 review），`spec-forge` 应自动退化：

```
AGENT_TYPE=codex → 自动跳过 FORGE Review（不退化为 error）
                 → summary.md 标注: "当前 Agent 不支持自动审查"
                 → 建议用户手动 review
```

退化策略：

| 缺失能力 | 退化行为 | 影响 |
|---------|---------|------|
| 无 review 能力 | 跳过 review 阶段 | 需要用户人工审查 |
| 无测试框架 | 跳过自动测试 | 需要用户自行验证 |
| 无无确认执行 | 提示用户手动确认每次操作 | 影响自动化程度 |
| 无 Agent CLI | 无法执行 | ❌ 阻塞 |

---

## 六、用户视角

### 全流程体验（Claude Code）

```
$ /forge "添加用户注册功能"

  ╔═══════════════════════════════════╗
  ║    spec-forge v0.1                ║
  ║    从规约到代码的自动化锻造炉       ║
  ╚═══════════════════════════════════╝

  [1/5] SPEC 阶段 — 正在理解需求...
    → OpenSpec: 生成 proposal、specs、design
    → 生成 3 个场景: 注册/登录/密码重置

  [2/5] PLAN 阶段 — 拆解任务...
    → 生成 4 个 task:
      TASK-001: 用户注册 API 端点
      TASK-002: 登录 API + JWT
      TASK-003: 前端注册页面
      TASK-004: 前端登录页面

  [3/5] FORGE 阶段 — 锻造代码...
    → TASK-001: 用户注册 API ✅
      ├─ AC 验证: ✅ 通过
      ├─ 测试:    ✅ pytest 3/3 通过
      └─ Review:  ✅ 无问题
    → TASK-002: 登录 API + JWT ✅
      ├─ AC 验证: ✅ 通过
      ├─ 测试:    ✅ pytest 5/5 通过
      └─ Review:  ✅ 无问题
    → ...

  [4/5] CLOSE 阶段 — 写回规约...
    → status.md: 已更新
    → delta spec: 已生成（2 个 ADDED，1 个 MODIFIED）
    → OpenSpec archive: 准备就绪

  [5/5] FINISH 阶段 — 交付...
    → 分支: auto/task-run-20260707-143000
    → 全部 4/4 task 成功 ✅
    → 测试覆盖率: 92%
    → 建议: git merge auto/task-run-20260707-143000

  合并到 main? [Y/n]
```

### 最小体验（无 OpenSpec，仅 loop）

```
$ /forge "添加用户注册功能"

  [1/5] SPEC 阶段 — 未检测到 OpenSpec
    → 使用自由格式 PRD.md（已有）或用户描述
    → 如果有 PRD.md 则直接进入下一阶段

  [2/5] PLAN 阶段 — 拆解任务...
    → prd_to_spec.sh → spec_to_issues.sh → issue_to_tasks.sh
    → 生成 4 个 task

  [3/5] FORGE 阶段 — 循环执行...
    → 同全流程
```

### 最大体验（三项目齐备 + Claude Code）

```
$ /forge "添加用户注册功能"

  → OpenSpec: /opsx:propose 自动触发
  → Superpowers: brainstorming + writing-plans 自动注入
  → loop: task_executor 自动执行
  → Superpowers: requesting-code-review 自动触发
  → OpenSpec: archive 自动触发
  → Superpowers: finishing-a-development-branch 自动提供选项
```

---

## 七、实施路径

### 即日可做：Skill 定义文件

创建 `superpowers/skills/spec-forge/SKILL.md`，包含五阶段流程的文本指令。让 Agent 理解并执行这套流程。不需要修改任何代码。

### Phase 1 需改 loop

| 改动 | 文件 | 描述 |
|------|------|------|
| `AGENT_CMD` 抽象 | `task_executor.sh` 等 3 个文件 | `eval "$AGENT_CMD"` |
| 质量门禁：自动测试 | `task_executor.sh` 新增 `run_tests()` | 检测测试框架并运行 |
| 质量门禁：Review 挂钩 | `task_executor.sh` 新增 `invoke_review()` | 调用 Superpowers review |
| delta spec 生成 | `task_executor.sh` 新增 `generate_delta_spec()` | 从 git diff 推断 delta |
| archive 触发 | `generate_summary()` 扩展 | 全部成功时提示 archive |
| `.agentrc` 配置文件 | 新增 | 统一管理 Agent 配置 |

### Phase 2 需改 OpenSpec

不需要改 OpenSpec 代码。loop 通过文件 I/O 与 OpenSpec 交互：
- 读 `openspec/specs/` — 文件系统操作
- 写 `openspec/changes/<name>/status.md` — 文件系统操作
- 写 `openspec/changes/<name>/specs/<domain>/spec.md` (delta) — 文件系统操作
- 调 `openspec archive` — CLI 调用（可选）

### Phase 3 需改 Superpowers

不需要改 Superpowers 核心。在 `skills/spec-forge/SKILL.md` 中引用已有的 skill：

```markdown
## Phase 3 执行后

执行 `task_executor.sh` 后，自动进入 review：

1. 检查是否需要 review:
   - 是否存在 summary.md？
   - 是否有 git commits？

2. 如果满足条件，调用 requesting-code-review:
   - 提供 base SHA 和 head SHA
   - SKILL.md 中引用 superpowers 的 review 流程

3. 自动进入 finishing-a-development-branch:
   - 读取 summary.md 的执行结果
   - 提供合并选项
```

---

## 八、命名备选

| 名称 | 理由 | 问题 |
|------|------|------|
| **`spec-forge`** ✅ 首选 | 准确描述"从规约锻造代码"，动词感强 | 无 |
| `spec-pipe` | 强调 pipeline 属性 | 名词，缺少"锻造"的转化感 |
| `spec-loop` | 直白，两个项目的组合 | 缺少 OpenSpec 和 Superpowers 的参与感 |
| `forge` | 简洁 | 太普通，搜索不方便 |
| `spec-driver` | 强调驱动 | 不够形象 |
| `spec-automata` | 强调自动化 | 太长 |
