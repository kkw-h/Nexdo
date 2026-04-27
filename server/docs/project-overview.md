# Nexdo Server Golang 项目说明

## 1. 项目简介

Nexdo Server Golang 是 Nexdo 后端 API 的 Go 实现版本，基于 `Gin + GORM + SQLite/PostgreSQL` 构建。

项目目标是对齐现有 TypeScript 后端的核心业务行为，先完成一版可运行、可测试、可持续迭代的 API 服务，覆盖用户、设备、提醒、同步、闪念和音频处理等核心能力。

当前版本重点强调：

- 接口行为稳定
- 响应结构统一
- 支持本地快速启动
- 具备较完整的接口级测试覆盖

## 2. 技术栈

- 语言：Go
- Web 框架：Gin
- ORM：GORM
- 数据库：SQLite / PostgreSQL
- 鉴权：JWT
- 密码处理：自定义密码哈希封装
- 数据迁移：SQL migration 文件顺序执行

## 3. 核心功能

### 3.1 鉴权与用户

- 用户注册
- 用户登录
- 刷新 access token
- 获取当前用户信息
- 更新昵称、头像、时区、语言
- 修改密码

### 3.2 设备管理

- 自动记录设备登录和访问信息
- 查询当前用户设备列表
- 删除设备
- 支持从请求头或 `User-Agent` 推断设备信息
- 记录并返回设备 IP 地址 `ip_address`

### 3.3 资源管理

- 清单 `lists` CRUD
- 分组 `groups` CRUD
- 标签 `tags` CRUD
- 删除清单、分组时校验是否仍被 reminder 使用

### 3.4 提醒管理

- reminder CRUD
- 完成 / 取消完成
- 完成历史查询
- 多条件筛选查询
- tag 关联与替换
- 循环截止时间 `repeat_until_at`
- 提前提醒分钟数 `remind_before_minutes`

### 3.5 循环提醒

支持以下循环规则：

- `daily`
- `weekly`
- `monthly`
- `yearly`
- `workday`
- `non_workday`

循环提醒完成后会自动生成下一条 reminder，并保留完成日志。

如果配置了 `repeat_until_at`，当下一次 `due_at` 晚于截止时间时，不再生成下一条 reminder，当前提醒直接完成。

### 3.6 同步接口

- `GET /api/v1/sync/bootstrap`
  用于客户端首次全量同步
- `GET /api/v1/sync/changes`
  用于按时间游标增量同步

增量同步支持返回：

- 新增 / 更新后的实体
- 已软删除实体的 id 列表

### 3.7 闪念与音频

- 文本闪念
- multipart 音频闪念
- 鉴权下载音频
- 闪念转 reminder
- 软删除后不可继续访问或转换

### 3.8 接口文档

- `GET /api/v1/docs` 返回 OpenAPI JSON
- `GET /api/v1/docs/ui` 返回可浏览的文档页面

## 4. 项目结构

```text
cmd/api
  main.go               # 程序入口

internal/app
  app.go                # 应用启动、路由注册、中间件
  auth_*                # 鉴权 / 用户 / 设备相关逻辑
  resource_*            # lists / groups / tags 逻辑
  reminder_*            # reminder 逻辑
  quicknote_*           # quick note 逻辑
  recurrence.go         # 循环提醒日期推进规则
  sync_helpers.go       # bootstrap / changes 同步逻辑
  openapi.go            # 文档输出
  app_test.go           # 主要接口级测试

internal/config
  config.go             # 配置加载

internal/models
  models.go             # GORM 数据模型

internal/http/response
  response.go           # 统一响应结构

internal/pkg
  jwt/                  # JWT 封装
  password/             # 密码哈希封装

migrations
  0001_init.sql         # 初始化数据库结构
  0002_sessions.sql     # sessions 表
  0003_reminder_schedule_fields.sql # reminder 循环截止/提前提醒字段

docs
  api-technical-solution-go.md
  project-overview.md
```

## 5. 设计原则

项目按“薄 handler、业务进 service、数据库读写进 repository”的思路组织：

- handler：处理请求参数、调用业务层、输出响应
- service：实现业务规则
- repository：负责数据库查询和写入

这样做的好处是：

- 结构清晰
- 便于后续拆模块
- 便于测试和回归

## 6. 响应规范

成功响应：

```json
{
  "code": 0,
  "message": "ok",
  "data": {}
}
```

失败响应：

```json
{
  "code": 40000,
  "message": "请求参数错误",
  "error": "详细原因"
}
```

