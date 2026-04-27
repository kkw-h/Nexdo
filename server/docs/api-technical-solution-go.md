# Nexdo Golang API 实现说明（Codex 专用）

> 目标：让 Codex 基于当前 TypeScript Workers 版本，快速生成一版可运行的 Go 后端 API。
> 这份文档不是历史介绍，而是“可直接执行的开发输入”。

---

## 1. 项目目标

用 `Golang + Gin + PostgreSQL + GORM` 实现一版 Nexdo 后端，业务行为尽量对齐当前线上 TypeScript 版本。

第一版优先实现：

- 鉴权：注册、登录、刷新 token、获取当前用户、修改资料、修改密码
- 设备：记录设备、查询设备、删除设备
- 资源：清单 / 分组 / 标签 CRUD
- 提醒：提醒 CRUD、完成 / 取消完成、完成历史、筛选查询
- 同步：`/sync/bootstrap`、`/sync/changes`
- 闪念：文本闪念、带音频闪念、闪念转提醒
- API 文档：OpenAPI / Swagger

不优先实现：

- 推送通知真实下发
- 分布式任务调度
- 多人协作

---

## 2. 当前 TypeScript 版本的真实来源

Go 版本必须以当前仓库实现为准，而不是旧设计稿。

主要对照文件：

- 路由入口：`/Users/kkw/www/kkw/Nexdo-Server/src/index.ts`
- 核心数据逻辑：`/Users/kkw/www/kkw/Nexdo-Server/src/lib/db.ts`
- 参数校验：`/Users/kkw/www/kkw/Nexdo-Server/src/lib/validation.ts`
- 类型定义：`/Users/kkw/www/kkw/Nexdo-Server/src/types.ts`
- 数据库结构：`/Users/kkw/www/kkw/Nexdo-Server/migrations/0001_init.sql`
- 增量迁移：`/Users/kkw/www/kkw/Nexdo-Server/migrations/0002_add_devices_table.sql` 到 `0005_add_reminder_completion_logs.sql`

如果 Go 实现与这些文件冲突，以这些文件的现行为准。

---

## 3. 推荐 Go 技术栈

- Go: `1.26+`
- HTTP: `gin-gonic/gin`
- ORM: `gorm.io/gorm`
- DB: `PostgreSQL`
- 配置: `env + cleanenv` 或 `viper`
- JWT: `github.com/golang-jwt/jwt/v5`
- 密码哈希: `golang.org/x/crypto/pbkdf2`
- 日志: `zap`
- 迁移: `golang-migrate`
- 文档: `swaggo/swag + gin-swagger`
- 对象存储: 先抽象接口，兼容本地文件 / S3 / R2

---

## 4. 推荐目录结构

```text
cmd/api/main.go
internal/app/bootstrap.go
internal/config/config.go
internal/http/
  middleware/
  response/
  handlers/
internal/modules/
  auth/
  user/
  device/
  list/
  group/
  tag/
  reminder/
  quicknote/
  sync/
internal/models/
internal/repository/
internal/service/
internal/pkg/
  jwt/
  password/
  clock/
  storage/
docs/
migrations/
```

要求：

- handler 只做参数解析、调用 service、返回统一响应
- service 写业务规则
- repository 只管数据库读写

---

## 5. 统一响应格式

成功：

```json
{
  "code": 0,
  "message": "ok",
  "data": {}
}
```

失败：

```json
{
  "code": 40000,
  "message": "请求参数错误",
  "error": "详细原因"
}
```

必须保留中文错误语义，常见 code：

- `40000` 请求参数错误
- `40001` / `40002` RFC3339 时间参数错误
- `40100` 未授权
- `40101` 旧密码不正确
- `40900` 邮箱已被注册
- `40901` 清单仍被使用
- `40902` 分组仍被使用
- `50000` 服务器内部错误

---

## 6. 核心数据模型

### 6.1 users

- id
- email
- password_hash
- nickname
- avatar_url
- timezone
- locale
- created_at
- updated_at

### 6.2 devices

- id
- user_id
- device_id
- device_name
- platform
- user_agent
- ip_address
- last_seen_at
- created_at
- updated_at

### 6.3 lists / groups / tags

与现有 SQL 一致实现。

### 6.4 reminders

- id
- user_id
- title
- note
- due_at
- repeat_until_at
- remind_before_minutes
- is_completed
- list_id
- group_id
- notification_enabled
- repeat_rule
- created_at
- updated_at
- deleted_at

### 6.5 reminder_tags

- reminder_id
- tag_id

### 6.6 reminder_completion_logs

- id
- reminder_id
- user_id
- completed_at
- original_due_at
- next_due_at
- created_at

### 6.7 quick_notes

- id
- user_id
- content
- status
- converted_reminder_id
- audio_key
- audio_filename
- audio_mime_type
- audio_size_bytes
- audio_duration_ms
- waveform_samples
- created_at
- updated_at
- deleted_at

---

## 7. 提醒循环规则（这是实现重点）

支持：

- `none`
- `daily`
- `weekly`
- `monthly`
- `yearly`
- `workday`
- `non_workday`

### 7.1 nextDate 规则

按当前 TS 逻辑实现：

- daily：`+1 day`
- weekly：`+7 days`
- monthly：`UTC month +1`
- yearly：`UTC year +1`
- workday / non_workday：按中国节假日日历推进

中国节假日规则请直接迁移 TS 文件逻辑：

- `/Users/kkw/www/kkw/Nexdo-Server/src/lib/china-calendar.ts`

### 7.2 完成循环提醒的真实行为

这部分必须严格照现在线上行为实现：

1. 原提醒变成已完成历史：
   - `is_completed = true`
   - `repeat_rule = none`
