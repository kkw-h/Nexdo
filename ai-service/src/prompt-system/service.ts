import { ZodError } from 'zod';

import { getPromptTemplate } from './registry.js';
import { renderTemplate } from './renderer.js';
import type { PromptRenderRequest } from './types.js';

export class PromptTemplateNotFoundError extends Error {
  constructor(promptId: string) {
    super(`Prompt template not found: ${promptId}`);
    this.name = 'PromptTemplateNotFoundError';
  }
}

export class PromptTemplateValidationError extends Error {
  constructor(
    public readonly promptId: string,
    public readonly causeError: ZodError,
  ) {
    super(`Prompt variables are invalid for template: ${promptId}`);
    this.name = 'PromptTemplateValidationError';
  }
}

export function renderPromptTemplate(request: PromptRenderRequest) {
  const template = getPromptTemplate(request.promptId);

  if (!template) {
    throw new PromptTemplateNotFoundError(request.promptId);
  }

  const parsed = template.inputSchema.safeParse(request.variables);

  if (!parsed.success) {
    throw new PromptTemplateValidationError(request.promptId, parsed.error);
  }

  const variables = parsed.data;

  return {
    template: {
      id: template.id,
      name: template.name,
      version: template.version,
      description: template.description,
      tags: template.tags,
    },
    variables,
    system: renderTemplate(template.systemTemplate, variables),
    prompt: renderTemplate(template.userTemplate, variables),
  };
}
