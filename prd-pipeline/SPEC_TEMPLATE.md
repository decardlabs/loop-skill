# 技术规格模板

> 这是 SPEC.md 的标准模板。每个合格的技术规格应包含以下全部 6 个章节，且每个章节的内容达到示例所示的完整度。
>
> `prd_to_spec.sh` 的 quality gate 以此模板为基准进行验证。

---

# 技术规格: <项目名称>

## 1. 架构概览

### 整体架构

<!-- 描述整体架构模式：前后端分离 / 单体 / 微服务 / Serverless 等 -->

前后端分离架构，前端为 SPA 应用，后端为 RESTful API 服务。

### 核心模块

| 模块 | 职责 | 技术选型 | 理由 |
|------|------|---------|------|
| 前端应用 | 用户界面与交互 | React + Vite | 组件化开发，AI 生成质量高 |
| API 服务 | 业务逻辑处理 | Go + Gin | 高性能，编译时类型安全 |
| 数据库 | 数据持久化 | PostgreSQL | 关系型数据库，AI SQL 生成质量高 |
| 缓存 | 热点数据加速 | Redis | 会话管理、缓存加速 |

### 模块依赖关系

```
用户 → 前端 SPA → API 服务 → 数据库
                    ↓
                 缓存服务
```

---

## 2. 模块设计

### 前端模块

| 模块 | 职责 | 主要组件 |
|------|------|---------|
| 页面路由 | 路由分发 | `App.tsx`, `router.tsx` |
| 页面组件 | 业务页面 | `pages/*.tsx` |
| 通用组件 | 可复用 UI | `components/*.tsx` |
| API 层 | 服务端通信 | `api/*.ts` |
| 状态管理 | 全局状态 | `store/*.ts` |

### 后端模块

| 模块 | 职责 | 主要文件 |
|------|------|---------|
| Handler | HTTP 请求处理 | `handler/*.go` |
| Service | 业务逻辑 | `service/*.go` |
| Repository | 数据访问 | `repository/*.go` |
| Model | 数据模型 | `model/*.go` |
| Middleware | 中间件 | `middleware/*.go` |

### 模块间接口

- 前端通过 HTTP JSON 调用后端 API
- 后端 Handler → Service → Repository → Model 单向依赖
- 层间通过接口定义解耦

---

## 3. 数据模型

### 核心实体

<!-- 至少定义一个实体，展示字段、类型、约束 -->

#### User（用户）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | UUID | PK, 自增 | 主键 |
| username | VARCHAR(50) | UNIQUE, NOT NULL | 用户名 |
| email | VARCHAR(100) | UNIQUE, NOT NULL | 邮箱 |
| password_hash | VARCHAR(255) | NOT NULL | bcrypt 哈希 |
| status | ENUM('active','inactive') | DEFAULT 'active' | 状态 |
| created_at | TIMESTAMP | NOT NULL | 创建时间 |
| updated_at | TIMESTAMP | NOT NULL | 更新时间 |

### 数据库设计

<!-- 至少描述一个表或集合 -->

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_users_email ON users(email);
```

### API 契约

<!-- 至少定义 3 个核心端点 -->

| 方法 | 路径 | 说明 | 请求体 | 响应 |
|------|------|------|--------|------|
| POST | /api/v1/auth/register | 用户注册 | `{username, email, password}` | `{code, message, data: {user}}` |
| POST | /api/v1/auth/login | 用户登录 | `{email, password}` | `{code, message, data: {token}}` |
| GET | /api/v1/users/me | 获取当前用户 | — | `{code, message, data: {user}}` |

---

## 4. 关键流程

### 用户注册流程

```
用户提交注册表单
    ↓
前端校验（格式、密码强度）
    ↓
POST /api/v1/auth/register
    ↓
后端校验（用户名/邮箱唯一性）
    ↓
密码 bcrypt 加密
    ↓
写入数据库
    ↓
返回用户信息（不含密码）
    ↓
前端跳转到登录页
```

### 状态机

```
用户状态:
  [注册] → active → [注销] → inactive
```

---

## 5. 非功能需求

| 维度 | 要求 | 实现方式 |
|------|------|---------|
| 性能 | API 响应 < 200ms | Redis 缓存、数据库索引 |
| 安全 | 密码 bcrypt、JWT 认证 | 认证中间件 |
| 可扩展 | 模块化设计，层间解耦 | 依赖注入 |
| 可用性 | 99.9% | 健康检查、优雅重启 |

---

## 6. 实现优先级

### MVP 范围（P0 — 必须完成）

| 优先级 | 模块 | 预估工时 | 依赖 |
|--------|------|---------|------|
| P0 | 数据库模型 + 迁移 | 1 天 | 无 |
| P0 | 用户注册/登录 API | 2 天 | 数据库模型 |
| P0 | 前端注册/登录页面 | 2 天 | API |
| P1 | 用户个人中心 | 1 天 | 登录 API |

### 后续迭代

| 迭代 | 内容 | 说明 |
|------|------|------|
| v1.1 | 密码找回 | 邮箱验证流程 |
| v1.2 | 第三方登录 | OAuth 集成 |

---

> 模板结束。`validate_spec_quality()` 以此标准检查：
> 1. 全部 6 个章节是否存在
> 2. 每个章节是否有实质性内容（>3 行）
> 3. 数据模型是否有带字段定义的表格
> 4. API 契约是否有具体端点（GET/POST/DELETE）
> 5. 是否包含占位符（TODO/TBD/待定），如有则报警
