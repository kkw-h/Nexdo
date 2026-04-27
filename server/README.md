# Nexdo Server Golang

基于 `Golang + Gin + GORM` 的 Nexdo API 第一版实现，覆盖鉴权、设备、清单/分组/标签、提醒、同步、闪念和音频下载。

项目详细说明见：

- [docs/project-overview.md](docs/project-overview.md)

## 当前能力

- 鉴权：注册、登录、刷新 token、登出
- 用户：获取当前用户、更新资料、修改密码
- 设备：活跃设备记录、设备列表、删除设备
- 资源：`lists / groups / tags` CRUD
- 提醒：CRUD、完成/取消完成、完成历史、筛选查询
- 循环提醒：`daily / weekly / monthly / yearly / workday / non_workday`
- 提醒扩展：循环截止时间 `repeat_until_at`、提前提醒分钟数 `remind_before_minutes`
- 同步：`/api/v1/sync/bootstrap`、`/api/v1/sync/changes`
- 闪念：文本闪念、音频闪念、闪念转提醒、音频鉴权下载
- 文档：`/api/v1/docs`

## 环境要求

- Go `1.26.2`
- SQLite 或 PostgreSQL

说明：

- `go.mod` 和 Docker 构建环境统一使用 Go `1.26.2`
- 如使用 `docker build` 或 `docker compose`，builder 镜像会使用 `golang:1.26.2-alpine`

## 主要环境变量

- `APP_ENV`: 默认 `development`
- `APP_NAME`: 默认 `nexdo-server`
- `APP_ADDR`: 默认 `:8080`
- `DATABASE_URL`: 默认 `sqlite://file:nexdo.db?_foreign_keys=on`
- `JWT_ACCESS_SECRET`: Access Token 密钥
- `JWT_REFRESH_SECRET`: Refresh Token 密钥
- `JWT_ACCESS_TTL_SECONDS`: 默认 `3600`
- `JWT_REFRESH_TTL_SECONDS`: 默认 `2592000`
- `AUDIO_STORAGE_DIR`: 默认 `storage/audio`
- `AUTO_MIGRATE`: 默认 `true`
- `MIGRATIONS_DIR`: 默认项目根目录下的 `migrations`

说明：

- `AUTO_MIGRATE=true` 时，启动会按文件名顺序执行 `migrations/*.sql`
- 已执行的 migration 会记录到 `schema_migrations` 表
- 也可以通过 `go run ./cmd/migrate` 单独执行迁移而不启动 API
- 生产环境至少需要包含 `0001_init.sql`、`0002_sessions.sql`、`0003_reminder_schedule_fields.sql`

## 本地启动

```bash
go run ./cmd/api
```

单独执行迁移：

```bash
go run ./cmd/migrate
```

服务默认地址：

```text
http://localhost:8080
```

## 测试

```bash
go test ./...
```

## Docker 部署

构建镜像：

```bash
docker build -t nexdo-server-golang .
```

直接运行：

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

使用 `docker compose`：

```bash
docker compose up -d --build
```

说明：

- 默认 compose 会同时启动 PostgreSQL 16
- PostgreSQL 数据持久化在 `postgres_data` volume
- 启动时会自动执行 `migrations/*.sql`
- 部署前请务必修改 `JWT_ACCESS_SECRET` 和 `JWT_REFRESH_SECRET`
- 如需外部 PostgreSQL，只需要改 `DATABASE_URL`
- 容器内 migration 路径固定为 `/app/migrations`

## 关键接口

- `GET /api/v1/health`
- `GET /api/v1/docs`
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`
- `GET /api/v1/me`
- `PATCH /api/v1/me`
- `PATCH /api/v1/me/password`
- `GET /api/v1/me/devices`
- `DELETE /api/v1/me/devices/:id`
- `GET/POST/PATCH/DELETE /api/v1/lists`
- `GET/POST/PATCH/DELETE /api/v1/groups`
- `GET/POST/PATCH/DELETE /api/v1/tags`
- `GET/POST /api/v1/reminders`
- `GET/PATCH/DELETE /api/v1/reminders/:id`
- `POST /api/v1/reminders/:id/complete`
- `POST /api/v1/reminders/:id/uncomplete`
- `GET /api/v1/reminders/:id/completion-logs`
- `GET /api/v1/sync/bootstrap`
- `GET /api/v1/sync/changes?since=RFC3339`
- `GET/POST /api/v1/quick-notes`
- `PATCH/DELETE /api/v1/quick-notes/:id`
- `GET /api/v1/quick-notes/:id/audio`
- `POST /api/v1/quick-notes/:id/convert`

## 说明

- 所有受保护接口都要求 `Authorization: Bearer <token>`
- 所有时间字段使用 RFC3339 / RFC3339Nano
- reminder 支持 `repeat_until_at` 和 `remind_before_minutes`
- `repeat_until_at` 为空时循环照常 rollover；下一次 `due_at` 晚于 `repeat_until_at` 时，不再生成下一条 reminder，当前提醒直接完成
- `remind_before_minutes` 为非负整数，默认 `0`，目前用于数据存储和接口返回
- 设备识别使用以下请求头：
  - `X-Nexdo-Device-ID`
  - `X-Nexdo-Device-Name`
  - `X-Nexdo-Device-Platform`
  - `User-Agent`
- `/me/devices` 返回设备 IP：`ip_address`
