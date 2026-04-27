# Nexdo Server Golang 修改紧急程度清单

本文档按当前项目状态给出建议的修改优先级，便于排期和落地。

## P0：应尽快处理

### 1. 补齐真正可用的登录态管理

当前状态：

- 已增加 `sessions` 表
- `access token` 和 `refresh token` 已绑定服务端 session
- `refresh` 已实现 rotation，旧 refresh token 会失效
- `logout` 已撤销当前 session
- 修改密码后会撤销该用户全部 session

已完成动作：

- 增加 `sessions` 表
- 为 refresh token 增加唯一 `jti`
- 实现 refresh token rotation
- `logout` 撤销当前设备会话
- 修改密码时撤销该用户所有 refresh token

剩余关注点：

- 如果后续接入多端会话策略，可以继续细化会话可视化和审计能力
- 如需更强安全性，可进一步引入 refresh token 哈希存储和设备指纹策略

## P1：高优先级，建议近期处理

### 2. 修复 reminder 列表的 N+1 查询问题

当前状态：

- reminder 列表已改为批量查询 tag 关系并一次性组装 `reminderView`
- `sync changes` 路径也已同步使用批量装配逻辑

已完成动作：

- 批量查询 `reminder_tags` 和 `tags`
- 在 service 层一次性组装 `reminderView`

剩余关注点：

- 为列表接口补充性能回归测试

### 3. 修复 quick note 音频文件与数据库写入不一致的问题

当前状态：

- multipart 创建 quick note 时，如果数据库写入失败，已写入音频会回滚删除
- 删除 quick note 时会同步清理音频文件
- 音频清理失败时，数据库删除状态会回滚

已完成动作：

- 为上传流程增加失败回滚
- 删除 quick note 时同步清理音频文件
- 为文件清理失败增加数据库补偿回滚

剩余关注点：

- 如果后续接入对象存储，还需要把补偿逻辑扩展到远端存储实现

### 4. 统一 Go 工具链和容器构建版本

当前状态：

- `go.mod` 使用 `go 1.26.2`
- `Dockerfile` 已统一为 `golang:1.26.2-alpine`

剩余关注点：

- 后续如果增加 CI，还需要显式固定同一 Go 版本
- 后续升级 Go 版本时，需要同时更新 `go.mod`、Dockerfile 和相关文档

已完成动作：

- 统一 Go 版本基线
- 在 README 中补充本地和 Docker 的版本说明

## P2：中优先级，建议逐步整理

### 5. 拆分 `shared.go`

当前状态：

- 原先集中在 `shared.go` 的逻辑已拆分到：
- `guards.go`
- `validation.go`
- `helpers.go`
- `device_helpers.go`
- `reminder_helpers.go`
- `view_helpers.go`

已完成动作：

- 按资源校验、请求校验、通用工具、设备处理、reminder 关系、视图拼装拆分职责
- `shared.go` 已收缩为轻量上下文适配文件

剩余关注点：

- 后续可以继续评估是否把 query adapter 再单独拆到 `context_adapters.go`

### 6. 加强输入校验和业务约束

当前状态：

- 已补充 `email`、`timezone`、`locale`、`avatar_url` 校验
- 已收紧 quick note 状态流转规则：
- 无关联 reminder 时不能手动标记 `converted`
- `converted` 状态不能改回 `draft`

已完成动作：

- 收紧邮箱、时区、locale、URL 等字段校验
- 明确 quick note 的部分状态流转约束

剩余关注点：

- reminder 资源字段仍可继续增加更细的语义校验
- 资源名称、颜色值、排序字段等仍然偏宽松

### 7. 补充更细粒度测试

当前状态：

- 现已新增函数级测试文件：
- `validation_test.go`
- `guards_test.go`
- `helpers_test.go`
- 现已新增业务逻辑整体测试文件：
- `reminder_form_test.go`
- `resource_form_test.go`
- `quicknote_form_test.go`
- `auth_form_test.go`
- 已补充 repository / service / handler 组合验证，覆盖主要资源的创建、更新、删除、越权和默认值场景

已完成动作：

- 为输入校验、session 判定、文件清理补充更细粒度测试
- 为 `reminder` 表单字段补齐创建 / 更新的主要边界分支
- 为 `lists / groups / tags` 补齐表单字段、默认值、空白名称、跨用户访问测试
- 为 `quick-notes` 补齐 JSON 提交、空白内容、波形默认值与清空、状态流转测试
- 为 `auth` 补齐注册、登录、资料更新、修改密码、删除设备等主要表单与业务分支测试
- 修复测试中暴露的业务问题：
- `reminder.notification_enabled=false` 被默认值覆盖
- `quick note` JSON 路径未拒绝空白内容
- `lists / groups / tags` 的 patch 未拦截空白名称

剩余关注点：

- 目前仍以 SQLite 下的接口 / service / repository 测试为主，仍缺少 PostgreSQL 方言下的集成验证
- multipart quick note 上传仍可继续细化更多异常输入组合
- 颜色值、排序字段、图标编码等资源字段的语义约束还可以继续收紧并补专门测试

## 建议实施顺序

1. 先做登录态管理改造，这是安全和行为正确性的最高优先级。
2. 然后处理 reminder 列表性能和 quick note 文件一致性。
3. 再统一工具链、拆分共享文件、加强输入校验并补细粒度测试。

## 当前结论

- P0 已完成。
- P1 已完成。
- P2 已完成当前阶段，结构整理、输入校验和业务逻辑整体测试已明显补强。
- 如果继续推进，建议转向 PostgreSQL 集成验证、multipart 异常路径扩展，以及资源字段的更严格业务约束。
