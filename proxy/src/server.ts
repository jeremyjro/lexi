import Anthropic from '@anthropic-ai/sdk';
import cors from 'cors';
import dotenv from 'dotenv';
import express from 'express';
import { performance } from 'node:perf_hooks';
import { buildUserMessage, ExplainRequest, SYSTEM_PROMPT } from './prompt.js';

dotenv.config();
dotenv.config({ path: '../.env', override: false });

const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? (process.env.PORT ? '0.0.0.0' : '127.0.0.1');
const apiKey = process.env.ANTHROPIC_API_KEY;
const model = process.env.ANTHROPIC_MODEL ?? 'claude-sonnet-4-6';
const nestedModel = process.env.ANTHROPIC_NESTED_MODEL ?? model;
const proxyToken = process.env.LEXI_PROXY_TOKEN;

if (!apiKey) {
  console.warn('ANTHROPIC_API_KEY is not set. /explain will return 500 until it is configured.');
}

const anthropic = apiKey ? new Anthropic({ apiKey }) : undefined;
const app = express();

app.use(cors({ origin: false }));
app.use(express.json({ limit: '32kb' }));
app.use((req, res, next) => {
  if (!proxyToken || req.path === '/health') {
    next();
    return;
  }

  const authorization = req.header('authorization') ?? '';
  const expected = `Bearer ${proxyToken}`;
  if (authorization !== expected) {
    res.status(401).json({ code: 'unauthorized', error: 'Unauthorized Lexi proxy request.' });
    return;
  }

  next();
});

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    model,
    nestedModel,
    anthropicApiKeyConfigured: Boolean(apiKey),
    proxyTokenConfigured: Boolean(proxyToken),
  });
});

app.post('/explain', async (req, res) => {
  const requestStartedAt = performance.now();
  const parsed = parseExplainRequest(req.body);
  if (!parsed.ok) {
    res.status(400).json({ code: 'invalid_request', error: parsed.error });
    return;
  }

  if (!anthropic) {
    res.status(500).json({ code: 'assistant_misconfigured', error: 'ANTHROPIC_API_KEY is not configured on the proxy.' });
    return;
  }

  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive',
    'X-Accel-Buffering': 'no',
  });
  res.flushHeaders?.();

  let firstDeltaAt: number | undefined;
  let outputCharacters = 0;
  const termForLog = parsed.value.term.slice(0, 60);
  const requestModel = parsed.value.lineage ? nestedModel : model;

  sendEvent(res, 'meta', {
    model: requestModel,
    proxyAcceptedMs: elapsedMs(requestStartedAt),
  });

  try {
    const anthropicStartedAt = performance.now();
    const stream = await anthropic.messages.create({
      model: requestModel,
      max_tokens: parsed.value.lineage ? 120 : 150,
      temperature: 0.2,
      system: [
        {
          type: 'text',
          text: SYSTEM_PROMPT,
          cache_control: { type: 'ephemeral' },
        },
      ],
      messages: [
        {
          role: 'user',
          content: buildUserMessage(parsed.value),
        },
      ],
      stream: true,
    });

    for await (const event of stream) {
      if (event.type !== 'content_block_delta' || event.delta.type !== 'text_delta') {
        continue;
      }

      if (firstDeltaAt === undefined) {
        firstDeltaAt = performance.now();
        const timing = {
          proxyTtftMs: elapsedMs(requestStartedAt),
          anthropicTtftMs: elapsedMs(anthropicStartedAt),
        };
        console.log(
          `Lexi /explain first token term="${termForLog}" proxyTtft=${timing.proxyTtftMs}ms anthropicTtft=${timing.anthropicTtftMs}ms`,
        );
        sendEvent(res, 'timing', timing);
      }

      outputCharacters += event.delta.text.length;
      sendEvent(res, 'delta', { text: event.delta.text });
    }

    const doneTiming = {
      totalMs: elapsedMs(requestStartedAt),
      outputCharacters,
    };
    console.log(`Lexi /explain done term="${termForLog}" total=${doneTiming.totalMs}ms chars=${outputCharacters}`);
    sendEvent(res, 'done', doneTiming);
    res.end();
  } catch (error) {
    const proxyError = classifyAssistantError(error);
    console.error('Anthropic /explain stream failed:', proxyError.code, error);
    sendEvent(res, 'error', proxyError);
    res.end();
  }
});

