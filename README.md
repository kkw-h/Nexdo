# Nexdo Monorepo

Nexdo 现在按 monorepo 结构组织：

- `app/`: Flutter 前端，多端应用与 AltStore 打包脚本都在这里
- `server/`: Go 后端 API 与数据库迁移
- `ai-service/`: 预留的 AI 服务目录
- `docs/`: 仓库级文档

## 文档

- `docs/ai-command-module-plan.md`: AI 指令模块开发规划
- `docs/api-technical-solution-go.md`: Go API 技术方案
- `docs/ALTSTORE.md`: AltStore 打包说明

## 常用命令

前端：

```bash
cd app
flutter pub get
flutter run -d macos
flutter test
flutter analyze
```

后端：

```bash
cd server
go run ./cmd/api
go test ./...
```

AltStore 打包：

```bash
./app/scripts/build_altstore_ipa.sh
```
