import Anthropic from '@anthropic-ai/sdk';
import cors from 'cors';
import dotenv from 'dotenv';
import express from 'express';
import { performance } from 'node:perf_hooks';
import {
  buildBuddyUserMessage,
  buildFollowUpUserMessage,
  BuddyExplainRequest,
  FollowUpExplainRequest,
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
const assemblyAIApiKey = process.env.ASSEMBLYAI_API_KEY;
const elevenLabsApiKey = process.env.ELEVENLABS_API_KEY;
const elevenLabsVoiceId = process.env.ELEVENLABS_VOICE_ID;
const perplexityApiKey = process.env.PERPLEXITY_API_KEY;
const researchProvider = process.env.LEXI_RESEARCH_PROVIDER ?? (perplexityApiKey ? 'perplexity' : 'none');
const researchMode = process.env.LEXI_RESEARCH_MODE ?? 'auto';
const perplexityModel = process.env.PERPLEXITY_MODEL ?? 'sonar-pro';
const perplexityEndpoint = process.env.PERPLEXITY_ENDPOINT ?? 'https://api.perplexity.ai/v1/sonar';

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
    assemblyAIConfigured: Boolean(assemblyAIApiKey),
    elevenLabsConfigured: Boolean(elevenLabsApiKey && elevenLabsVoiceId),
    perplexityConfigured: Boolean(perplexityApiKey),
    researchProvider,
    researchMode,
    perplexityModel,
  });
});

app.post('/transcribe-token', async (_req, res) => {
  if (!assemblyAIApiKey) {
    res.status(500).json({ code: 'assemblyai_misconfigured', error: 'ASSEMBLYAI_API_KEY is not configured on the proxy.' });
    return;
  }

  const response = await fetch('https://streaming.assemblyai.com/v3/token?expires_in_seconds=60&max_session_duration_seconds=600', {
    method: 'GET',
    headers: { authorization: assemblyAIApiKey },
  });
  const body = await response.text();
  res.status(response.status).type('application/json').send(body);
});

