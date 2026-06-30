import Anthropic from '@anthropic-ai/sdk';
import cors from 'cors';
import dotenv from 'dotenv';
import express from 'express';
import { performance } from 'node:perf_hooks';
import {
  buildBuddyUserMessage,
  buildComposeUserMessage,
  buildFollowUpUserMessage,
  BuddyExplainRequest,
  ComposeRequest,
  FollowUpExplainRequest,
  buildUserMessage,
  BUDDY_SYSTEM_PROMPT,
  COMPOSE_SYSTEM_PROMPT,
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
const assemblyAITokenTimeoutMs = Math.max(1000, Math.min(10000, Number(process.env.ASSEMBLYAI_TOKEN_TIMEOUT_MS ?? 4000)));
const elevenLabsApiKey = process.env.ELEVENLABS_API_KEY;
const elevenLabsVoiceId = process.env.ELEVENLABS_VOICE_ID;
const perplexityApiKey = process.env.PERPLEXITY_API_KEY;
const researchProvider = process.env.LEXI_RESEARCH_PROVIDER ?? (perplexityApiKey ? 'perplexity' : 'none');
const researchMode = process.env.LEXI_RESEARCH_MODE ?? 'auto';
const perplexityModel = process.env.PERPLEXITY_MODEL ?? 'sonar-pro';
const perplexityEndpoint = process.env.PERPLEXITY_ENDPOINT ?? 'https://api.perplexity.ai/chat/completions';
const RESEARCH_SYSTEM_PROMPT =
  'You are Lexi Research, a source-grounded research agent. Identify exactly what the reader is asking about — the specific company, product, person, organization, or niche term — and return current, factual, source-backed information. Lead with what the entity actually is and the key concrete facts (real name, what it does, who is behind it, current status, important numbers or dates). Prefer authoritative or primary sources. If the subject is ambiguous, give the most likely identification and briefly note alternatives. Be concise; do not hedge.';

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
    assemblyAITokenTimeoutMs,
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

  const startedAt = performance.now();
  try {
    const response = await fetch('https://streaming.assemblyai.com/v3/token?expires_in_seconds=60&max_session_duration_seconds=600', {
      method: 'GET',
      headers: { authorization: assemblyAIApiKey },
      signal: AbortSignal.timeout(assemblyAITokenTimeoutMs),
    });
    const body = await response.text();
    console.log(`Lexi transcribe-token status=${response.status} total=${Math.round(performance.now() - startedAt)}ms`);
    res.status(response.status).type('application/json').send(body);
  } catch (error) {
    console.warn(`Lexi transcribe-token failed total=${Math.round(performance.now() - startedAt)}ms`, error);
    res.status(504).json({ code: 'assemblyai_token_timeout', error: 'AssemblyAI token request timed out.' });
  }
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
  const researchIntent = planResearch(request);
  const plan = buildInferencePlan(request, researchIntent);
  const systemBlocks = request.kind === 'buddy'
    ? [
        { type: 'text' as const, text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' as const } },
        { type: 'text' as const, text: BUDDY_SYSTEM_PROMPT },
      ]
    : [{ type: 'text' as const, text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' as const } }];

  sendEvent(res, 'meta', {
    model: plan.model,
    maxTokens: plan.maxTokens,
    route: plan.route,
    latencyTier: plan.latencyTier,
    researchPolicy: plan.researchPolicy,
    researchPending: plan.researchPolicy !== 'off',
    researchUsed: false,
    proxyAcceptedMs: elapsedMs(requestStartedAt),
  });

  const research = await maybeResearch(request, plan, researchIntent);
  const messageContent = buildMessageContent(request, research);

  if (research) {
    sendEvent(res, 'meta', {
      model: plan.model,
      maxTokens: plan.maxTokens,
      route: plan.route,
      latencyTier: plan.latencyTier,
      researchPolicy: plan.researchPolicy,
      researchProvider: research.provider,
      researchMs: research.elapsedMs,
      researchUsed: true,
      proxyAcceptedMs: elapsedMs(requestStartedAt),
    });
  }

  try {
    const anthropicStartedAt = performance.now();
    const stream = await anthropic.messages.create({
      model: plan.model,
      max_tokens: plan.maxTokens,
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
      route: plan.route,
      latencyTier: plan.latencyTier,
      researchUsed: Boolean(research),
      researchProvider: research?.provider,
      researchMs: research?.elapsedMs,
    };
    console.log(`Lexi /explain done term="${termForLog}" route=${plan.route} research=${Boolean(research)} total=${doneTiming.totalMs}ms chars=${outputCharacters}`);
    sendEvent(res, 'done', doneTiming);
    res.end();
  } catch (error) {
    const proxyError = classifyAssistantError(error);
    console.error('Anthropic /explain stream failed:', proxyError.code, error);
    sendEvent(res, 'error', proxyError);
    res.end();
  }
});

app.post('/compose', async (req, res) => {
  const requestStartedAt = performance.now();
  const parsed = parseComposeRequest(req.body);
  if (!parsed.ok) {
    res.status(400).json({ code: 'invalid_request', error: parsed.error });
    return;
  }

  if (!anthropic) {
    res.status(500).json({ code: 'assistant_misconfigured', error: 'ANTHROPIC_API_KEY is not configured on the proxy.' });
    return;
  }

  const request = parsed.value;
  const requestModel = model;
  const maxTokens = 1800;
  const route = 'active_composition';
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive',
    'X-Accel-Buffering': 'no',
  });
  res.flushHeaders?.();

  sendEvent(res, 'meta', {
    model: requestModel,
    maxTokens,
    route,
    latencyTier: 'standard',
    researchPolicy: 'off',
    researchUsed: false,
    proxyAcceptedMs: elapsedMs(requestStartedAt),
  });

  let firstDeltaAt: number | undefined;
  let outputCharacters = 0;
  try {
    const anthropicStartedAt = performance.now();
    const stream = await anthropic.messages.create({
      model: requestModel,
      max_tokens: maxTokens,
      temperature: 0.2,
      system: [{ type: 'text' as const, text: COMPOSE_SYSTEM_PROMPT, cache_control: { type: 'ephemeral' as const } }],
      messages: [
        {
          role: 'user',
          content: buildComposeUserMessage(request),
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
        console.log(`Lexi /compose first token app="${request.appName}" proxyTtft=${timing.proxyTtftMs}ms anthropicTtft=${timing.anthropicTtftMs}ms`);
        sendEvent(res, 'timing', timing);
      }
      outputCharacters += event.delta.text.length;
      sendEvent(res, 'delta', { text: event.delta.text });
    }

    const doneTiming = {
      totalMs: elapsedMs(requestStartedAt),
      outputCharacters,
      route,
      latencyTier: 'standard',
      researchUsed: false,
    };
    console.log(`Lexi /compose done app="${request.appName}" total=${doneTiming.totalMs}ms chars=${outputCharacters}`);
    sendEvent(res, 'done', doneTiming);
    res.end();
  } catch (error) {
    const proxyError = classifyAssistantError(error);
    console.error('Anthropic /compose stream failed:', proxyError.code, error);
    sendEvent(res, 'error', proxyError);
    res.end();
  }
});

// Allow tests to import the research/plan helpers without binding a port.
if (process.env.LEXI_NO_LISTEN !== '1') {
  app.listen(port, host, () => {
    console.log(`Lexi proxy listening on http://${host}:${port}`);
  });
}

export {
  buildInferencePlan,
  planResearch,
  maybeResearch,
  buildMessageContent,
  extractResearchSources,
};
export type { ParsedRequest, ResearchIntent, ResearchResult, InferencePlan };

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

type ComposeParseResult =
  | { ok: true; value: ComposeRequest }
  | { ok: false; error: string };

type BuddyImage = { mediaType: AllowedImageMediaType; data: string };

type ParsedRequest =
  | { kind: 'text'; value: ExplainRequest }
  | { kind: 'followup'; value: FollowUpExplainRequest }
  | { kind: 'buddy'; value: BuddyExplainRequest; image?: BuddyImage };

type InferenceRoute = 'fast_text' | 'web_research' | 'personal_memory' | 'nested_lookup' | 'followup' | 'buddy_vision';
type LatencyTier = 'fast' | 'standard' | 'deep';
type ResearchPolicy = 'off' | 'auto' | 'required';

type InferencePlan = {
  route: InferenceRoute;
  latencyTier: LatencyTier;
  researchPolicy: ResearchPolicy;
  model: string;
  maxTokens: number;
};

type ResearchResult = {
  provider: 'perplexity';
  context: string;
  elapsedMs: number;
};

// A decision (made before inference) that a request warrants live web research,
// plus the text query to send to Perplexity. Computed once per request so the
// inference plan and the research call agree on whether research runs.
type ResearchIntent = {
  query: string;
  label: string;
};

type PerplexityResponse = {
  choices?: Array<{ message?: { content?: string } }>;
  citations?: unknown[];
  search_results?: Array<{ title?: unknown; url?: unknown; date?: unknown }>;
};

type RequestParseResult =
  | { ok: true; request: ParsedRequest }
  | { ok: false; error: string };

function parseComposeRequest(body: unknown): ComposeParseResult {
  if (!body || typeof body !== 'object') {
    return { ok: false, error: 'Expected JSON object.' };
  }

  const value = body as Record<string, unknown>;
  const instruction = stringField(value.instruction).slice(0, 1000);
  const selectedText = stringField(value.selectedText).slice(0, 1800);
  const surroundingText = stringField(value.surroundingText).slice(0, 2400);
  const currentText = stringField(value.currentText).slice(0, 2400);
  const windowTitle = stringField(value.windowTitle).slice(0, 240);
  const appName = stringField(value.appName).slice(0, 120);
  const sessionContext = stringField(value.sessionContext).slice(0, 1800);

  if (!instruction) {
    return { ok: false, error: 'instruction is required.' };
  }

  return {
    ok: true,
    value: {
      instruction,
      selectedText,
      surroundingText,
      currentText,
      windowTitle,
      appName,
      ...(sessionContext ? { sessionContext } : {}),
    },
  };
}

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

function buildInferencePlan(request: ParsedRequest, research: ResearchIntent | undefined): InferencePlan {
  const researchPolicy: ResearchPolicy = research
    ? (researchMode === 'always' ? 'required' : 'auto')
    : 'off';

  switch (request.kind) {
    case 'buddy':
      // Buddy always needs the vision model (an image may be attached); when we
      // also research, allow a few more tokens and mark it as a deeper route.
      return {
        route: research ? 'web_research' : 'buddy_vision',
        latencyTier: research ? 'deep' : 'standard',
        researchPolicy,
        model: visionModel,
        maxTokens: research ? 900 : 800,
      };
    case 'followup':
      return {
        route: research ? 'web_research' : 'followup',
        latencyTier: 'standard',
        researchPolicy,
        model: nestedModel,
        maxTokens: research ? 700 : 600,
      };
    case 'text':
      if (request.value.lineage) {
        return {
          route: 'nested_lookup',
          latencyTier: 'fast',
          researchPolicy: 'off',
          model: nestedModel,
          maxTokens: 480,
        };
      }
      if (research) {
        return {
          route: 'web_research',
          latencyTier: researchMode === 'always' ? 'deep' : 'standard',
          researchPolicy,
          model,
          maxTokens: 700,
        };
      }
      return {
        route: request.value.sessionContext ? 'personal_memory' : 'fast_text',
        latencyTier: 'fast',
        researchPolicy: 'off',
        model,
        maxTokens: request.value.sessionContext ? 700 : 520,
      };
  }
}

// Decide, before inference, whether a request warrants live web research and
// build the Perplexity query. Runs for ALL request kinds (text, buddy/vision,
// follow-up) so screenshot/voice captures that point at a company/product/term
// get real research instead of surface-level screen narration.
function planResearch(request: ParsedRequest): ResearchIntent | undefined {
  if (researchMode === 'off' || researchProvider !== 'perplexity' || !perplexityApiKey) {
    return undefined;
  }
  switch (request.kind) {
    case 'text':
      return planTextResearch(request.value);
    case 'buddy':
      return planBuddyResearch(request.value);
    case 'followup':
      return planFollowUpResearch(request.value);
  }
}

function planTextResearch(value: ExplainRequest): ResearchIntent | undefined {
  if (value.lineage) {
    return undefined;
  }
  const term = value.term.trim();
  if (researchMode === 'always') {
    return term || value.question ? { query: buildTextResearchQuery(value), label: term || value.question || 'text' } : undefined;
  }
  if (!term) {
    return undefined;
  }
  const warranted =
    Boolean(value.question) ||
    !value.passage ||
    /[-/0-9]/.test(term) ||
    /\s/.test(term) ||
    /^[A-Z0-9]{2,}$/.test(term) ||
    /[A-Z]/.test(term.slice(1)) ||
    term.length > 14;
  return warranted ? { query: buildTextResearchQuery(value), label: term } : undefined;
}

function planBuddyResearch(value: BuddyExplainRequest): ResearchIntent | undefined {
  const question = value.question.trim();
  const ocr = (value.ocrText ?? '').trim();
  // Perplexity is text-only: without a question or OCR text there is nothing to
  // research (the screenshot pixels alone can't be sent), so fall back to vision.
  if (!question && !ocr) {
    return undefined;
  }
  const label = question || ocr.slice(0, 60);
  if (researchMode === 'always') {
    return { query: buildBuddyResearchQuery(value), label };
  }
  // A pure "how do I use this UI" question with no named entity on screen is
  // about operating the app, not an external fact — leave it to vision.
  if (question && isLocalUiQuestion(question) && !hasNamedEntity(ocr)) {
    return undefined;
  }
  const warranted =
    looksLikeFactualLookup(question) ||
    hasNamedEntity(question) ||
    looksLikeFactualLookup(ocr) ||
    hasNamedEntity(ocr) ||
    ocr.length > 0; // text visible on screen almost always names something worth grounding
  return warranted ? { query: buildBuddyResearchQuery(value), label } : undefined;
}

function planFollowUpResearch(value: FollowUpExplainRequest): ResearchIntent | undefined {
  const question = value.question.trim();
  if (!question) {
    return undefined;
  }
  if (researchMode === 'always') {
    return { query: buildFollowUpResearchQuery(value), label: question };
  }
  // Most follow-ups are about the answer already on screen; only reach for the
  // web when the question asks for an external fact or names a real entity.
  if (isLocalUiQuestion(question)) {
    return undefined;
  }
  const warranted = looksLikeFactualLookup(question) || hasNamedEntity(question);
  return warranted ? { query: buildFollowUpResearchQuery(value), label: question } : undefined;
}

// True for "what/who is X", "tell me about X", market-cap/founder/etc. lookups.
function looksLikeFactualLookup(text: string): boolean {
  const t = text.trim();
  if (!t) {
    return false;
  }
  if (/\b(who|what|which|where|when)\b.{0,40}\b(is|are|was|were|founded|founder|makes?|owns?|means?|does|do|ceo|headquarter|based|company|stock|ticker|product|app)\b/i.test(t)) {
    return true;
  }
  return /\b(who is|who's|what is|what's|whats|tell me about|look up|research|how much|net worth|market cap|revenue|valuation|stock price|share price)\b/i.test(t);
}

// Loose proper-noun / acronym / ticker detector — true when text likely names a
// real-world entity (company, product, person) worth researching.
function hasNamedEntity(text: string): boolean {
  const t = text.trim();
  if (!t) {
    return false;
  }
  if (/\b[A-Z]{2,6}\b/.test(t)) {
    return true;
  }
  return /\b[A-Z][a-z]{2,}\b/.test(t);
}

// Questions about driving the UI itself rather than understanding external facts.
function isLocalUiQuestion(text: string): boolean {
  return /\b(how do i|how can i|how to|where is|which button|click|tap|close this|open this|undo|redo|shortcut|keyboard|scroll|drag|resize)\b/i.test(text);
}

async function maybeResearch(
  request: ParsedRequest,
  plan: InferencePlan,
  intent: ResearchIntent | undefined,
): Promise<ResearchResult | undefined> {
  if (plan.researchPolicy === 'off' || !intent) {
    return undefined;
  }

  const startedAt = performance.now();
  const label = intent.label.slice(0, 60);
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
          { role: 'system', content: RESEARCH_SYSTEM_PROMPT },
          { role: 'user', content: intent.query },
        ],
        max_tokens: 900,
        temperature: 0.1,
      }),
    });

    if (!response.ok) {
      const detail = await safeReadBody(response);
      console.warn(
        `Lexi research FAILED: Perplexity HTTP ${response.status} kind=${request.kind} term="${label}" endpoint=${perplexityEndpoint} model=${perplexityModel} detail=${detail}`,
      );
      return undefined;
    }

    const payload = (await response.json()) as PerplexityResponse;
    const content = stringField(payload.choices?.[0]?.message?.content).slice(0, 4200);
    if (!content) {
      console.warn(`Lexi research returned no content: kind=${request.kind} term="${label}" model=${perplexityModel}`);
      return undefined;
    }
    const sources = extractResearchSources(payload);
    const context = [
      `Provider: Perplexity ${perplexityModel}`,
      `Research answer:\n${content}`,
      sources.length ? `Sources:\n${sources.map((source, index) => `${index + 1}. ${source}`).join('\n')}` : '',
    ].filter(Boolean).join('\n\n').slice(0, 5200);
    const researchElapsedMs = elapsedMs(startedAt);
    console.log(
      `Lexi research done kind=${request.kind} term="${label}" provider=perplexity ms=${researchElapsedMs} sources=${sources.length}`,
    );
    return { provider: 'perplexity', context, elapsedMs: researchElapsedMs };
  } catch (error) {
    console.warn(
      `Lexi research FAILED: Perplexity request errored kind=${request.kind} term="${label}" endpoint=${perplexityEndpoint}`,
      error,
    );
    return undefined;
  }
}

