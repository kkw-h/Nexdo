package app

import "github.com/gin-gonic/gin"

func buildDoc() gin.H {
	return gin.H{
		"openapi": "3.0.3",
		"info": gin.H{
			"title":       "Nexdo API",
			"version":     "v1",
			"description": "Nexdo Golang API 第一版，覆盖鉴权、设备、资源、提醒、同步、闪念与音频下载。",
		},
		"servers": []gin.H{{"url": "/"}},
		"paths": gin.H{
			"/api/v1/health": gin.H{
				"get": gin.H{"summary": "健康检查", "tags": []string{"system"}},
			},
			"/api/v1/docs": gin.H{
				"get": gin.H{"summary": "OpenAPI 文档", "tags": []string{"system"}},
			},
			"/api/v1/docs/ui": gin.H{
				"get": gin.H{"summary": "OpenAPI 文档 UI", "tags": []string{"system"}},
			},
			"/api/v1/auth/register": gin.H{
				"post": gin.H{"summary": "注册", "tags": []string{"auth"}},
			},
			"/api/v1/auth/login": gin.H{
				"post": gin.H{"summary": "登录", "tags": []string{"auth"}},
			},
			"/api/v1/auth/refresh": gin.H{
				"post": gin.H{"summary": "刷新 token", "tags": []string{"auth"}},
			},
			"/api/v1/auth/logout": gin.H{
				"post": gin.H{"summary": "登出", "tags": []string{"auth"}, "security": bearer()},
			},
			"/api/v1/me": gin.H{
				"get":   gin.H{"summary": "当前用户", "tags": []string{"user"}, "security": bearer()},
				"patch": gin.H{"summary": "更新用户", "tags": []string{"user"}, "security": bearer()},
			},
			"/api/v1/me/password": gin.H{
				"patch": gin.H{"summary": "修改密码", "tags": []string{"user"}, "security": bearer()},
			},
			"/api/v1/me/devices": gin.H{
				"get": gin.H{"summary": "设备列表", "tags": []string{"device"}, "security": bearer()},
			},
			"/api/v1/me/devices/{id}": gin.H{
				"delete": gin.H{"summary": "删除设备", "tags": []string{"device"}, "security": bearer()},
			},
			"/api/v1/lists": gin.H{
				"get":  gin.H{"summary": "清单列表", "tags": []string{"list"}, "security": bearer()},
				"post": gin.H{"summary": "创建清单", "tags": []string{"list"}, "security": bearer()},
			},
			"/api/v1/lists/{id}": gin.H{
				"patch":  gin.H{"summary": "更新清单", "tags": []string{"list"}, "security": bearer()},
				"delete": gin.H{"summary": "删除清单", "tags": []string{"list"}, "security": bearer()},
			},
			"/api/v1/groups": gin.H{
				"get":  gin.H{"summary": "分组列表", "tags": []string{"group"}, "security": bearer()},
				"post": gin.H{"summary": "创建分组", "tags": []string{"group"}, "security": bearer()},
			},
			"/api/v1/groups/{id}": gin.H{
				"patch":  gin.H{"summary": "更新分组", "tags": []string{"group"}, "security": bearer()},
				"delete": gin.H{"summary": "删除分组", "tags": []string{"group"}, "security": bearer()},
			},
			"/api/v1/tags": gin.H{
				"get":  gin.H{"summary": "标签列表", "tags": []string{"tag"}, "security": bearer()},
				"post": gin.H{"summary": "创建标签", "tags": []string{"tag"}, "security": bearer()},
			},
			"/api/v1/tags/{id}": gin.H{
				"patch":  gin.H{"summary": "更新标签", "tags": []string{"tag"}, "security": bearer()},
				"delete": gin.H{"summary": "删除标签", "tags": []string{"tag"}, "security": bearer()},
			},
			"/api/v1/reminders": gin.H{
				"get":  gin.H{"summary": "提醒列表", "tags": []string{"reminder"}, "security": bearer()},
				"post": gin.H{"summary": "创建提醒", "tags": []string{"reminder"}, "security": bearer()},
			},
			"/api/v1/reminders/{id}": gin.H{
				"get":    gin.H{"summary": "提醒详情", "tags": []string{"reminder"}, "security": bearer()},
				"patch":  gin.H{"summary": "更新提醒", "tags": []string{"reminder"}, "security": bearer()},
				"delete": gin.H{"summary": "删除提醒", "tags": []string{"reminder"}, "security": bearer()},
			},
			"/api/v1/reminders/{id}/complete": gin.H{
				"post": gin.H{"summary": "完成提醒", "tags": []string{"reminder"}, "security": bearer()},
			},
			"/api/v1/reminders/{id}/uncomplete": gin.H{
				"post": gin.H{"summary": "取消完成提醒", "tags": []string{"reminder"}, "security": bearer()},
			},
			"/api/v1/reminders/{id}/completion-logs": gin.H{
				"get": gin.H{"summary": "提醒完成历史", "tags": []string{"reminder"}, "security": bearer()},
			},
			"/api/v1/sync/bootstrap": gin.H{
				"get": gin.H{"summary": "同步初始化", "tags": []string{"sync"}, "security": bearer()},
			},
			"/api/v1/sync/changes": gin.H{
				"get": gin.H{"summary": "同步增量", "tags": []string{"sync"}, "security": bearer()},
			},
			"/api/v1/quick-notes": gin.H{
				"get":  gin.H{"summary": "闪念列表", "tags": []string{"quick_note"}, "security": bearer()},
				"post": gin.H{"summary": "创建闪念", "tags": []string{"quick_note"}, "security": bearer()},
			},
			"/api/v1/quick-notes/{id}": gin.H{
				"patch":  gin.H{"summary": "更新闪念", "tags": []string{"quick_note"}, "security": bearer()},
				"delete": gin.H{"summary": "删除闪念", "tags": []string{"quick_note"}, "security": bearer()},
			},
			"/api/v1/quick-notes/{id}/audio": gin.H{
				"get": gin.H{"summary": "下载闪念音频", "tags": []string{"quick_note"}, "security": bearer()},
			},
			"/api/v1/quick-notes/{id}/convert": gin.H{
				"post": gin.H{"summary": "闪念转提醒", "tags": []string{"quick_note"}, "security": bearer()},
			},
			"/api/v1/ai/commands/resolve": gin.H{
				"post": gin.H{"summary": "解析 AI 命令并返回提案", "tags": []string{"ai_command"}, "security": bearer()},
			},
			"/api/v1/ai/commands/confirmations/verify": gin.H{
				"post": gin.H{"summary": "校验 AI 命令确认 token", "tags": []string{"ai_command"}, "security": bearer()},
			},
			"/api/v1/ai/commands/confirmations/execute": gin.H{
				"post": gin.H{"summary": "执行已确认的 AI 命令", "tags": []string{"ai_command"}, "security": bearer()},
			},
		},
		"components": gin.H{
			"securitySchemes": gin.H{
				"BearerAuth": gin.H{
					"type":   "http",
					"scheme": "bearer",
				},
			},
			"schemas": gin.H{
				"SuccessResponse": gin.H{
					"type": "object",
					"properties": gin.H{
						"code":    gin.H{"type": "integer", "example": 0},
						"message": gin.H{"type": "string", "example": "ok"},
						"data":    gin.H{"type": "object"},
					},
				},
				"ErrorResponse": gin.H{
					"type": "object",
					"properties": gin.H{
						"code":    gin.H{"type": "integer", "example": 40000},
						"message": gin.H{"type": "string", "example": "请求参数错误"},
						"error":   gin.H{"type": "string", "example": "due_at 必须是 RFC3339 时间戳"},
					},
				},
				"User": gin.H{
					"type": "object",
					"properties": gin.H{
						"id":         gin.H{"type": "string"},
						"email":      gin.H{"type": "string"},
						"nickname":   gin.H{"type": "string"},
						"avatar_url": gin.H{"type": "string"},
						"timezone":   gin.H{"type": "string"},
						"locale":     gin.H{"type": "string"},
						"created_at": gin.H{"type": "string", "format": "date-time"},
						"updated_at": gin.H{"type": "string", "format": "date-time"},
					},
				},
				"Reminder": gin.H{
					"type": "object",
					"properties": gin.H{
						"id":                    gin.H{"type": "string"},
						"title":                 gin.H{"type": "string"},
						"note":                  gin.H{"type": "string"},
						"due_at":                gin.H{"type": "string", "format": "date-time"},
						"repeat_until_at":       gin.H{"type": "string", "format": "date-time", "nullable": true},
						"remind_before_minutes": gin.H{"type": "integer"},
						"is_completed":          gin.H{"type": "boolean"},
						"list_id":               gin.H{"type": "string"},
						"group_id":              gin.H{"type": "string"},
						"notification_enabled":  gin.H{"type": "boolean"},
						"repeat_rule":           gin.H{"type": "string"},
						"created_at":            gin.H{"type": "string", "format": "date-time"},
						"updated_at":            gin.H{"type": "string", "format": "date-time"},
						"tags":                  gin.H{"type": "array", "items": gin.H{"$ref": "#/components/schemas/Tag"}},
					},
				},
				"Tag": gin.H{
					"type": "object",
					"properties": gin.H{
						"id":          gin.H{"type": "string"},
						"name":        gin.H{"type": "string"},
						"color_value": gin.H{"type": "integer"},
						"created_at":  gin.H{"type": "string", "format": "date-time"},
						"updated_at":  gin.H{"type": "string", "format": "date-time"},
					},
				},
				"QuickNote": gin.H{
					"type": "object",
					"properties": gin.H{
						"id":                    gin.H{"type": "string"},
						"content":               gin.H{"type": "string"},
						"status":                gin.H{"type": "string"},
						"converted_reminder_id": gin.H{"type": "string", "nullable": true},
						"audio_key":             gin.H{"type": "string", "nullable": true},
						"audio_filename":        gin.H{"type": "string", "nullable": true},
						"audio_mime_type":       gin.H{"type": "string", "nullable": true},
						"audio_size_bytes":      gin.H{"type": "integer", "nullable": true},
						"audio_duration_ms":     gin.H{"type": "integer", "nullable": true},
						"waveform_samples":      gin.H{"type": "array", "items": gin.H{"type": "integer"}},
						"audio_url":             gin.H{"type": "string", "nullable": true},
						"created_at":            gin.H{"type": "string", "format": "date-time"},
						"updated_at":            gin.H{"type": "string", "format": "date-time"},
					},
				},
			},
		},
	}
}

