import Anthropic from '@anthropic-ai/sdk';
import cors from 'cors';
import dotenv from 'dotenv';
import express from 'express';
import { performance } from 'node:perf_hooks';
import {
  buildBuddyUserMessage,
  BuddyExplainRequest,
  buildUserMessage,
  BUDDY_SYSTEM_PROMPT,
  ExplainRequest,
  SYSTEM_PROMPT,
} from './prompt.js';

dotenv.config();
dotenv.config({ path: '../.env', override: false });

const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? (process.env.PORT ? '0.0.0.0' : '127.0.0.1');
const apiKey = process.env.ANTHROPIC_API_KEY;
const model = process.env.ANTHROPIC_MODEL ?? 'claude-sonnet-4-6';
const nestedModel = process.env.ANTHROPIC_NESTED_MODEL ?? model;
// Buddy (hold-to-ask) sends a screenshot, so it needs a vision-capable model.
// Defaults to the main model (claude-sonnet-4-6 is vision-capable and strong on
// charts/diagrams) so we don't hardcode a separate, possibly-stale model string.
const visionModel = process.env.ANTHROPIC_VISION_MODEL ?? model;
const proxyToken = process.env.LEXI_PROXY_TOKEN;
const jsonBodyLimit = process.env.LEXI_JSON_BODY_LIMIT ?? '25mb';

const ALLOWED_IMAGE_MEDIA_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'] as const;
type AllowedImageMediaType = (typeof ALLOWED_IMAGE_MEDIA_TYPES)[number];

if (!apiKey) {
  console.warn('ANTHROPIC_API_KEY is not set. /explain will return 500 until it is configured.');
}

const anthropic = apiKey ? new Anthropic({ apiKey }) : undefined;
const app = express();

app.use(cors({ origin: false }));
// Buddy captures send a downscaled base64 screenshot, so the body can be a few
// hundred KB. Keep a generous-but-bounded limit to protect memory.
app.use(express.json({ limit: jsonBodyLimit }));
app.use((error: unknown, _req: express.Request, res: express.Response, next: express.NextFunction) => {
  if (numericProperty(error, 'status') === 413 || stringProperty(error, 'type') === 'entity.too.large') {
    res.status(413).json({ code: 'payload_too_large', error: 'That Buddy Capture image is too large. Try dragging a smaller region.' });
    return;
  }
  next(error);
});
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
    visionModel,
    jsonBodyLimit,
    anthropicApiKeyConfigured: Boolean(apiKey),
    proxyTokenConfigured: Boolean(proxyToken),
  });
});

app.post('/explain', async (req, res) => {
  const requestStartedAt = performance.now();
  const parsed = parseRequest(req.body);
  if (!parsed.ok) {
    res.status(400).json({ code: 'invalid_request', error: parsed.error });
    return;
  }
  const request = parsed.request;

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
  const termForLog = (request.kind === 'buddy' ? request.value.question || 'buddy capture' : request.value.term).slice(0, 60);
  const requestModel = request.kind === 'buddy' ? visionModel : request.value.lineage ? nestedModel : model;
  const maxTokens = request.kind === 'buddy' ? 240 : request.value.lineage ? 120 : 150;
  const systemBlocks = request.kind === 'buddy'
    ? [
        { type: 'text' as const, text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' as const } },
        { type: 'text' as const, text: BUDDY_SYSTEM_PROMPT },
      ]
    : [{ type: 'text' as const, text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' as const } }];
  const messageContent = request.kind === 'buddy'
    ? buildBuddyMessageContent(request)
    : buildUserMessage(request.value);

  sendEvent(res, 'meta', {
    model: requestModel,
    proxyAcceptedMs: elapsedMs(requestStartedAt),
  });

  try {
    const anthropicStartedAt = performance.now();
    const stream = await anthropic.messages.create({
      model: requestModel,
      max_tokens: maxTokens,
      temperature: 0.2,
      system: systemBlocks,
      messages: [
        {
          role: 'user',
          content: messageContent,
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
  | 'payload_too_large'
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

  if (status === 413 || rawMessage.includes('too large')) {
    return { code: 'payload_too_large', message: 'That Buddy Capture image is too large. Try dragging a smaller region.' };
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

type BuddyImage = { mediaType: AllowedImageMediaType; data: string };

type ParsedRequest =
  | { kind: 'text'; value: ExplainRequest }
  | { kind: 'buddy'; value: BuddyExplainRequest; image?: BuddyImage };

type RequestParseResult =
  | { ok: true; request: ParsedRequest }
  | { ok: false; error: string };

function parseRequest(body: unknown): RequestParseResult {
  if (!body || typeof body !== 'object') {
    return { ok: false, error: 'Expected JSON object.' };
  }

  if (stringField((body as Record<string, unknown>).mode) === 'buddy') {
    return parseBuddyRequest(body as Record<string, unknown>);
  }

  const textParse = parseExplainRequest(body);
  if (!textParse.ok) {
    return { ok: false, error: textParse.error };
  }
  return { ok: true, request: { kind: 'text', value: textParse.value } };
}

function parseBuddyRequest(value: Record<string, unknown>): RequestParseResult {
  const question = stringField(value.question).slice(0, 600);
  const windowTitle = stringField(value.windowTitle).slice(0, 240);
  const appName = stringField(value.appName).slice(0, 120);
  const image = parseImage(value.image, value.imageMediaType);

  if (!image && !question) {
    return { ok: false, error: 'A buddy capture needs an image, a spoken question, or both.' };
  }

  return {
    ok: true,
    request: {
      kind: 'buddy',
      value: { question, windowTitle, appName, hasImage: Boolean(image) },
      ...(image ? { image } : {}),
    },
  };
}

function parseImage(rawData: unknown, rawMediaType: unknown): BuddyImage | undefined {
  const raw = stringField(rawData);
  if (!raw) {
    return undefined;
  }

  // Accept either a bare base64 string or a full data URL.
  let base64 = raw;
  let mediaType = stringField(rawMediaType);
  const dataUrlMatch = /^data:(.+?);base64,(.*)$/s.exec(raw);
  if (dataUrlMatch) {
    mediaType = mediaType || dataUrlMatch[1];
    base64 = dataUrlMatch[2];
  }

  if (!base64) {
    return undefined;
  }

  const resolvedMediaType: AllowedImageMediaType = (ALLOWED_IMAGE_MEDIA_TYPES as readonly string[]).includes(mediaType)
    ? (mediaType as AllowedImageMediaType)
    : 'image/jpeg';

  return { mediaType: resolvedMediaType, data: base64 };
}

function buildBuddyMessageContent(request: { value: BuddyExplainRequest; image?: BuddyImage }): Anthropic.ContentBlockParam[] {
  const blocks: Anthropic.ContentBlockParam[] = [];
  if (request.image) {
    blocks.push({
      type: 'image',
      source: { type: 'base64', media_type: request.image.mediaType, data: request.image.data },
    });
  }
  blocks.push({ type: 'text', text: buildBuddyUserMessage(request.value) });
  return blocks;
}

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
