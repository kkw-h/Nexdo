import { z } from 'zod';

export const supportedIntentValues = [
  'reminder.query',
  'reminder.create',
  'reminder.update',
  'reminder.delete',
  'reminder.complete',
  'reminder.uncomplete',
  'quick_note.convert',
  'quick_note.query',
  'list.query',
  'unknown',
] as const;

export const supportedActionValues = [
  'none',
  'query_reminders',
  'create_reminder',
  'update_reminder',
  'delete_reminder',
  'complete_reminder',
  'uncomplete_reminder',
  'convert_quick_note',
  'query_quick_notes',
  'query_lists',
] as const;

export const supportedIntentSchema = z.enum(supportedIntentValues);
export const supportedActionSchema = z.enum(supportedActionValues);
export const operationTypeSchema = z.enum([
  'read_only',
  'write_requires_confirmation',
]);
export const commandStatusSchema = z.enum([
  'read_only_answer',
  'need_more_info',
  'multiple_candidates',
  'confirmation_required',
  'unsupported_intent',
]);
export const targetTypeSchema = z.enum([
  'none',
  'reminder',
  'quick_note',
  'list',
  'group',
  'tag',
]);
export const riskLevelSchema = z.enum(['low', 'medium', 'high']);

export const reminderCandidateSchema = z.object({
  id: z.string().trim().min(1),
  title: z.string().trim().min(1).max(200),
  dueAt: z.string().trim().max(100).nullable().optional(),
  note: z.string().trim().max(2000).nullable().optional(),
  completed: z.boolean().optional(),
  listName: z.string().trim().max(200).nullable().optional(),
  groupName: z.string().trim().max(200).nullable().optional(),
  tags: z.array(z.string().trim().max(100)).optional(),
  aliases: z.array(z.string().trim().max(100)).optional(),
});

export const quickNoteCandidateSchema = z.object({
  id: z.string().trim().min(1),
  content: z.string().trim().min(1).max(4000),
  createdAt: z.string().trim().max(100).nullable().optional(),
});

export const resourceCandidateSchema = z.object({
  id: z.string().trim().min(1),
  name: z.string().trim().min(1).max(200),
});

export const candidateSummarySchema = z.object({
  id: z.string().trim().min(1),
  title: z.string().trim().min(1).max(200),
  reason: z.string().trim().min(1).max(500),
});

export const commandClassifyRequestSchema = z.object({
  userInput: z.string().trim().min(1).max(4000),
  timezone: z.string().trim().max(100).default('Asia/Shanghai'),
  now: z.string().trim().max(100).optional(),
  allowedIntents: z.array(supportedIntentSchema).optional(),
});

export const commandClassifyResultSchema = z.object({
  intent: supportedIntentSchema,
  operationType: operationTypeSchema,
  confidence: z.number().min(0).max(1),
  summary: z.string().trim().min(1).max(500),
  missingSlots: z.array(z.string().trim().min(1).max(100)).default([]),
  entities: z.record(z.string(), z.unknown()).default({}),
  nextStep: z.enum(['answer_directly', 'load_context', 'ask_user']),
  clarificationQuestion: z.string().trim().max(500).nullable().default(null),
});

export const commandContextSchema = z.object({
  reminders: z.array(reminderCandidateSchema).default([]),
  quickNotes: z.array(quickNoteCandidateSchema).default([]),
  lists: z.array(resourceCandidateSchema).default([]),
  groups: z.array(resourceCandidateSchema).default([]),
  tags: z.array(resourceCandidateSchema).default([]),
});

export const commandProposeRequestSchema = z.object({
  userInput: z.string().trim().min(1).max(4000),
  classification: commandClassifyResultSchema,
  timezone: z.string().trim().max(100).default('Asia/Shanghai'),
  now: z.string().trim().max(100).optional(),
  context: commandContextSchema.default({
    reminders: [],
    quickNotes: [],
    lists: [],
    groups: [],
    tags: [],
  }),
});

export const commandProposalSchema = z.object({
  action: supportedActionSchema,
  targetType: targetTypeSchema,
  targetIds: z.array(z.string().trim().min(1)).default([]),
  patch: z.record(z.string(), z.unknown()).default({}),
  reason: z.string().trim().min(1).max(800),
  riskLevel: riskLevelSchema,
});

export const commandPlanStepSchema = commandProposalSchema.extend({
  step: z.number().int().min(1),
  summary: z.string().trim().min(1).max(300).default(''),
});

export const commandProposeResultSchema = z.object({
  status: commandStatusSchema,
  intent: supportedIntentSchema,
  operationType: operationTypeSchema,
  requiresConfirmation: z.boolean(),
  summary: z.string().trim().min(1).max(500),
  userMessage: z.string().trim().min(1).max(1000),
  missingSlots: z.array(z.string().trim().min(1).max(100)).default([]),
  answer: z.string().trim().max(2000).nullable().default(null),
  clarificationQuestion: z.string().trim().max(500).nullable().default(null),
  confirmationMessage: z.string().trim().max(500).nullable().default(null),
  proposal: commandProposalSchema.nullable().default(null),
  plan: z.array(commandPlanStepSchema).default([]),
  candidates: z.array(candidateSummarySchema).default([]),
});

export type CommandClassifyRequest = z.infer<typeof commandClassifyRequestSchema>;
export type CommandClassifyResult = z.infer<typeof commandClassifyResultSchema>;
export type CommandProposeRequest = z.infer<typeof commandProposeRequestSchema>;
export type CommandProposeResult = z.infer<typeof commandProposeResultSchema>;