项目保留中文错误语义，便于客户端直接消费。

## 7. 数据库与迁移

项目使用 SQL migration 文件管理表结构。

启动时如果开启自动迁移：

- 会按文件名顺序执行 `migrations/*.sql`
- 已执行记录会写入 `schema_migrations`

默认本地可直接使用 SQLite，生产环境可以切到 PostgreSQL。

当前迁移文件包括：

- `0001_init.sql`
- `0002_sessions.sql`
- `0003_reminder_schedule_fields.sql`

## 8. 配置说明

常用环境变量：

- `APP_ENV`
- `APP_NAME`
- `APP_ADDR`
- `DATABASE_URL`
- `JWT_ACCESS_SECRET`
- `JWT_REFRESH_SECRET`
- `JWT_ACCESS_TTL_SECONDS`
- `JWT_REFRESH_TTL_SECONDS`
- `AUDIO_STORAGE_DIR`
- `AUTO_MIGRATE`
- `MIGRATIONS_DIR`

## 9. 本地运行

启动服务：

```bash
go run ./cmd/api
```

默认地址：

```text
http://localhost:8080
```

单独执行迁移：

```bash
go run ./cmd/migrate
```

这个命令会：

- 连接 `DATABASE_URL`
- 按顺序执行未执行过的 `migrations/*.sql`
- 把已执行文件名记录到 `schema_migrations`
- 输出 applied / skipped 的 migration 信息

## 10. Docker 部署

项目已提供：

- [Dockerfile](/Users/kkw/www/kkw/Nexdo-Server-GoLang/Dockerfile)
- [docker-compose.yml](/Users/kkw/www/kkw/Nexdo-Server-GoLang/docker-compose.yml)

### 10.1 构建镜像

```bash
docker build -t nexdo-server-golang .
```

### 10.2 直接运行

```bash
docker run -d \
  --name nexdo-api \
  -p 8080:8080 \
  -e JWT_ACCESS_SECRET=change-me-access-secret \
  -e JWT_REFRESH_SECRET=change-me-refresh-secret \
  -e DATABASE_URL='postgres://nexdo:nexdo@<postgres-host>:5432/nexdo?sslmode=disable' \
  -e AUDIO_STORAGE_DIR=/app/storage/audio \
  -e MIGRATIONS_DIR=/app/migrations \
  -v nexdo_storage:/app/storage \
  nexdo-server-golang
```

### 10.3 使用 Compose

```bash
docker compose up -d --build
```

默认 compose 配置：

- 对外暴露 `8080`
- 同时启动 PostgreSQL 16
- 使用 volume 持久化 PostgreSQL 数据和音频文件
- 自动执行 migration

部署时建议至少修改：

- `JWT_ACCESS_SECRET`
- `JWT_REFRESH_SECRET`
- `POSTGRES_PASSWORD`
- 如需外置数据库，再调整 `DATABASE_URL`

## 11. 测试情况

项目当前以接口级测试为主，覆盖了以下重点场景：

- 注册 / 登录 / 刷新 token / 修改密码
- 设备记录与跨用户访问控制
- lists / groups / tags CRUD 与删除约束
- lists / groups / tags 表单字段、默认值、空白名称与跨用户 patch
- reminder CRUD、筛选、完成、取消完成
- reminder 提交表单字段的主要边界、默认值、外键归属与 `notification_enabled=false`
- reminder 的 `repeat_until_at` / `remind_before_minutes` 字段校验、默认值、清空和持久化
- 所有循环提醒规则的 rollover
- 循环提醒在 `repeat_until_at` 截止后停止 rollover
- sync bootstrap 与增量 changes
- quick note 创建、音频下载、转换、删除与异常路径
- quick note JSON 提交、空白内容、波形默认值 / 清空与状态流转
- tag 替换与删除后的 reminder 关联清理
- repository / service 层也已补充部分回归测试，用于锁定默认值、状态流转和文件清理等业务细节

运行测试：

```bash
go test ./...
```

## 12. 当前状态

当前版本已经可以作为一版完整的 API 原型服务使用，适合：

- 本地联调
- 客户端接口对接
- 后续模块化重构
- 持续补充业务细节

如果后续继续演进，建议优先考虑：

- 更细的模块拆分
- 更完整的 OpenAPI schema
- refresh/logout 令牌撤销策略
- 更完善的日志与可观测性
- 更多针对 PostgreSQL 的集成验证
