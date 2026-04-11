# Nexdo API 技术方案文档（Golang）

## 1. 文档目标

本文档用于定义 Nexdo 当前阶段的后端 API 技术方案，服务于以下目标：

- 支撑 Flutter 多端数据同步
- 从当前本地数据模型平滑演进到云端架构
- 兼容提醒事项、任务清单、分组、标签、循环提醒、闪念等核心能力
- 为后续推送通知、协作、统计、订阅能力预留扩展空间

当前前端已有的核心领域对象来自本地模型：

- `ReminderItem`
- `ReminderList`
- `ReminderGroup`
- `ReminderTag`
- `ReminderRepeatRule`

因此本方案优先保证“领域模型一致性”和“本地到云端的迁移成本最低”。

---

## 2. 技术选型结论

### 2.1 推荐技术栈

- 编程语言：`Golang 1.22+`
- Web 框架：`Gin`
- ORM / SQL 工具：`GORM`
- 数据库：`PostgreSQL 16`
- 缓存 / 队列：`Redis`
- 鉴权：`JWT + Refresh Token`
- 配置管理：`Viper` 或环境变量
- 数据迁移：`golang-migrate`
- API 文档：`OpenAPI 3 + Swagger`
- 日志：`zap`
- 定时任务：`robfig/cron` 或基于 Redis 的异步任务
- 容器化：`Docker + Docker Compose`
- 反向代理：`Nginx`

### 2.2 为什么这样选

#### Go

- 性能稳定，适合 API、任务调度、通知处理
- 并发模型天然适合提醒、同步、后台任务
- 部署简单，单二进制很适合中小团队快速上线

#### Gin

- 上手快，生态成熟
- 很适合先做 REST API
- 中间件、参数校验、路由组织比较顺手

#### PostgreSQL

- 当前数据结构天然是关系型
- 支持复杂查询、事务、索引、JSON 扩展
- 对后续协作、统计、审计、订阅都更友好

#### Redis

- 适合存会话、限流、短期缓存
- 适合做异步任务和提醒调度加速层

#### GORM

- 初期开发效率高
- 团队上手快
- 后续如果对复杂 SQL 有更高要求，可以逐步引入原生 SQL 或 `sqlc`

---

## 3. 总体架构

### 3.1 架构分层

建议采用典型分层：

1. `api / handler`
2. `service`
3. `repository`
4. `model / entity`
5. `infrastructure`

### 3.2 推荐目录结构

```text
server/
  cmd/
    api/
      main.go
  internal/
    app/
      bootstrap.go
    config/
      config.go
    middleware/
      auth.go
      logger.go
      recovery.go
    modules/
      auth/
        handler.go
        service.go
        repository.go
        dto.go
        model.go
      reminder/
        handler.go
        service.go
        repository.go
        dto.go
        model.go
      list/
      group/
      tag/
      quicknote/
      sync/
      user/
      device/
    pkg/
      db/
      jwt/
      logger/
      redis/
      response/
      validator/
  migrations/
  docs/
  deployments/
    docker/
```

### 3.3 模块边界

第一期建议拆成这些模块：

- `auth`：注册、登录、刷新令牌、退出
- `user`：用户信息、偏好设置
- `device`：设备登记、推送 token、平台信息
- `list`：任务清单
- `group`：分组
- `tag`：标签
- `reminder`：提醒事项
- `quicknote`：闪念
- `sync`：增量同步、冲突处理
- `notification`：提醒调度、推送状态

---

## 4. 业务对象设计

### 4.1 当前前端模型映射

#### ReminderItem

- `id`
- `title`
- `note`
- `due_at`
- `is_completed`
- `created_at`
- `updated_at`
- `list_id`
- `group_id`
- `tag_ids`
- `notification_enabled`
- `repeat_rule`

#### ReminderList

- `id`
- `name`
- `color_value`

#### ReminderGroup

- `id`
- `name`
- `icon_code_point`

#### ReminderTag

- `id`
- `name`
- `color_value`

#### QuickNote

当前前端还未落地，但从产品结构上应提前纳入：

- `id`
- `content`
- `source`
- `status`
- `created_at`
- `updated_at`
- `converted_reminder_id`

### 4.2 repeat_rule 设计

建议后端固定枚举值：

- `none`
- `daily`
- `weekly`
- `monthly`
- `yearly`

后续如果要扩展更复杂规则，再单独升级为：

- `repeat_type`
- `repeat_interval`
- `repeat_weekdays`
- `repeat_end_at`
- `timezone`

第一期先不要过度设计。

---

## 5. 数据库设计

### 5.1 核心表

#### users

```text
id
email
password_hash
nickname
avatar_url
timezone
locale
created_at
updated_at
deleted_at
```

#### devices

```text
id
user_id
platform
device_name
push_token
app_version
last_active_at
created_at
updated_at
```

#### reminder_lists

```text
id
user_id
name
color_value
sort_order
created_at
updated_at
deleted_at
```