// Perplexity returns sources in `search_results` (objects with title/url) on
// current models, and historically as a `citations` array of bare URLs. Prefer
// the richer search_results and fall back to citations.
function extractResearchSources(payload: PerplexityResponse): string[] {
  const sources: string[] = [];
  if (Array.isArray(payload.search_results)) {
    for (const result of payload.search_results) {
      const title = stringField(result?.title);
      const url = stringField(result?.url);
      if (url) {
        sources.push(title ? `${title} — ${url}` : url);
      } else if (title) {
        sources.push(title);
      }
    }
  }
  if (sources.length === 0 && Array.isArray(payload.citations)) {
    for (const citation of payload.citations) {
      const url = stringField(citation);
      if (url) {
        sources.push(url);
      }
    }
  }
  return sources.slice(0, 8);
}

async function safeReadBody(response: Response): Promise<string> {
  try {
    return (await response.text()).slice(0, 300).replace(/\s+/g, ' ').trim() || '(empty body)';
  } catch {
    return '(unreadable body)';
  }
}

function buildTextResearchQuery(input: ExplainRequest): string {
  return `Research the highlighted term for Lexi. Return source-grounded facts that help answer accurately.

TERM: ${input.term}
PASSAGE: ${input.passage || '(none)'}
WINDOW TITLE: ${input.windowTitle || '(unknown)'}
APP: ${input.appName || '(unknown)'}
READER QUESTION: ${input.question || '(none)'}

Focus on exact definition, specific entity/name identification, current factual context, and ambiguity. Keep it concise but cite/source the claims.`;
}