app.listen(port, host, () => {
  console.log(`Lexi proxy listening on http://${host}:${port}`);
});

type ProxyErrorCode =
  | 'assistant_auth_failed'
  | 'assistant_rate_limited'
  | 'assistant_model_unavailable'
  | 'assistant_overloaded'
  | 'assistant_unavailable';

type ProxyError = {
  code: ProxyErrorCode;
  message: string;
};

function classifyAssistantError(error: unknown): ProxyError {
  const status = numericProperty(error, 'status');
  const rawMessage = stringProperty(error, 'message').toLowerCase();

  if (status === 401 || status === 403) {
    return { code: 'assistant_auth_failed', message: 'The assistant API key was rejected. Check the Anthropic key in Railway.' };
  }

  if (status === 404 || rawMessage.includes('model')) {
    return { code: 'assistant_model_unavailable', message: 'The configured assistant model is unavailable. Check ANTHROPIC_MODEL in Railway.' };
  }

  if (status === 429 || rawMessage.includes('rate')) {
    return { code: 'assistant_rate_limited', message: 'The assistant is rate limited. Try again shortly.' };
  }

  if (status === 529 || rawMessage.includes('overloaded')) {
    return { code: 'assistant_overloaded', message: 'The assistant is overloaded. Try again shortly.' };
  }

  return { code: 'assistant_unavailable', message: "Couldn't reach the assistant. Check Railway logs if this keeps happening." };
}

function numericProperty(value: unknown, key: string): number | undefined {
  if (!value || typeof value !== 'object' || !(key in value)) {
    return undefined;
  }
  const property = (value as Record<string, unknown>)[key];
  return typeof property === 'number' ? property : undefined;
}

function stringProperty(value: unknown, key: string): string {
  if (!value || typeof value !== 'object' || !(key in value)) {
    return '';
  }
  const property = (value as Record<string, unknown>)[key];
  return typeof property === 'string' ? property : '';
}

type ParseResult =
  | { ok: true; value: ExplainRequest }
  | { ok: false; error: string };

function parseExplainRequest(body: unknown): ParseResult {
  if (!body || typeof body !== 'object') {
    return { ok: false, error: 'Expected JSON object.' };
  }

  const value = body as Record<string, unknown>;
  const term = stringField(value.term).slice(0, 240);
  const passage = stringField(value.passage).slice(0, 1200);
  const windowTitle = stringField(value.windowTitle).slice(0, 240);
  const appName = stringField(value.appName).slice(0, 120);
  const lineage = parseLineage(value.lineage);

  if (!term) {
    return { ok: false, error: 'term is required.' };
  }

  return {
    ok: true,
    value: {
      term,
      passage,
      windowTitle,
      appName,
      ...(lineage ? { lineage } : {}),
    },
  };
}

function parseLineage(value: unknown): ExplainRequest['lineage'] | undefined {
  if (!value || typeof value !== 'object') {
    return undefined;
  }

  const lineage = value as Record<string, unknown>;
  const rootTerm = stringField(lineage.rootTerm).slice(0, 240);
  const rootSourceText = stringField(lineage.rootSourceText).slice(0, 1000);
  const parentTerm = stringField(lineage.parentTerm).slice(0, 240);
  const parentAnswer = stringField(lineage.parentAnswer).slice(0, 1600);
  const depth = numberField(lineage.depth);

  if (!rootTerm || !parentAnswer) {
    return undefined;
  }

  return {
    rootTerm,
    rootSourceText,
    parentTerm,
    parentAnswer,
    depth,
  };
}

function stringField(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function numberField(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, Math.round(value)) : 0;
}

function sendEvent(res: express.Response, event: string, data: unknown) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(data)}\n\n`);
}

function elapsedMs(startedAt: number): number {
  return Math.round(performance.now() - startedAt);
}