#### reminder_groups

```text
id
user_id
name
icon_code_point
sort_order
created_at
updated_at
deleted_at
```

#### reminder_tags

```text
id
user_id
name
color_value
created_at
updated_at
deleted_at
```

#### reminders

```text
id
user_id
list_id
group_id
title
note
due_at
is_completed
completed_at
notification_enabled
repeat_rule
source
created_at
updated_at
deleted_at
version
```

#### reminder_tag_relations

```text
id
reminder_id
tag_id
created_at
```

#### quick_notes

```text
id
user_id
content
status
converted_reminder_id
created_at
updated_at
deleted_at
```

#### sync_operations

```text
id
user_id
device_id
resource_type
resource_id
operation
payload
created_at
```

### 5.2 索引建议

重点索引：

- `reminders(user_id, due_at)`
- `reminders(user_id, is_completed, due_at)`
- `reminders(user_id, updated_at)`
- `reminder_lists(user_id, sort_order)`
- `reminder_groups(user_id, sort_order)`
- `reminder_tags(user_id, name)`
- `quick_notes(user_id, created_at desc)`

### 5.3 软删除

建议第一期统一采用软删除：

- 保留同步一致性
- 减少误删风险
- 便于后续做回收站

---

## 6. API 风格设计

### 6.1 总体原则

- 风格：RESTful
- 前缀：`/api/v1`
- 返回格式统一
- 所有写操作记录 `updated_at`
- 所有资源默认带 `id`
- 支持分页、筛选、排序

### 6.2 统一响应格式

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
  "code": 40001,
  "message": "invalid params",
  "error": {
    "field": "title",
    "reason": "required"
  }
}
```

### 6.3 鉴权方式

- Access Token：短期 JWT
- Refresh Token：长期刷新
- Header：`Authorization: Bearer <token>`

### 6.4 API 列表

#### Auth

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`

#### User

- `GET /api/v1/me`
- `PATCH /api/v1/me`

#### Lists

- `GET /api/v1/lists`
- `POST /api/v1/lists`
- `PATCH /api/v1/lists/:id`
- `DELETE /api/v1/lists/:id`

#### Groups

- `GET /api/v1/groups`
- `POST /api/v1/groups`
- `PATCH /api/v1/groups/:id`
- `DELETE /api/v1/groups/:id`

#### Tags

- `GET /api/v1/tags`
- `POST /api/v1/tags`
- `PATCH /api/v1/tags/:id`
- `DELETE /api/v1/tags/:id`

#### Reminders

- `GET /api/v1/reminders`
- `GET /api/v1/reminders/:id`
- `POST /api/v1/reminders`
- `PATCH /api/v1/reminders/:id`
- `DELETE /api/v1/reminders/:id`
- `POST /api/v1/reminders/:id/complete`
- `POST /api/v1/reminders/:id/uncomplete`

#### Quick Notes

- `GET /api/v1/quick-notes`
- `POST /api/v1/quick-notes`
- `PATCH /api/v1/quick-notes/:id`
- `DELETE /api/v1/quick-notes/:id`
- `POST /api/v1/quick-notes/:id/convert`

#### Sync

- `GET /api/v1/sync/bootstrap`
- `GET /api/v1/sync/changes?since=...`
- `POST /api/v1/sync/push`

#### Devices

- `POST /api/v1/devices/register`
- `PATCH /api/v1/devices/:id`

---

## 7. 关键接口设计

### 7.1 获取工作区初始化数据

```http
GET /api/v1/sync/bootstrap
```

