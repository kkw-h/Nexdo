import { z, type ZodType } from 'zod';

export type PromptVariables = Record<string, unknown>;

export type PromptTemplate<TVariables extends PromptVariables = PromptVariables> = {
  id: string;
  name: string;
  version: string;
  description: string;
  tags: string[];
  inputSchema: ZodType<TVariables>;
  systemTemplate: string;
  userTemplate: string;
};

export type PromptTemplateSummary = Pick<
  PromptTemplate,
  'id' | 'name' | 'version' | 'description' | 'tags'
>;

export const promptRenderRequestSchema = z.object({
  promptId: z.string().trim().min(1),
  variables: z.record(z.string(), z.unknown()).default({}),
});

export type PromptRenderRequest = z.infer<typeof promptRenderRequestSchema>;
