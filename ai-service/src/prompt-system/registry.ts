import { promptTemplates } from './templates.js';
import type { PromptTemplate, PromptTemplateSummary } from './types.js';

const promptTemplateMap = new Map<string, PromptTemplate>(
  promptTemplates.map((template) => [template.id, template]),
);

export function listPromptTemplates(): PromptTemplateSummary[] {
  return promptTemplates.map(({ id, name, version, description, tags }) => ({
    id,
    name,
    version,
    description,
    tags,
  }));
}

export function getPromptTemplate(promptId: string): PromptTemplate | undefined {
  return promptTemplateMap.get(promptId);
}
