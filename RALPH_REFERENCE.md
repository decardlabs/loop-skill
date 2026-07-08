# Ralph 项目参考分析

> Ralph 是 Geoffrey Huntley 提出的"自主 AI 编码循环"模式，
> 和 loop 属于同一类问题——让 AI 在循环中自主完成编码任务。
> 以下是 Ralph 生态对 loop 的参考价值。

---

## 一、Ralph 生态全景

Ralph 不是一个项目，而是一个**模式**——有十几个独立实现，各自侧重不同：

| 实现 | 语言 | 特点 |
|------|------|------|
| **ralph-loop** (PageAI-Pro) | Python | Docker 沙箱、任务队列、最接近 loop 的原始设计 |
| **ralph-wiggum** (harrymunro) | Shell | Claude Code 专用，终端交互 |
| **ralph-wiggum** (fstandhartinger) | Shell | + SpecKit 规格驱动 |
| **ralph-ai-coding-loop** (OctavianTocan) | Shell | 5 次重试、结构化学习、零配置 |
| **ralph-claude-code** (frankbria) | TypeScript | **最完善**：784 测试、限流、熔断、Docker/E2B 沙箱 |
| **ralph-code** (daegwang) | Node.js CLI | 可混用 Agent（Claude 规划 + Codex 执行） |
| **ralph-zero** (jasontang-ai) | Skills/SKILL.md | Agent Skills 编排器，支持 Claude/Cursor/Copilot |
| **ralph-tui** (subsy) | Bun/TypeScript | 终端 UI，多 Agent 远程监控 |
| **pi-smart-ralph** | npm 包 | Pi 专属，子代理 + Epics + GitHub 同步 |

### 核心循环

所有实现共享同一个核心模式：

```
1. 读取任务列表（prd.json / tasks.md）
2. 选取下一个未完成任务
3. 启动新的 AI Agent 实例（全新上下文）
4. Agent 实现 → 验证（测试/lint/类型检查）
5. 通过 → commit，更新进度，记录经验
6. 循环，直到全部完成
```

**这和 loop 的 task_executor.sh 完全一致。** 说明这个模式已经过大量实践验证。

---

## 二、可以直接借鉴的能力

### 1. 限流与熔断（rate limiting + circuit breaker）

来自 `ralph-claude-code`（TypeScript，784 测试的最完善实现）：

```
当前 loop: 重试 3 次 → 失败 → 标记 failed

Ralph 的做法:
  - 限流: 检测 API 429 错误 → 自动退避等待
  - 熔断: 连续 N 次失败 → 停止该 task → 报告给用户
  - 智能退出: 检测"AI 在原地说车轱辘话"模式 → 及时终止
```

**对我们项目的意义：** 当前 loop 只检查退出码。如果 AI 输出的是"我不确定怎么实现"而不是代码，退出码仍然可能是 0。需要检测输出内容的有效性。

**建议改动：** `task_executor.sh` 的 `execute_task()` 在执行成功后，检查输出日志是否包含实质性的代码变更，而非空响应或拒绝回答。

```bash
# 检测 AI 是否真正产生了代码
if [ "$rc" -eq 0 ]; then
    # 新增: 输出有效性检查
    if ! grep -qE '(CREATE|function|class|def|impl)' "$log_file" 2>/dev/null; then
        warn "AI 输出可能不包含有效代码实现"
        # 视同失败，触发重试
        rc=1
    fi
fi
```

### 2. 结构化经验记录（learnings）

来自 `ralph-ai-coding-loop`：

```
当前 loop: 失败 → 重试 3 次 → 放弃

Ralph 的做法:
  每次失败后记录 learnings.md:
  - 这个 task 为什么失败？
  - 下次应该注意什么？
  - 有哪些文件不能碰？
```

**对我们项目的意义：** 重试时，当前的 prompt 只加了"请换一种方式"。如果能注入前次失败的原因，AI 更有可能成功。

**建议改动：** 在 `quality_gate.txt` 中记录失败原因摘要，重试时注入 prompt：

```bash
# 重试 prompt 增加失败上下文
if [ -f "$task_log_dir/quality_gate.txt" ]; then
    local _fail_reason="$(cat "$task_log_dir/quality_gate.txt" | head -c 200)"
    actual_prompt="${actual_prompt}

注意：之前的尝试失败于：${_fail_reason}
请避免同样的错误。"
fi
```

### 3. 多 Agent 混用（Claude 规划 + Codex 执行）

来自 `ralph-code`（Node.js CLI）：

```
当前 loop: 所有步骤用同一个 AGENT_CMD

Ralph 的做法:
  规划阶段 → Claude（推理强，适合设计）
  执行阶段 → Codex（速度快，成本低）
  审查阶段 → Claude（判断力好）
```

**对我们项目的意义：** `AGENT_CMD` 已经是抽象层，但每个阶段用同一个 Agent。可以在 `lib.sh` 中增加分阶段配置：

```bash
AGENT_CMD_PLAN="${AGENT_CMD_PLAN:-$AGENT_CMD}"
AGENT_CMD_EXEC="${AGENT_CMD_EXEC:-$AGENT_CMD}"
AGENT_CMD_REVIEW="${AGENT_CMD_REVIEW:-$AGENT_CMD}"
```

用户可以在 `.agentrc` 中配置：

```bash
AGENT_CMD_PLAN="claude -p ..."      # 规划用 Claude
AGENT_CMD_EXEC="codex -p"           # 执行用 Codex（便宜）
AGENT_CMD_REVIEW="claude -p ..."    # 审查用 Claude
```