2. 新建一条新的未完成提醒：
   - 新 `id`
   - `due_at = nextDate(...)`
   - `is_completed = false`
   - 保留原来的 `title / note / list_id / group_id / tag_ids / notification_enabled / repeat_rule / repeat_until_at / remind_before_minutes`
3. 写入 `reminder_completion_logs`

补充规则：

- `repeat_until_at` 可空，非空时必须是 RFC3339
- `remind_before_minutes` 为非负整数，默认 `0`
- 如果下一次 `due_at` 晚于 `repeat_until_at`，则不再生成新 reminder，当前 reminder 直接完成

### 7.3 哪些接口会触发循环完成逻辑

以下都必须等价：

- `POST /api/v1/reminders/:id/complete`
- `PATCH /api/v1/reminders/:id` 且 `is_completed=true`
- `PATCH /api/v1/reminders/:id` 把 `due_at` 推进到下一次时，也视为完成一次循环

实现原则：

- 只要是循环提醒，且 PATCH 明确表达“完成本次”，就统一走同一套 service 逻辑
- 不允许第一种调用能循环、第二种调用失效

---

## 8. 设备逻辑

前端会稳定传：

- `X-Nexdo-Device-ID`
- `X-Nexdo-Device-Name`
- `X-Nexdo-Device-Platform`
- `User-Agent`

要求：

- 登录、注册、refresh、鉴权访问时都刷新设备活跃信息
- 设备 IP 使用服务端解析的客户端地址，优先受 `X-Forwarded-For` / 反向代理转发头影响
- `/me/devices` 返回：
  - id
  - device_id
  - device_name
  - platform
  - user_agent
  - ip_address
  - last_seen_at
  - created_at
  - updated_at
- `/me/devices/:id` 支持删除

---

## 9. 闪念逻辑

必须支持两种创建方式：

1. JSON 创建文本闪念
2. multipart/form-data 创建带音频闪念

要求：

- `audio` 最大 10MB
- MIME 必须 `audio/*`
- 支持 `audio_duration_ms`
- 支持 `waveform_samples`
- 音频访问走鉴权下载接口
- 闪念可转为提醒

---

## 10. 必须实现的接口清单

### 鉴权

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`

### 用户

- `GET /api/v1/me`
- `PATCH /api/v1/me`
- `PATCH /api/v1/me/password`
- `GET /api/v1/me/devices`
- `DELETE /api/v1/me/devices/:id`

### 同步

- `GET /api/v1/sync/bootstrap`
- `GET /api/v1/sync/changes?since=...`

### 清单 / 分组 / 标签

- `GET/POST/PATCH/DELETE /api/v1/lists`
- `GET/POST/PATCH/DELETE /api/v1/groups`
- `GET/POST/PATCH/DELETE /api/v1/tags`

### 提醒

- `GET /api/v1/reminders`
- `GET /api/v1/reminders/:id`
- `GET /api/v1/reminders/:id/completion-logs`
- `POST /api/v1/reminders`
- `PATCH /api/v1/reminders/:id`
- `DELETE /api/v1/reminders/:id`
- `POST /api/v1/reminders/:id/complete`
- `POST /api/v1/reminders/:id/uncomplete`

### 闪念

- `GET /api/v1/quick-notes`
- `POST /api/v1/quick-notes`
- `PATCH /api/v1/quick-notes/:id`
- `DELETE /api/v1/quick-notes/:id`
- `GET /api/v1/quick-notes/:id/audio`
- `POST /api/v1/quick-notes/:id/convert`

### 其他

- `GET /api/v1/health`
- `GET /api/v1/docs`

---

## 11. Codex 开发顺序

建议让 Codex 按下面顺序产出：

1. 初始化 Go 项目结构、配置、数据库连接、统一响应
2. 建表 migration 与 GORM model
3. auth + user + device
4. list / group / tag
5. reminder 基础 CRUD
6. reminder 循环完成逻辑
7. sync/bootstrap + sync/changes
8. quick note + audio 存储接口
9. OpenAPI 文档
10. 集成测试

不要一开始就做“推送、队列、复杂调度”。

---

## 12. Codex 的明确实现要求

给 Codex 的关键约束：

- 以当前 TS 版本行为为准，不要自行发明新接口
- 所有时间字段统一 RFC3339
- 错误信息保持中文
- 所有受保护接口都要求 Bearer Token
- 设备头逻辑必须实现
- 循环提醒必须重点测试，至少覆盖：
  - daily 连续 5 次
  - weekly 连续 5 次
  - monthly 连续 5 次
  - monthly 月末边界
  - yearly 闰年边界
  - workday / non_workday 连续 5 次
  - `repeat_until_at` 截止后不再 rollover
  - `remind_before_minutes` 持久化和默认值

---

## 13. Go 版本验收标准

满足以下条件才算第一版完成：

- `go test ./...` 通过
- OpenAPI 可访问
- 注册 / 登录 / refresh / me 可用
- 提醒 CRUD 可用
- 循环提醒完成逻辑与 TS 对齐
- `PATCH is_completed=true` 不会导致循环中断
- 闪念文本 / 音频可创建
- `/sync/bootstrap` 可返回完整初始化数据

---

## 14. 给 Codex 的一句话任务模板

可直接这样下达任务：

> 请基于 `docs/api-technical-solution-go.md`，按当前 TypeScript 版本行为，使用 `Golang + Gin + GORM + PostgreSQL` 实现一版可运行的 Nexdo API。先完成基础骨架、数据库迁移、鉴权、设备、清单/分组/标签、提醒和循环提醒逻辑，并补集成测试。循环提醒的完成行为必须与当前 TS 版本一致。