返回：

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "lists": [],
    "groups": [],
    "tags": [],
    "reminders": [],
    "quick_notes": [],
    "server_time": "2026-04-11T12:00:00Z"
  }
}
```

这会直接对应你前端现在的 `ReminderWorkspace` 概念。

### 7.2 创建提醒

```http
POST /api/v1/reminders
```

请求体：

```json
{
  "title": "晚上复盘今天完成情况",
  "note": "完成后补一下明天的提醒安排",
  "due_at": "2026-04-11T20:00:00+08:00",
  "list_id": "xxx",
  "group_id": "xxx",
  "tag_ids": ["tag1", "tag2"],
  "notification_enabled": true,
  "repeat_rule": "daily"
}
```

### 7.3 完成提醒

```http
POST /api/v1/reminders/:id/complete
```

服务端逻辑：

- 非循环提醒：标记完成
- 循环提醒：推进 `due_at` 到下一次，保留未完成状态，记录一次完成日志

建议同时新增一张表：

#### reminder_completion_logs

```text
id
reminder_id
user_id
completed_at
original_due_at
next_due_at
created_at
```

这样循环提醒不会丢失完成历史。

---

## 8. 同步策略设计

### 8.1 推荐同步模型

建议采用：

- 客户端本地缓存
- 服务端主数据源
- 基于 `updated_at + version` 的增量同步

### 8.2 基本规则

- 每条记录有 `updated_at`
- 每条记录有 `version`
- 客户端记录 `last_sync_at`
- 启动时拉 bootstrap
- 后续拉 changes
- 本地变更 push 到服务端

### 8.3 冲突策略

第一期建议简单一点：

- 默认 `last write wins`
- 服务端比较 `updated_at`
- 若冲突严重，再返回冲突错误给客户端

后续再升级到：

- 字段级合并
- 客户端冲突提示

---

## 9. 通知与提醒调度方案

### 9.1 第一阶段

当前 Flutter 端已有本地通知，因此服务端第一阶段不必立刻接管全部提醒发送。

服务端先负责：

- 保存提醒规则
- 保存循环规则
- 保存时区
- 保存设备 token

客户端继续负责本地通知调度。

### 9.2 第二阶段

服务端开始负责推送：

- 创建提醒后生成调度任务
- 修改提醒后重建调度任务
- 循环提醒完成后生成下一次调度

### 9.3 推荐实现

- Redis ZSet 或独立 `notification_jobs` 表
- Worker 定时扫描到期任务
- 调用推送服务（FCM / APNs）

#### notification_jobs

```text
id
user_id
device_id
reminder_id
trigger_at
status
retry_count
created_at
updated_at
```

---

## 10. 闪念设计

既然产品已经要增加 `闪念` 菜单，后端建议直接纳入一期范围。

### 10.1 闪念状态

- `draft`
- `converted`
- `archived`

### 10.2 关键能力

- 快速记录
- 编辑
- 删除
- 转提醒

### 10.3 转提醒接口

```http
POST /api/v1/quick-notes/:id/convert
```

请求体：

```json
{
  "title": "整理需求会议纪要",
  "due_at": "2026-04-12T10:00:00+08:00",
  "list_id": "xxx",
  "group_id": "xxx",
  "tag_ids": []
}
```

---

## 11. 安全设计

### 11.1 必备安全项

- 密码使用 `bcrypt`
- JWT 签名密钥独立管理
- Refresh Token 支持失效
- 接口限流
- 参数校验
- 操作日志
- 软删除资源鉴权检查

### 11.2 数据权限

所有核心表必须带 `user_id`，查询时强制按用户隔离。

永远不要只按 `id` 查资源并返回。

必须按：

- `id`
- `user_id`

联合判断。

---

## 12. 部署方案

### 12.1 开发环境

- `api`
- `postgres`
- `redis`
- `pgadmin` 可选

### 12.2 生产环境

- `api` 多实例
- `postgres` 托管或主从
- `redis`
- `nginx`
- `prometheus + grafana` 可选

### 12.3 Docker Compose 参考

建议准备：

- `docker-compose.dev.yml`
- `docker-compose.prod.yml`

---

## 13. 日志与监控

### 13.1 日志

统一结构化日志字段：

- `trace_id`
- `user_id`
- `device_id`
- `path`
- `method`
- `latency`
- `status_code`

### 13.2 监控指标

- 请求耗时
- 5xx 错误率
- 数据库连接数
- Redis 使用情况
- 通知任务成功率
- 同步任务失败率

---

## 14. 开发阶段规划

### Phase 1

- 初始化 Go 后端工程
- 接入 PostgreSQL / Redis
- 完成 auth / me
- 完成 lists / groups / tags / reminders CRUD
- 完成 bootstrap 接口

### Phase 2

- 完成 quick_notes
- 完成 sync changes / push
- 完成设备注册
- 完成循环提醒完成日志

### Phase 3

- 服务端通知调度
- 推送集成
- 数据统计
- 闪念转提醒流程完善

---

## 15. 最终建议

### 15.1 当前建议的正式技术方案

- 语言：`Go`
- 框架：`Gin`
- 数据库：`PostgreSQL`
- 缓存 / 队列：`Redis`
- ORM：`GORM`
- 鉴权：`JWT + Refresh Token`
- 同步：`bootstrap + changes + push`
- 文档：`Swagger / OpenAPI`

### 15.2 不建议现在做的事

- 先上微服务
- 先做过度复杂的重复规则
- 先做字段级冲突合并
- 先做 WebSocket 全量实时同步

当前最重要的是：

1. 先把单体 API 跑稳
2. 和 Flutter 端模型完全对齐
3. 把登录、提醒、清单、闪念、同步打通

---

## 16. 下一步执行建议

建议按下面顺序继续推进：

1. 在仓库下新建 `server/` Go 后端工程
2. 初始化 `Gin + GORM + PostgreSQL + Redis`
3. 先完成数据库迁移和核心表
4. 实现 `auth + me + bootstrap + reminders CRUD`
5. Flutter 端替换本地仓库为 `remote/local hybrid repository`

如果继续往下做，下一步最合适的是：

- 我直接帮你在当前项目里初始化 `server/` 后端骨架
- 并把第一批数据表和 API 路由一起搭起来