### 4. 沙箱执行（Docker / E2B）

来自 `ralph-loop` 和 `ralph-claude-code`：

```
当前 loop: AI 在目标目录直接写文件

Ralph 的做法:
  Docker 沙箱 → AI 在容器里写代码 → 验证通过 → 复制出来
  好处: AI 不会意外修改系统文件、不会泄漏 token
```

**对我们项目的意义：** 不是所有用户都需要沙箱，但对于 CI/CD 环境或团队共享服务器，沙箱可以防止 AI 误操作。

**建议改动：** 可选功能，增加 `--sandbox docker` 参数。当指定时，AI 在隔离环境中执行。

### 5. 终端 UI 远程监控

来自 `ralph-tui`（Bun/TypeScript）：

```
当前 loop: 执行完成后看 summary.md

Ralph TUI 的做法:
  实时终端仪表盘:
  ├─ 当前执行进度 60%
  ├─ 最近完成的 task
  ├─ 失败的 task + 原因
  └─ 预计剩余时间
```

**对我们项目的意义：** loop 已有 `progress.sh`，但它是静态的（需要手动刷新）。可以增加 `--watch` 模式，让 progress.sh 持续刷新。

### 6. 输出有效性检测

来自多个 Ralph 实现：

```
当前 loop: 检查退出码（0=成功，非0=失败）

Ralph 的做法:
  - 检查输出是否包含有效代码
  - 检查是否创建/修改了文件
  - 检查是否引用了存在的文件路径
```

**这是我们最直接的差距。** 当前 loop 把"AI 成功退出"等同于"task 成功完成"，但 AI 可能：
- 输出"I don't know how to do this"然后退出码 0
- 写了空文件
- 写的代码引用了不存在的依赖

---

## 三、差距对比

| 能力 | Ralph 生态 | loop | 差距 |
|------|-----------|------|------|
| 核心循环 | ✅ | ✅ | 一致 |
| 重试机制 | ✅ 含 learnings 注入 | ✅ 重试但无注入 | 小差距 |
| Git 集成 | ✅ | ✅ | 一致 |
| 质量门禁 | ✅ 测试/lint/类型 | ✅ 同上 | 一致 |
| 限流熔断 | ✅ ralph-claude-code | ❌ | 🔴 可加 |
| 输出有效性 | ✅ 多个实现 | ❌ | 🔴 可加 |
| 多 Agent 混用 | ✅ ralph-code | ⚠️ AGENT_CMD | 🟡 可扩展 |
| 结构化经验 | ✅ learnings.md | ❌ | 🟡 可加 |
| 沙箱执行 | ✅ Docker/E2B | ❌ | 🟢 可选 |
| 终端 UI | ✅ ralph-tui | ⚠️ progress.sh | 🟢 可选 |
| 安装方式 | npm / bun | git clone | 一致 |
| 语言 | TypeScript/Shell/Python | Bash | loop 更轻量 |
| 规范集成 | SpecKit/OpenSpec | OpenSpec | 一致 |
| 流程管控 | ralph-zero (Skills) | Superpowers | 一致 |

---

## 四、建议行动项

### 立即可以做的（低投入，高收益）

```text
1. 输出有效性检测
   在 execute_task() 成功后检查输出是否包含有效代码
   改动: task_executor.sh +10 行
   收益: 避免"AI 说不知道"但退出码 0 的误报

2. 失败原因注入重试
   重试时将前次失败摘要追加到 prompt
   改动: task_executor.sh +5 行
   收益: 重试成功率提升
```

### 短期可以做的（中等投入）

```text
3. 分阶段 AGENT_CMD
   允许规划/执行/审查用不同的 Agent
   改动: lib.sh +10 行 + .agentrc 扩展
   收益: Claude 规划 + Codex 执行，成本最优

4. progress.sh --watch 模式
   持续刷新进度显示
   改动: progress.sh +30 行
   收益: 实时看到执行进展
```

### 长期考虑的

```text
5. Docker 沙箱（--sandbox docker）
6. learnings.md 结构化经验积累
```

---

## 五、最值得立即做的改动

### 输出有效性检测

```bash
# task_executor.sh execute_task() 成功后增加
if [ "$rc" -eq 0 ]; then
    # 检测输出是否包含实质性的代码变更
    local code_keywords="function|class|def|impl|interface|const|let|import|export|package|module|fn|pub|struct|enum|trait"
    if ! grep -qiE "$code_keywords" "$log_file" 2>/dev/null && \
       ! grep -qiE '(created|modified|added|updated).*(file|test)' "$log_file" 2>/dev/null; then
        warn "  ${id}: ⚠️ 输出中未检测到有效代码，可能 AI 未能真正实现"
        # 可选: 将退出码设为非0，触发重试
        # rc=1
        # 继续执行（仅警告），但将结果记入 quality_gate
    fi
fi
```

### 分阶段 AGENT_CMD

```bash
# lib.sh 增加
AGENT_CMD_PLAN="${AGENT_CMD_PLAN:-$AGENT_CMD}"
AGENT_CMD_EXEC="${AGENT_CMD_EXEC:-$AGENT_CMD}"
AGENT_CMD_REVIEW="${AGENT_CMD_REVIEW:-$AGENT_CMD}"
```

```bash
# .agentrc.example 增加
# 分阶段 Agent 配置（可选，默认全部使用 AGENT_CMD）
# AGENT_CMD_PLAN="claude -p ..."     # 设计/规划阶段
# AGENT_CMD_EXEC="codex -p"          # 编码执行阶段
# AGENT_CMD_REVIEW="claude -p ..."   # 代码审查阶段
```
