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
const model = process.env.ANTHROPIC_MODEL ?? 'claude-haiku-4-5-20251001';
const proxyToken = process.env.LEXI_PROXY_TOKEN;

if (!apiKey) {
  console.warn('ANTHROPIC_API_KEY is not set. /explain will return 500 until it is configured.');
}

const anthropic = new Anthropic({ apiKey });
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
    res.status(401).json({ error: 'Unauthorized Lexi proxy request.' });
    return;
  }

  next();
});

app.get('/health', (_req, res) => {
  res.json({ ok: true, model });
});

app.post('/explain', async (req, res) => {
  const requestStartedAt = performance.now();
  const parsed = parseExplainRequest(req.body);
  if (!parsed.ok) {
    res.status(400).json({ error: parsed.error });
    return;
  }

  if (!apiKey) {
    res.status(500).json({ error: 'ANTHROPIC_API_KEY is not configured on the proxy.' });
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

  sendEvent(res, 'meta', {
    model,
    proxyAcceptedMs: elapsedMs(requestStartedAt),
  });

  try {
    const anthropicStartedAt = performance.now();
    const stream = await anthropic.messages.create({
      model,
      max_tokens: 150,
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
    console.error('Anthropic /explain stream failed:', error);
    sendEvent(res, 'error', { message: "Couldn't reach the assistant — try again." });
    res.end();
  }
});

app.listen(port, host, () => {
  console.log(`Lexi proxy listening on http://${host}:${port}`);
});

type ParseResult =
  | { ok: true; value: ExplainRequest }
  | { ok: false; error: string };

function parseExplainRequest(body: unknown): ParseResult {
  if (!body || typeof body !== 'object') {
    return { ok: false, error: 'Expected JSON object.' };
  }

  const value = body as Partial<Record<keyof ExplainRequest, unknown>>;
  const term = stringField(value.term).slice(0, 240);
  const passage = stringField(value.passage).slice(0, 1200);
  const windowTitle = stringField(value.windowTitle).slice(0, 240);
  const appName = stringField(value.appName).slice(0, 120);

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
    },
  };
}

function stringField(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function sendEvent(res: express.Response, event: string, data: unknown) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(data)}\n\n`);
}

function elapsedMs(startedAt: number): number {
  return Math.round(performance.now() - startedAt);
}