app.post('/tts', async (req, res) => {
  if (!elevenLabsApiKey || !elevenLabsVoiceId) {
    res.status(500).json({ code: 'tts_misconfigured', error: 'ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID are not configured on the proxy.' });
    return;
  }

  const text = stringField((req.body as Record<string, unknown>)?.text).slice(0, 2400);
  if (!text) {
    res.status(400).json({ code: 'invalid_request', error: 'text is required.' });
    return;
  }

  const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${elevenLabsVoiceId}`, {
    method: 'POST',
    headers: {
      'xi-api-key': elevenLabsApiKey,
      'content-type': 'application/json',
      accept: 'audio/mpeg',
    },
    body: JSON.stringify({
      text,
      model_id: stringField((req.body as Record<string, unknown>)?.model_id) || 'eleven_flash_v2_5',
      voice_settings: (req.body as Record<string, unknown>)?.voice_settings ?? { stability: 0.5, similarity_boost: 0.75 },
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    res.status(response.status).type('application/json').send(body);
    return;
  }

  res.status(response.status);
  res.setHeader('content-type', response.headers.get('content-type') ?? 'audio/mpeg');
  if (response.body) {
    for await (const chunk of response.body) {
      res.write(chunk);
    }
  }
  res.end();
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
  const termForLog = requestLabel(request).slice(0, 60);
  const requestModel = request.kind === 'buddy'
    ? visionModel
    : request.kind === 'followup' || (request.kind === 'text' && request.value.lineage)
      ? nestedModel
      : model;
  const maxTokens = request.kind === 'buddy' ? 800 : request.kind === 'followup' ? 600 : request.kind === 'text' && request.value.lineage ? 480 : 700;
  const systemBlocks = request.kind === 'buddy'
    ? [
        { type: 'text' as const, text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' as const } },
        { type: 'text' as const, text: BUDDY_SYSTEM_PROMPT },
      ]
    : [{ type: 'text' as const, text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' as const } }];
  const research = await maybeResearch(request);
  const messageContent = buildMessageContent(request, research);

  sendEvent(res, 'meta', {
    model: requestModel,
    proxyAcceptedMs: elapsedMs(requestStartedAt),
    researchProvider: research?.provider,
    researchUsed: Boolean(research),
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
  | { kind: 'followup'; value: FollowUpExplainRequest }
  | { kind: 'buddy'; value: BuddyExplainRequest; image?: BuddyImage };

type ResearchResult = {
  provider: 'perplexity';
  context: string;
};

type RequestParseResult =
  | { ok: true; request: ParsedRequest }
  | { ok: false; error: string };

function parseRequest(body: unknown): RequestParseResult {
  if (!body || typeof body !== 'object') {
    return { ok: false, error: 'Expected JSON object.' };
  }

  const mode = stringField((body as Record<string, unknown>).mode);
  if (mode === 'buddy') {
    return parseBuddyRequest(body as Record<string, unknown>);
  }
  if (mode === 'followup') {
    return parseFollowUpRequest(body as Record<string, unknown>);
  }

  const textParse = parseExplainRequest(body);
  if (!textParse.ok) {
    return { ok: false, error: textParse.error };
  }
  return { ok: true, request: { kind: 'text', value: textParse.value } };
}

function parseFollowUpRequest(value: Record<string, unknown>): RequestParseResult {
  const question = stringField(value.question).slice(0, 600);
  const windowTitle = stringField(value.windowTitle).slice(0, 240);
  const appName = stringField(value.appName).slice(0, 120);
  const sessionContext = stringField(value.sessionContext).slice(0, 1600);
  const lineage = parseLineage(value.lineage);

  if (!question || !lineage) {
    return { ok: false, error: 'A follow-up needs a question and parent answer context.' };
  }

  return {
    ok: true,
    request: {
      kind: 'followup',
      value: {
        question,
        rootTerm: lineage.rootTerm,
        rootSourceText: lineage.rootSourceText,
        parentTerm: lineage.parentTerm,
        parentAnswer: lineage.parentAnswer,
        depth: lineage.depth,
        windowTitle,
        appName,
        ...(sessionContext ? { sessionContext } : {}),
      },
    },
  };
}

function parseBuddyRequest(value: Record<string, unknown>): RequestParseResult {
  const question = stringField(value.question).slice(0, 600);
  const windowTitle = stringField(value.windowTitle).slice(0, 240);
  const appName = stringField(value.appName).slice(0, 120);
  const ocrText = stringField(value.ocrText).slice(0, 2400);
  const sessionContext = stringField(value.sessionContext).slice(0, 1600);
  const image = parseImage(value.image, value.imageMediaType);

  if (!image && !question) {
    return { ok: false, error: 'A buddy capture needs an image, a spoken question, or both.' };
  }

  return {
    ok: true,
    request: {
      kind: 'buddy',
      value: {
        question,
        windowTitle,
        appName,
        hasImage: Boolean(image),
        ...(ocrText ? { ocrText } : {}),
        ...(sessionContext ? { sessionContext } : {}),
      },
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

async function maybeResearch(request: ParsedRequest): Promise<ResearchResult | undefined> {
  if (!shouldUseResearch(request)) {
    return undefined;
  }

  const query = buildResearchQuery(request.value);
  const startedAt = performance.now();
  try {
    const response = await fetch(perplexityEndpoint, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${perplexityApiKey}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: perplexityModel,
        messages: [
          {
            role: 'system',
            content: 'You are Lexi Research, a source-grounded research agent. Find exact definitions, current facts, names, organizations, products, and niche terms. Prefer authoritative or primary sources. If the term is ambiguous, say so and separate meanings.',
          },
          { role: 'user', content: query },
        ],
        max_tokens: 900,
        temperature: 0.1,
        search_mode: 'web',
        return_related_questions: false,
      }),
    });

    if (!response.ok) {
      console.warn(`Lexi research skipped: Perplexity returned HTTP ${response.status}`);
      return undefined;
    }

    const payload = await response.json() as { choices?: Array<{ message?: { content?: string } }>; citations?: unknown };
    const content = stringField(payload.choices?.[0]?.message?.content).slice(0, 4200);
    if (!content) {
      return undefined;
    }
    const citations = Array.isArray(payload.citations)
      ? payload.citations.map((citation) => stringField(citation)).filter(Boolean).slice(0, 8)
      : [];
    const context = [
      `Provider: Perplexity ${perplexityModel}`,
      `Research answer:\n${content}`,
      citations.length ? `Sources:\n${citations.map((citation, index) => `${index + 1}. ${citation}`).join('\n')}` : '',
    ].filter(Boolean).join('\n\n').slice(0, 5200);
    console.log(`Lexi research done term="${requestLabel(request).slice(0, 60)}" provider=perplexity ms=${elapsedMs(startedAt)}`);
    return { provider: 'perplexity', context };
  } catch (error) {
    console.warn('Lexi research skipped: Perplexity request failed', error);
    return undefined;
  }
}

function shouldUseResearch(request: ParsedRequest): request is { kind: 'text'; value: ExplainRequest } {
  if (researchMode === 'off' || researchProvider !== 'perplexity' || !perplexityApiKey) {
    return false;
  }
  if (request.kind !== 'text' || request.value.lineage) {
    return false;
  }
  if (researchMode === 'always') {
    return true;
  }

  const term = request.value.term.trim();
  if (!term) {
    return false;
  }
  if (request.value.question || !request.value.passage) {
    return true;
  }
  if (/[-/0-9]/.test(term) || /\s/.test(term)) {
    return true;
  }
  if (/^[A-Z0-9]{2,}$/.test(term) || /[A-Z]/.test(term.slice(1))) {
    return true;
  }
  return term.length > 14;
}

function buildResearchQuery(input: ExplainRequest): string {
  return `Research the highlighted term for Lexi. Return source-grounded facts that help answer accurately.

TERM: ${input.term}
PASSAGE: ${input.passage || '(none)'}
WINDOW TITLE: ${input.windowTitle || '(unknown)'}
APP: ${input.appName || '(unknown)'}
READER QUESTION: ${input.question || '(none)'}

Focus on exact definition, specific entity/name identification, current factual context, and ambiguity. Keep it concise but cite/source the claims.`;
}

function requestLabel(request: ParsedRequest): string {
  switch (request.kind) {
    case 'buddy':
      return request.value.question || 'buddy capture';
    case 'followup':
      return request.value.question;
    case 'text':
      return request.value.term;
  }
}

function buildMessageContent(request: ParsedRequest, research?: ResearchResult): Anthropic.ContentBlockParam[] | string {
  switch (request.kind) {
    case 'buddy':
      return buildBuddyMessageContent(request);
    case 'followup':
      return buildFollowUpUserMessage(request.value);
    case 'text':
      return buildUserMessage({ ...request.value, ...(research ? { researchContext: research.context } : {}) });
  }
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
  const question = stringField(value.question).slice(0, 600);
  const sessionContext = stringField(value.sessionContext).slice(0, 1600);
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
      ...(question ? { question } : {}),
      ...(sessionContext ? { sessionContext } : {}),
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
