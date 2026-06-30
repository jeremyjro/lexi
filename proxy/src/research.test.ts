import assert from 'node:assert/strict';
import test from 'node:test';

// Configure research env BEFORE importing the server module, since the proxy
// reads these into module-level constants at import time. LEXI_NO_LISTEN keeps
// the import side-effect-free (no port binding) so tests can exercise helpers.
process.env.LEXI_NO_LISTEN = '1';
process.env.PERPLEXITY_API_KEY = 'test-key';
process.env.LEXI_RESEARCH_PROVIDER = 'perplexity';
process.env.LEXI_RESEARCH_MODE = 'auto';
process.env.PERPLEXITY_ENDPOINT = 'https://api.perplexity.ai/chat/completions';
process.env.PERPLEXITY_MODEL = 'sonar-pro';

const {
  planResearch,
  buildInferencePlan,
  maybeResearch,
  buildMessageContent,
  extractResearchSources,
} = await import('./server.js');
type Mod = typeof import('./server.js');
type ParsedRequest = Parameters<Mod['planResearch']>[0];

function buddyRequest(overrides: Record<string, unknown> = {}): ParsedRequest {
  return {
    kind: 'buddy',
    value: {
      question: '',
      windowTitle: '',
      appName: 'Safari',
      hasImage: true,
      ...overrides,
    },
    image: { mediaType: 'image/png', data: 'AAAA' },
  } as ParsedRequest;
}

function fakeFetch(status: number, body: unknown) {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const fn = async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return {
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
      text: async () => JSON.stringify(body),
    } as unknown as Response;
  };
  return { fn: fn as unknown as typeof fetch, calls };
}

test('planResearch triggers research for a screenshot of a company name (OCR)', () => {
  const intent = planResearch(buddyRequest({ ocrText: 'Anthropic' }));
  assert.ok(intent, 'expected a research intent for OCR company name');
  assert.match(intent!.query, /Anthropic/);
});

test('planResearch skips a pure UI/how-to buddy question with no entity', () => {
  const intent = planResearch(buddyRequest({ question: 'how do I close this window?' }));
  assert.equal(intent, undefined);
});

test('planResearch skips when buddy has neither question nor OCR (vision only)', () => {
  const intent = planResearch(buddyRequest({}));
  assert.equal(intent, undefined);
});

test('planResearch researches a factual follow-up phrased as "where is X based?"', () => {
  const req = {
    kind: 'followup',
    value: {
      question: 'where is Anthropic based?',
      rootTerm: 'Claude',
      rootSourceText: '',
      parentTerm: 'Claude',
      parentAnswer: 'Claude is an AI assistant.',
      depth: 1,
      windowTitle: '',
      appName: 'Safari',
    },
  } as ParsedRequest;
  const intent = planResearch(req);
  assert.ok(intent, 'factual "where is" follow-up should still research');
  assert.match(intent!.query, /Anthropic/);
});

test('planResearch researches a buddy voice question naming an entity with no OCR', () => {
  const intent = planResearch(buddyRequest({ question: 'where is Anthropic based?', ocrText: '' }));
  assert.ok(intent, 'entity question with no OCR should still research');
});

test('buildInferencePlan marks buddy research auto and keeps the vision model', () => {
  const req = buddyRequest({ ocrText: 'Anthropic' });
  const intent = planResearch(req);
  const plan = buildInferencePlan(req, intent);
  assert.equal(plan.researchPolicy, 'auto');
  assert.equal(plan.route, 'web_research');
});

test('maybeResearch (mocked 200) returns context with answer + sources and hits the chat endpoint', async () => {
  const original = globalThis.fetch;
  const mock = fakeFetch(200, {
    choices: [{ message: { content: 'Anthropic is an AI safety company founded in 2021.' } }],
    search_results: [{ title: 'Anthropic', url: 'https://www.anthropic.com' }],
  });
  globalThis.fetch = mock.fn;
  try {
    const req = buddyRequest({ ocrText: 'Anthropic' });
    const intent = planResearch(req);
    const plan = buildInferencePlan(req, intent);
    const research = await maybeResearch(req, plan, intent);
    assert.ok(research, 'expected research result');
    assert.match(research!.context, /Anthropic is an AI safety company/);
    assert.match(research!.context, /anthropic\.com/);

    // Verify endpoint + request body shape match the Perplexity chat API.
    assert.equal(mock.calls.length, 1);
    assert.equal(mock.calls[0].url, 'https://api.perplexity.ai/chat/completions');
    const sentBody = JSON.parse(String(mock.calls[0].init.body));
    assert.equal(sentBody.model, 'sonar-pro');
    assert.ok(Array.isArray(sentBody.messages));
    assert.equal(sentBody.messages[0].role, 'system');
    assert.equal(sentBody.messages[1].role, 'user');
    assert.equal('search_mode' in sentBody, false, 'invalid search_mode param must be removed');
    assert.equal('return_related_questions' in sentBody, false, 'invalid param must be removed');
  } finally {
    globalThis.fetch = original;
  }
});

test('maybeResearch (mocked 4xx) falls back cleanly to undefined', async () => {
  const original = globalThis.fetch;
  const mock = fakeFetch(400, { error: { message: 'bad request' } });
  globalThis.fetch = mock.fn;
  try {
    const req = buddyRequest({ ocrText: 'Anthropic' });
    const intent = planResearch(req);
    const plan = buildInferencePlan(req, intent);
    const research = await maybeResearch(req, plan, intent);
    assert.equal(research, undefined);
  } finally {
    globalThis.fetch = original;
  }
});

test('buildMessageContent injects WEB RESEARCH CONTEXT into the buddy (vision) message', () => {
  const req = buddyRequest({ ocrText: 'Anthropic' });
  const content = buildMessageContent(req, {
    provider: 'perplexity',
    context: 'Provider: Perplexity sonar-pro\n\nResearch answer:\nAnthropic is an AI company.',
    elapsedMs: 10,
  });
  assert.ok(Array.isArray(content));
  const text = (content as Array<{ type: string; text?: string }>)
    .filter((b) => b.type === 'text')
    .map((b) => b.text)
    .join('\n');
  assert.match(text, /WEB RESEARCH CONTEXT/);
  assert.match(text, /Anthropic is an AI company/);
});

test('extractResearchSources prefers search_results, falls back to citations', () => {
  assert.deepEqual(
    extractResearchSources({ search_results: [{ title: 'A', url: 'https://a.com' }] }),
    ['A — https://a.com'],
  );
  assert.deepEqual(
    extractResearchSources({ citations: ['https://b.com'] }),
    ['https://b.com'],
  );
});
