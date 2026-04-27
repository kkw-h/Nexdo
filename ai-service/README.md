# Nexdo AI Service

一个基于 Vercel AI SDK 的最小服务，当前按 OpenAI 兼容代理方式配置，并内置一套可扩展的 prompt 系统。

## 环境要求

- Node.js 20+
- 一个可用的 OpenAI 兼容接口

## 安装

```bash
cd ai-service
npm install
```

当前服务读取：

- `OPENAI_API_KEY`
- `OPENAI_BASE_URL`
- `OPENAI_MODEL`
- `OPENAI_WIRE_API`

## 启动

```bash
npm run dev
```

默认服务地址：

```text
http://localhost:3030
```

## 测试接口

健康检查：

```bash
curl http://localhost:3030/health
```

查看支持的命令意图：

```bash
curl http://localhost:3030/api/commands/intents
```

命令意图识别：

```bash
curl -X POST http://localhost:3030/api/commands/classify \
  -H "Content-Type: application/json" \
  -d '{
    "userInput": "把明天下午三点的产品会议提醒删掉",
    "timezone": "Asia/Shanghai"
  }'
```

命令提案：

```bash
curl -X POST http://localhost:3030/api/commands/propose \
  -H "Content-Type: application/json" \
  -d '{
    "userInput": "把明天下午三点的产品会议提醒删掉",
    "timezone": "Asia/Shanghai",
    "classification": {
      "intent": "reminder.delete",
      "operationType": "write_requires_confirmation",
      "confidence": 0.94,
      "summary": "用户想删除一个提醒",
      "missingSlots": [],
      "entities": {
        "title": "产品会议",
        "due_at": "明天下午三点"
      },
      "nextStep": "load_context",
      "clarificationQuestion": null
    },
    "context": {
      "reminders": [
        {
          "id": "rmd_123",
          "title": "产品会议",
          "dueAt": "2026-04-28T15:00:00+08:00",
          "completed": false
        }
      ],
      "quickNotes": [],
      "lists": [],
      "groups": [],
      "tags": []
    }
  }'
```

查看 prompt 模板列表：

```bash
curl http://localhost:3030/api/prompts
```

渲染 prompt 模板：

```bash
curl -X POST http://localhost:3030/api/prompts/render \
  -H "Content-Type: application/json" \
  -d '{
    "promptId": "nexdo.general.reply",
    "variables": {
      "user_input": "请介绍一下 Nexdo",
      "app_name": "Nexdo",
      "response_style": "brief"
    }
  }'
```

AI 测试接口：

```bash
curl -X POST http://localhost:3030/api/test \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "用一句话介绍 Nexdo 是什么"
  }'
```

使用 promptId 测试：

```bash
curl -X POST http://localhost:3030/api/test \
  -H "Content-Type: application/json" \
  -d '{
    "promptId": "nexdo.note.to-task",
    "variables": {
      "note": "明天下午和产品确认提醒列表筛选逻辑，然后整理成开发任务",
      "output_format": "bullet_list"
    }
  }'
```

## 接口说明

- `GET /health`: 不调用模型，返回服务状态
- `GET /api/commands/intents`: 返回支持的命令意图和写操作确认规则
- `POST /api/commands/classify`: 识别用户意图，输出结构化分类结果
- `POST /api/commands/propose`: 基于服务端候选数据生成结构化提案
- `GET /api/prompts`: 返回 prompt 模板清单
- `POST /api/prompts/render`: 校验变量并返回渲染后的 system/prompt
- `POST /api/test`: 调用 Vercel AI SDK 的 `generateText`

请求体：

```json
{
  "prompt": "你好",
  "system": "可选，自定义系统提示词"
}
```

或者：

```json
{
  "promptId": "nexdo.general.reply",
  "variables": {
    "user_input": "你好"
  }
}
```

## 当前内置模板

- `nexdo.general.reply`
- `nexdo.reminder.summarize`
- `nexdo.note.to-task`

## 命令编排约束

推荐链路：

1. 前端提交用户原始输入给 Golang
2. Golang 调 `POST /api/commands/classify`
3. Golang 根据意图查询业务候选数据
4. Golang 调 `POST /api/commands/propose`
5. 如果是写操作，前端必须确认后才能执行

强约束：

- `create / update / delete / complete / uncomplete / convert` 一律视为写操作
- 写操作在 AI 层只会返回 proposal，不会执行
- 真正的 confirmation token 必须由 Golang 生成和校验
- `ai-service` 不负责落库、不负责鉴权、不负责执行删除或修改

## Prompt 结构

代码结构：

- `src/prompt-system/templates.ts`: 模板定义
- `src/prompt-system/registry.ts`: 模板注册表
- `src/prompt-system/renderer.ts`: `{{variable}}` 渲染器
- `src/prompt-system/service.ts`: 变量校验与渲染编排

新增一个 prompt 的方式：

1. 在 `src/prompt-system/templates.ts` 增加模板
2. 定义 `id / version / inputSchema / systemTemplate / userTemplate`
3. 通过 `POST /api/prompts/render` 先验证渲染结果
4. 再通过 `POST /api/test` 做真实模型调用
