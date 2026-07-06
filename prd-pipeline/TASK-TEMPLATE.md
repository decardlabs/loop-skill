# Task 文件模板

每个 Task 文件都需要包含 YAML frontmatter 元数据，格式如下：

```yaml
---
id: TASK-001
issue: "ISSUE-001: 用户注册功能"
status: pending
dependencies: []
ac: "用户可注册新账号，数据写入数据库，返回 JWT token"
prompt: |
  发给 Claude Code 的完整执行指令。
  包括项目上下文、具体实现要求、约束条件。
---
```

## 字段说明

| 字段 | 必填 | 说明 |
|------|------|------|
| `id` | ✓ | Task 编号，格式 `TASK-NNN` |
| `issue` | ✓ | 所属 Issue 名称 |
| `status` | ✓ | `pending` / `running` / `done` / `failed` |
| `dependencies` | ✓ | 依赖的 Task ID 列表，如 `[TASK-001, TASK-003]` 或 `[]` |
| `ac` | ✓ | 验收标准（一句话） |
| `prompt` | ✓ | 发给 Claude Code 的完整 prompt，用 `|` 块标语法 |

## 示例

参考 `PRD-example.md` 和生成的 `tasks/TASK-NNN-*.md` 文件。

## prompt 编写最佳实践

一个好的 prompt 应该包含：

1. **上下文锚点**：项目根路径、技术栈、代码约定
   ```
   项目路径: /path/to/project
   技术栈: FastAPI + SQLAlchemy + React
   代码风格: 遵循项目现有 eslint/prettier 配置
   ```

2. **具体任务描述**：做什么，不做什么
   ```
   请实现用户注册 API:
   - POST /api/v1/auth/register
   - 接受 {phone, password, code} 三个字段
   - 验证手机号格式（11位中国大陆手机号）
   - 密码 bcrypt 加密后存入数据库
   ```

3. **验收标准**：怎么做才算完成
   ```
   验收:
   - curl 测试返回 201 + 用户信息（不含密码）
   - 数据库 user 表有对应记录
   - 重复手机号返回 409
   - pytest 通过
   ```

4. **约束条件**：
   ```
   - 不要引入新的第三方依赖
   - 不要修改现有数据库迁移
   - 添加对应的单元测试
   ```
