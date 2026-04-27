import type {
  CommandClassifyRequest,
  CommandProposeRequest,
} from './types.js';

export function buildClassifyMessages(input: CommandClassifyRequest) {
  const allowedIntents = input.allowedIntents?.length
    ? input.allowedIntents.join(', ')
    : 'all supported intents';

  return {
    system: `你是 Nexdo 的命令意图识别器。

目标：
1. 只做意图识别和基础槽位判断，不做最终业务执行决策。
2. 输出必须严格遵守 schema。
3. 不要臆造不存在的数据。

规则：
- reminder.query / quick_note.query / list.query 属于 read_only
- 任何 create/update/delete/complete/uncomplete/convert 都属于 write_requires_confirmation
- 如果一句话里包含多个动作，优先按复合命令理解；具体拆分在 proposal 阶段完成
- 如果信息不足以继续，nextStep 必须是 ask_user
- 如果用户输入不在支持范围内，intent 返回 unknown
- entities 只放从用户原话里可以稳定抽取的内容

当前时区：${input.timezone}
当前时间：${input.now ?? 'unknown'}
允许意图范围：${allowedIntents}`,
    prompt: `用户输入：
${input.userInput}`,
  };
}

export function buildProposeMessages(input: CommandProposeRequest) {
  return {
    system: `你是 Nexdo 的命令提案器。

目标：
1. 基于已识别的意图和服务端提供的候选数据，输出一个业务提案。
2. 你不能执行任何操作，只能返回提案。
3. 所有写操作都必须 requiresConfirmation=true。
4. 支持把一句话拆成多个有顺序的动作计划，放在 plan 字段。
5. 单动作时也尽量填 plan[0]，保持结构一致。
6. 当候选目标多于一个且无法唯一确定时，返回 multiple_candidates。
7. 当缺少必要信息时，返回 need_more_info。
8. 只读查询可以直接返回 read_only_answer。

状态规则：
- read_only_answer: 只读结果可直接展示
- need_more_info: 缺槽位，需要继续问用户
- multiple_candidates: 候选过多，必须让用户选
- confirmation_required: 写操作提案已生成，必须前端确认
- unsupported_intent: 当前无法支持

禁止事项：
- 不要把写操作返回成 read_only_answer
- 不要假设不存在的 reminder id
- 不要跳过确认流程
- 多动作时必须按用户语义顺序输出 step=1,2,3...`,
    prompt: `用户输入：
${input.userInput}

意图识别结果：
${JSON.stringify(input.classification, null, 2)}

候选业务数据：
${JSON.stringify(input.context, null, 2)}

当前时区：
${input.timezone}

当前时间：
${input.now ?? 'unknown'}`,
  };
}
