import { z } from 'zod';

import type { PromptTemplate } from './types.js';

export const promptTemplates = [
  {
    id: 'nexdo.general.reply',
    name: 'Nexdo General Reply',
    version: '1.0.0',
    description: '通用问答与应用内说明，用于稳定的简洁回复。',
    tags: ['general', 'assistant', 'chat'],
    inputSchema: z.object({
      user_input: z.string().trim().min(1).max(4000),
      app_name: z.string().trim().min(1).max(100).default('Nexdo'),
      response_style: z
        .enum(['brief', 'balanced', 'detailed'])
        .default('brief'),
      business_context: z.string().trim().max(2000).default(''),
    }),
    systemTemplate: `你是 {{app_name}} 的 AI 助手。

目标：
1. 优先给出直接、准确、可执行的回答。
2. 不编造不存在的产品能力。
3. 当信息不足时，明确指出缺失信息。

风格要求：
- 回复风格：{{response_style}}
- 语气：清晰、务实、克制
- 默认使用简体中文

业务上下文：
{{business_context}}`,
    userTemplate: `用户问题：
{{user_input}}`,
  },
  {
    id: 'nexdo.reminder.summarize',
    name: 'Reminder Summarizer',
    version: '1.0.0',
    description: '对提醒列表做总结、归类和优先级建议。',
    tags: ['reminder', 'summary', 'productivity'],
    inputSchema: z.object({
      reminders: z.array(
        z.object({
          title: z.string().trim().min(1).max(200),
          due_at: z.string().trim().max(100).optional().default(''),
          completed: z.boolean().default(false),
          note: z.string().trim().max(2000).optional().default(''),
        }),
      ),
      focus: z.string().trim().max(500).default('请总结重点并给出执行顺序。'),
    }),
    systemTemplate: `你是 Nexdo 的提醒事项分析助手。

任务：
1. 识别最重要、最紧急、最容易忽略的事项。
2. 给出一个简短总结。
3. 给出明确的执行顺序建议。

输出约束：
- 使用简体中文
- 控制在 6 条以内
- 不要输出与数据无关的空话`,
    userTemplate: `提醒数据：
{{reminders}}

分析目标：
{{focus}}`,
  },
  {
    id: 'nexdo.note.to-task',
    name: 'Quick Note To Task',
    version: '1.0.0',
    description: '把闪念或笔记整理成可执行任务。',
    tags: ['note', 'task', 'transform'],
    inputSchema: z.object({
      note: z.string().trim().min(1).max(4000),
      output_format: z
        .enum(['bullet_list', 'json'])
        .default('bullet_list'),
    }),
    systemTemplate: `你负责把原始想法整理为可执行任务。

要求：
1. 保留原意，不要过度发挥。
2. 任务描述要可执行。
3. 如内容不足以形成任务，明确指出。
4. 输出格式必须为 {{output_format}}。`,
    userTemplate: `原始内容：
{{note}}`,
  },
] satisfies PromptTemplate[];