function buildBuddyResearchQuery(input: BuddyExplainRequest): string {
  return `Research what the reader is pointing at on their screen for Lexi. Identify the specific entity (company, product, person, organization, or term) and return source-grounded, current facts.

SPOKEN QUESTION: ${input.question || '(none — the reader pointed without speaking)'}
TEXT VISIBLE ON SCREEN (OCR): ${input.ocrText || '(none)'}
WINDOW TITLE: ${input.windowTitle || '(unknown)'}
APP: ${input.appName || '(unknown)'}

Identify exactly what this is (real name, what it does, who is behind it, current status, key numbers or dates). If ambiguous, give the most likely identification and note alternatives. Be concise and cite sources.`;
}

function buildFollowUpResearchQuery(input: FollowUpExplainRequest): string {
  return `Research to answer a reader's follow-up question for Lexi. Return source-grounded, current facts.

FOLLOW-UP QUESTION: ${input.question}
TOPIC BEING DISCUSSED: ${input.parentTerm || input.rootTerm}
ROOT TERM: ${input.rootTerm}
APP: ${input.appName || '(unknown)'}

Focus on the specific facts the question asks for (names, numbers, dates, current status, definitions). Be concise and cite sources.`;
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
      return buildBuddyMessageContent(request, research);
    case 'followup':
      return buildFollowUpUserMessage({ ...request.value, ...(research ? { researchContext: research.context } : {}) });
    case 'text':
      return buildUserMessage({ ...request.value, ...(research ? { researchContext: research.context } : {}) });
  }
}

function buildBuddyMessageContent(
  request: { value: BuddyExplainRequest; image?: BuddyImage },
  research?: ResearchResult,
): Anthropic.ContentBlockParam[] {
  const blocks: Anthropic.ContentBlockParam[] = [];
  if (request.image) {
    blocks.push({
      type: 'image',
      source: { type: 'base64', media_type: request.image.mediaType, data: request.image.data },
    });
  }
  blocks.push({
    type: 'text',
    text: buildBuddyUserMessage({ ...request.value, ...(research ? { researchContext: research.context } : {}) }),
  });
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