func bearer() []gin.H {
	return []gin.H{{"BearerAuth": []string{}}}
}

func buildDocUI() string {
	return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Nexdo API Docs</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f5f1e8;
      --panel: #fffdf8;
      --ink: #1f2a37;
      --muted: #6b7280;
      --line: #d6cfc2;
      --accent: #14532d;
      --accent-2: #b45309;
      --chip: #efe7d7;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "Iowan Old Style", "Palatino Linotype", "Book Antiqua", Georgia, serif;
      background:
        radial-gradient(circle at top left, rgba(180,83,9,.12), transparent 28%),
        radial-gradient(circle at bottom right, rgba(20,83,45,.12), transparent 30%),
        var(--bg);
      color: var(--ink);
    }
    .wrap {
      max-width: 1100px;
      margin: 0 auto;
      padding: 32px 20px 48px;
    }
    .hero {
      background: linear-gradient(135deg, rgba(255,253,248,.96), rgba(250,244,232,.96));
      border: 1px solid var(--line);
      border-radius: 24px;
      padding: 28px;
      box-shadow: 0 12px 32px rgba(31,42,55,.08);
    }
    h1 {
      margin: 0 0 8px;
      font-size: clamp(2rem, 4vw, 3.5rem);
      line-height: 1;
    }
    .sub {
      margin: 0;
      color: var(--muted);
      font-size: 1rem;
    }
    .actions {
      display: flex;
      gap: 12px;
      flex-wrap: wrap;
      margin-top: 20px;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      padding: 10px 16px;
      border-radius: 999px;
      text-decoration: none;
      border: 1px solid var(--line);
      background: var(--panel);
      color: var(--ink);
      font-weight: 600;
    }
    .btn.primary {
      background: var(--accent);
      color: #fff;
      border-color: var(--accent);
    }
    .meta {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 14px;
      margin-top: 24px;
    }
    .meta-card, .tag-panel, .path {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 18px;
    }
    .meta-card {
      padding: 14px 16px;
    }
    .meta-label {
      font-size: .82rem;
      text-transform: uppercase;
      letter-spacing: .08em;
      color: var(--muted);
    }
    .meta-value {
      margin-top: 6px;
      font-size: 1.05rem;
      font-weight: 600;
    }
    .section-title {
      margin: 28px 0 12px;
      font-size: 1.25rem;
    }
    .tags {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
    }
    .tag-panel {
      padding: 10px 14px;
      background: var(--chip);
      font-weight: 600;
    }
    .paths {
      display: grid;
      gap: 14px;
      margin-top: 10px;
    }
    .path {
      padding: 16px;
    }
    .route-line {
      display: flex;
      gap: 12px;
      flex-wrap: wrap;
      align-items: center;
      margin-bottom: 8px;
    }
    .method {
      min-width: 72px;
      text-align: center;
      padding: 6px 10px;
      border-radius: 999px;
      color: #fff;
      font: 700 .82rem/1.1 ui-monospace, SFMono-Regular, Menlo, monospace;
      text-transform: uppercase;
    }
    .method.get { background: #0f766e; }
    .method.post { background: #1d4ed8; }
    .method.patch { background: #b45309; }
    .method.delete { background: #b91c1c; }
    .path-text {
      font: 600 .98rem/1.3 ui-monospace, SFMono-Regular, Menlo, monospace;
      word-break: break-all;
    }
    .summary {
      color: var(--muted);
    }
  </style>
</head>
<body>
  <div class="wrap">
    <section class="hero">
      <h1>Nexdo API Docs</h1>
      <p class="sub">Golang + Gin + GORM 版本接口文档。保留 JSON 文档入口，也提供可直接浏览的 UI。</p>
      <div class="actions">
        <a class="btn primary" href="/api/v1/docs" target="_blank" rel="noreferrer">查看 OpenAPI JSON</a>
        <a class="btn" href="/api/v1/health" target="_blank" rel="noreferrer">健康检查</a>
      </div>
      <div class="meta">
        <div class="meta-card">
          <div class="meta-label">Version</div>
          <div class="meta-value">v1</div>
        </div>
        <div class="meta-card">
          <div class="meta-label">Auth</div>
          <div class="meta-value">Bearer Token</div>
        </div>
        <div class="meta-card">
          <div class="meta-label">Format</div>
          <div class="meta-value">RFC3339 / JSON</div>
        </div>
      </div>
    </section>

    <h2 class="section-title">Tags</h2>
    <section class="tags">
      <div class="tag-panel">system</div>
      <div class="tag-panel">auth</div>
      <div class="tag-panel">user</div>
      <div class="tag-panel">device</div>
      <div class="tag-panel">list</div>
      <div class="tag-panel">group</div>
      <div class="tag-panel">tag</div>
      <div class="tag-panel">reminder</div>
      <div class="tag-panel">sync</div>
      <div class="tag-panel">quick_note</div>
      <div class="tag-panel">ai_command</div>
    </section>

    <h2 class="section-title">Key Paths</h2>
    <section class="paths">
      <article class="path"><div class="route-line"><span class="method get">GET</span><span class="path-text">/api/v1/docs</span></div><div class="summary">OpenAPI JSON 文档</div></article>
      <article class="path"><div class="route-line"><span class="method post">POST</span><span class="path-text">/api/v1/auth/register</span></div><div class="summary">注册并返回用户与 token</div></article>
      <article class="path"><div class="route-line"><span class="method post">POST</span><span class="path-text">/api/v1/auth/login</span></div><div class="summary">登录并返回用户与 token</div></article>
      <article class="path"><div class="route-line"><span class="method get">GET</span><span class="path-text">/api/v1/me</span></div><div class="summary">获取当前用户</div></article>
      <article class="path"><div class="route-line"><span class="method get">GET</span><span class="path-text">/api/v1/reminders</span></div><div class="summary">提醒列表与筛选查询</div></article>
      <article class="path"><div class="route-line"><span class="method post">POST</span><span class="path-text">/api/v1/reminders/:id/complete</span></div><div class="summary">完成提醒，循环提醒会 rollover</div></article>
      <article class="path"><div class="route-line"><span class="method get">GET</span><span class="path-text">/api/v1/sync/bootstrap</span></div><div class="summary">首次同步完整数据</div></article>
      <article class="path"><div class="route-line"><span class="method get">GET</span><span class="path-text">/api/v1/sync/changes?since=...</span></div><div class="summary">增量同步变更</div></article>
      <article class="path"><div class="route-line"><span class="method post">POST</span><span class="path-text">/api/v1/quick-notes</span></div><div class="summary">文本或 multipart 音频闪念</div></article>
      <article class="path"><div class="route-line"><span class="method get">GET</span><span class="path-text">/api/v1/quick-notes/:id/audio</span></div><div class="summary">鉴权下载音频</div></article>
      <article class="path"><div class="route-line"><span class="method post">POST</span><span class="path-text">/api/v1/ai/commands/resolve</span></div><div class="summary">解析自然语言命令并生成只读结果或待确认提案</div></article>
      <article class="path"><div class="route-line"><span class="method post">POST</span><span class="path-text">/api/v1/ai/commands/confirmations/verify</span></div><div class="summary">校验命令确认 token 是否仍有效</div></article>
      <article class="path"><div class="route-line"><span class="method post">POST</span><span class="path-text">/api/v1/ai/commands/confirmations/execute</span></div><div class="summary">消费确认 token 并执行提醒类写操作</div></article>
    </section>
  </div>
</body>
</html>`
}
