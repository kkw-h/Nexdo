import { generateObject, type LanguageModel } from 'ai';

import { buildClassifyMessages, buildProposeMessages } from './prompts.js';
import type {
  CommandClassifyRequest,
  CommandClassifyResult,
  CommandProposeRequest,
  CommandProposeResult,
} from './types.js';
import {
  commandClassifyResultSchema,
  commandProposeResultSchema,
} from './types.js';

export async function classifyCommand(
  model: LanguageModel,
  input: CommandClassifyRequest,
): Promise<CommandClassifyResult> {
  const messages = buildClassifyMessages(input);
  const result = await generateObject({
    model,
    schema: commandClassifyResultSchema,
    system: messages.system,
    prompt: messages.prompt,
  });

  return normalizeClassification(result.object);
}

export async function proposeCommand(
  model: LanguageModel,
  input: CommandProposeRequest,
): Promise<CommandProposeResult> {
  const messages = buildProposeMessages(input);
  const result = await generateObject({
    model,
    schema: commandProposeResultSchema,
    system: messages.system,
    prompt: messages.prompt,
  });

  return normalizeProposal(result.object);
}

function normalizeClassification(
  result: CommandClassifyResult,
): CommandClassifyResult {
  const operationType =
    result.intent === 'reminder.query' ||
    result.intent === 'quick_note.query' ||
    result.intent === 'list.query'
      ? 'read_only'
      : result.intent === 'unknown'
        ? result.operationType
        : 'write_requires_confirmation';

  const nextStep =
    result.intent === 'unknown'
      ? 'ask_user'
      : result.missingSlots.length > 0
        ? 'ask_user'
        : 'load_context';

  return {
    ...result,
    operationType,
    nextStep,
    clarificationQuestion:
      nextStep === 'ask_user'
        ? result.clarificationQuestion || '请补充更明确的目标或时间信息。'
        : null,
  };
}

function normalizeProposal(result: CommandProposeResult): CommandProposeResult {
  const normalizedPlan =
    result.plan.length > 0
      ? result.plan.map((step, index) => ({
          ...step,
          step: index + 1,
          summary: step.summary || step.reason,
        }))
      : result.proposal
        ? [
            {
              ...result.proposal,
              step: 1,
              summary: result.summary,
            },
          ]
        : [];

  if (result.operationType === 'write_requires_confirmation') {
    const status =
      result.status === 'need_more_info' ||
      result.status === 'multiple_candidates' ||
      result.status === 'unsupported_intent'
        ? result.status
        : 'confirmation_required';

    return {
      ...result,
      status,
      requiresConfirmation: status === 'confirmation_required',
      confirmationMessage:
        status === 'confirmation_required'
          ? result.confirmationMessage || result.summary
          : null,
      answer: null,
      plan: normalizedPlan,
      proposal: normalizedPlan.length > 0 ? normalizedPlan[0] : result.proposal,
    };
  }

  if (result.status === 'confirmation_required') {
    return {
      ...result,
      status: 'read_only_answer',
      requiresConfirmation: false,
      confirmationMessage: null,
      plan: normalizedPlan,
      proposal: normalizedPlan.length > 0 ? normalizedPlan[0] : result.proposal,
    };
  }

  return {
    ...result,
    requiresConfirmation: false,
    confirmationMessage: null,
    plan: normalizedPlan,
    proposal: normalizedPlan.length > 0 ? normalizedPlan[0] : result.proposal,
  };
}
