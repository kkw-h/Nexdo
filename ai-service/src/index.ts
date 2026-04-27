import { createOpenAI } from '@ai-sdk/openai';
import dotenv from 'dotenv';
import express, { type Response } from 'express';
import { generateText } from 'ai';
import { z } from 'zod';

import {
  classifyCommand,
  proposeCommand,
} from './command-system/service.js';
import {
  commandClassifyRequestSchema,
  commandProposeRequestSchema,
  supportedIntentValues,
} from './command-system/types.js';
import { listPromptTemplates } from './prompt-system/registry.js';
import {
  PromptTemplateNotFoundError,
  PromptTemplateValidationError,
  renderPromptTemplate,
} from './prompt-system/service.js';
import { promptRenderRequestSchema } from './prompt-system/types.js';

dotenv.config({ override: true });

const app = express();
app.use(express.json());

const testRequestSchema = z
  .object({
    prompt: z.string().trim().min(1).max(4000).optional(),
    system: z.string().trim().max(4000).optional(),
    promptId: z.string().trim().min(1).optional(),
    variables: z.record(z.string(), z.unknown()).optional(),
  })
  .refine((value) => Boolean(value.prompt || value.promptId), {
    message: 'Either prompt or promptId is required.',
    path: ['prompt'],
  });

const port = Number(process.env.PORT || 3030);
const baseURL = process.env.OPENAI_BASE_URL;
const apiKey = process.env.OPENAI_API_KEY;
const wireApi = process.env.OPENAI_WIRE_API || 'responses';
const testModel = process.env.OPENAI_MODEL || 'gpt-4.1-mini';

const openai = createOpenAI({
  name: 'cliproxyapi',
  baseURL,
  apiKey,
});

const commandModel =
  wireApi === 'responses' ? openai.responses(testModel) : openai(testModel);

function ensureModelConfig(res: Response): boolean {
  if (!apiKey || !baseURL) {
    res.status(500).json({
      ok: false,
      error: 'missing_openai_config',
      message:
        'Set OPENAI_API_KEY and OPENAI_BASE_URL in ai-service/.env before calling this endpoint.',
    });
    return false;
  }

  return true;
}

function handlePromptError(error: unknown, res: Response): boolean {
  if (error instanceof PromptTemplateNotFoundError) {
    res.status(404).json({
      ok: false,
      error: 'prompt_not_found',
      message: error.message,
    });
    return true;
  }

  if (error instanceof PromptTemplateValidationError) {
    res.status(400).json({
      ok: false,
      error: 'invalid_prompt_variables',
      promptId: error.promptId,
      details: error.causeError.flatten(),
    });
    return true;
  }

  return false;
}

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'nexdo-ai-service',
    provider: 'cliproxyapi',
    baseURL,
    wireApi,
    model: testModel,
    promptTemplateCount: listPromptTemplates().length,
    supportedCommandIntents: supportedIntentValues,
  });
});

app.get('/api/commands/intents', (_req, res) => {
  res.json({
    ok: true,
    intents: supportedIntentValues,
    rules: {
      writeOperationsRequireConfirmation: true,
    },
  });
});

app.post('/api/commands/classify', async (req, res) => {
  if (!ensureModelConfig(res)) {
    return;
  }

  const parsed = commandClassifyRequestSchema.safeParse(req.body);

  if (!parsed.success) {
    res.status(400).json({
      ok: false,
      error: 'invalid_request',
      details: parsed.error.flatten(),
    });
    return;
  }

  try {
    const classification = await classifyCommand(commandModel, parsed.data);
    res.json({
      ok: true,
      classification,
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : 'Unknown command classify error';
    res.status(500).json({
      ok: false,
      error: 'command_classify_failed',
      message,
    });
  }
});

app.post('/api/commands/propose', async (req, res) => {
  if (!ensureModelConfig(res)) {
    return;
  }

  const parsed = commandProposeRequestSchema.safeParse(req.body);

  if (!parsed.success) {
    res.status(400).json({
      ok: false,
      error: 'invalid_request',
      details: parsed.error.flatten(),
    });
    return;
  }

  try {
    const proposal = await proposeCommand(commandModel, parsed.data);
    res.json({
      ok: true,
      proposal,
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : 'Unknown command propose error';
    res.status(500).json({
      ok: false,
      error: 'command_propose_failed',
      message,
    });
  }
});

app.get('/api/prompts', (_req, res) => {
  res.json({
    ok: true,
    prompts: listPromptTemplates(),
  });
});

app.post('/api/prompts/render', (req, res) => {
  const parsed = promptRenderRequestSchema.safeParse(req.body);

  if (!parsed.success) {
    res.status(400).json({
      ok: false,
      error: 'invalid_request',
      details: parsed.error.flatten(),
    });
    return;
  }

  try {
    const rendered = renderPromptTemplate(parsed.data);
    res.json({
      ok: true,
      ...rendered,
    });
  } catch (error) {
    if (handlePromptError(error, res)) {
      return;
    }

    const message =
      error instanceof Error ? error.message : 'Unknown prompt render error';
    res.status(500).json({
      ok: false,
      error: 'prompt_render_failed',
      message,
    });
  }
});

app.post('/api/test', async (req, res) => {
  const parsed = testRequestSchema.safeParse(req.body);

  if (!parsed.success) {
    res.status(400).json({
      ok: false,
      error: 'invalid_request',
      details: parsed.error.flatten(),
    });
    return;
  }

  if (!ensureModelConfig(res)) {
    return;
  }

  try {
    const rendered = parsed.data.promptId
      ? renderPromptTemplate({
          promptId: parsed.data.promptId,
          variables: parsed.data.variables ?? {},
        })
      : {
          template: null,
          variables: parsed.data.variables ?? {},
          system:
            parsed.data.system ||
            'You are the Nexdo AI test endpoint. Reply briefly and clearly.',
          prompt: parsed.data.prompt ?? '',
        };

    const result = await generateText({
      model: commandModel,
      system: rendered.system,
      prompt: rendered.prompt,
    });

    const providerMetadata = result.providerMetadata as
      | Record<string, Record<string, unknown>>
      | undefined;

    res.json({
      ok: true,
      model: testModel,
      provider: 'cliproxyapi',
      wireApi,
      template: rendered.template,
      renderedPrompt: {
        system: rendered.system,
        prompt: rendered.prompt,
      },
      text: result.text,
      usage: result.usage,
      response: {
        id: result.response.id,
        timestamp: result.response.timestamp,
        providerResponseId:
          typeof providerMetadata?.openai?.responseId === 'string'
            ? providerMetadata.openai.responseId
            : null,
      },
    });
  } catch (error) {
    if (handlePromptError(error, res)) {
      return;
    }

    const message = error instanceof Error ? error.message : 'Unknown AI SDK error';
    res.status(500).json({
      ok: false,
      error: 'ai_request_failed',
      message,
    });
  }
});

app.listen(port, () => {
  console.log(`Nexdo AI service listening on http://localhost:${port}`);
});
