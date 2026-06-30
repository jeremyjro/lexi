# Lexi Context Infrastructure Roadmap

Last updated: 2026-06-25

## Executive summary

Lexi should not try to become defensible by training a frontier model from scratch. That is too expensive, too slow, and not where the product-specific moat lives. Lexi becomes defensible by owning the layers that generic model providers do not own: the user's live laptop context, personal memory, retrieval/routing logic, feedback data, latency-optimized interaction patterns, and safe action permissions.

The current product is useful but thinly moated:

```text
macOS capture overlay → Railway proxy → Claude/Perplexity → answer panel
```

The defensible version should become:

```text
native sensing layer
→ local context daemon
→ personal memory/event store
→ retrieval + entity graph
→ inference orchestrator
→ specialized fast/deep model routes
→ safe action layer
→ evaluation + personalization loop
```

Claude, Perplexity, AssemblyAI, Wispr, and similar APIs can remain rented capabilities. Lexi should own the context operating system around them.

## Product vision

Lexi is a private, always-available personal context layer for the computer. It watches only what the user permits, understands current work context, remembers useful concepts and relationships, retrieves relevant personal and web context, and answers or acts with minimal user ceremony.

The target user experience:

- The user highlights or points at something.
- Lexi already knows the active app, window, recent context, relevant notes, and likely intent.
- Simple questions answer quickly.
- Ambiguous names, companies, niche definitions, or current facts trigger web-grounded research.
- Personal concepts trigger private memory retrieval.
- Repeated use makes Lexi better for that specific user.
- Actions are possible, but always gated by explicit permissions and previews.

## Strategic principles

1. **Own context, not the foundation model.** Foundation models are rented reasoning engines. The moat is the user's private context graph and the product's ability to assemble the right context at the right time.
2. **Fast and deep are different products.** Quick comprehension should feel instant. Deep research can take seconds. The router must choose the right path.
3. **Prediction is not evidence.** Claude can infer likely meanings, but exact names, companies, products, current facts, and niche definitions need retrieval or web research.
4. **Local-first where possible.** The laptop has privacy-sensitive context. Extract, summarize, and index locally; send only relevant snippets to cloud models.
5. **Build an evaluation loop before fine-tuning.** Fine-tuning without interaction data and evals is premature optimization.
6. **Use narrow models before custom foundation models.** Train small classifiers/rankers/summarizers for Lexi-specific tasks only after enough data exists.

## Competitive reference: Wispr Flow

Public case studies describe Wispr Flow using open-source Llama-family models for real-time transcript cleanup, hosted on dedicated low-latency inference infrastructure. The key lesson is not that every startup needs to train a model from scratch. The lesson is that Wispr owns the narrow task layer around speech:

- capture everywhere on device
- user vocabulary and style memory
- transcript cleanup and self-correction handling
- fine-tuned open-source models for the exact post-processing task
- dedicated inference optimized for p99 latency
- continuous feedback data

Lexi should copy the pattern, not the exact domain. The Lexi equivalent is:

- context capture everywhere on the laptop
- personal memory and entity graph
- contextual explanation and action routing
- small specialized models for intent/routing/ranking later
- dedicated fast path for common comprehension tasks
- continuous answer-quality and latency evaluation

## Stack ownership map

### Own now

- Native macOS capture and interaction layer
- Active app/window/context extraction
- Local interaction event store
- Recent-session memory
- Inference route planning
- Research trigger policy
- Personal retrieval policy
- Evaluation events and latency metrics
- User-facing answer UX
- Safe action permission model

### Rent now

- Claude/GPT/Gemini for frontier reasoning
- Perplexity/Exa for web-grounded research
- AssemblyAI/Wispr/Deepgram for production speech-to-text
- Apple Vision/Claude/Gemini for OCR and vision depending on latency/privacy needs
- Hosted embeddings until local embeddings are justified

### Own later

- Intent classifier
- Context ranker/reranker
- Query rewriter
- Answer compression/style model
- Local summarizer
- Transcript cleanup model
- Dedicated inference endpoint for fine-tuned small models
- Optional local on-device model path for privacy/latency

## Target architecture

```text
Lexi.app
  Hotkey/voice/screen capture
  Active app/window detector
  OCR and text extraction
  Local event store
  Local memory/retrieval client
  Answer panel

Lexi Context Store
  events.jsonl / SQLite v1
  interactions
  screen_context
  entities
  memories
  embeddings
  feedback

Lexi Proxy
  authentication
  inference orchestrator
  route planner
  web research adapter
  model adapter(s)
  telemetry events
  eval sampling

External engines
  Claude: synthesis/reasoning
  Perplexity: web-grounded facts
  Embeddings provider or local embeddings
  Speech provider
  Future fine-tuned small model endpoint
```

## Route taxonomy

Lexi should stop treating every request as one generic model call.

### `fast_text`

Use when the selected term is common, passage context is strong, and no special entity/current-fact signal appears.

- Goal: low latency
- Dependencies: Claude only or future small model
- Research: no
- Target: fastest time-to-first-token

### `web_research`

Use when term/question likely needs facts beyond the passage.

Triggers:

- explicit spoken/written question
- proper nouns or multi-word names
- hyphenated terms
- acronyms
- terms with numbers
- no passage context
- long/uncommon terms
- current events/products/companies

- Goal: accuracy
- Dependencies: Perplexity then Claude
- Target: slower but source-grounded

### `personal_memory`

Use when the term/question maps to prior Lexi answers, Obsidian notes, contacts, projects, or recent screen context.

- Goal: personalization
- Dependencies: local memory + Claude
- Target: medium latency

### `deep_synthesis`

Use when the question is strategic, multi-hop, or action-oriented.

- Goal: thoughtful answer
- Dependencies: memory + web + Claude
- Target: seconds are acceptable

### `buddy_vision`

Use for screenshot/pointing workflows.

- Goal: explain visible UI/content
- Dependencies: OCR, image model, optional memory
- Target: medium latency

### `action_agent`

Use only after explicit user request to do something.

- Goal: act on behalf of user
- Dependencies: tool layer
- Target: correctness and safety over speed

## Phase plan

## Phase 0 — Stabilize current assistant

Status: mostly complete before this roadmap.

Delivered capabilities:

- macOS answer panel
- top-right pill and expanded answer card
- Claude proxy
- Perplexity research path
- Buddy screenshot/voice scaffolding
- recent in-memory session context
- basic diagnostics

Remaining risks:

- inference path is still mostly monolithic
- no durable local event/memory store
- no eval set
- no retrieval ranking
- no structured route telemetry

## Phase 1 — Inference orchestrator and route telemetry

Goal: make the backend an explicit decision system instead of a direct Claude wrapper.

Implementation requirements:

- Introduce an `InferencePlan` object in the proxy.
- Classify each request into route types.
- Decide model, token budget, research policy, and latency tier from the route.
- Emit route metadata in SSE `meta` events.
- Log done timing with route and research state.
- Keep existing API contract stable for the Mac client.

Success criteria:

- `/explain` response meta includes route, latency tier, model, max tokens, research policy, and research usage.
- Perplexity is only called when route policy says it should be.
- Typecheck/build pass.

Why this matters:

This creates the backend seam where future local models, memory retrieval, and action planning can plug in.

## Phase 2 — Local durable interaction/event store

Goal: start owning data from real usage.

Implementation requirements:

- Add a local append-only event store in the Mac app.
- Store every completed answer event as JSONL.
- Include term, app, window, source, answer preview, latency, route, research usage, and timestamp.
- Keep sensitive full payloads out of telemetry by default.
- Add diagnostics fields for last route/research/done timing.

Success criteria:

- Completed Lexi answers create local interaction events.
- Diagnostics can show last route and research usage.
- This works without adding external dependencies.

Why this matters:

This is the seed of the proprietary dataset. Without this, Lexi cannot evaluate, personalize, or fine-tune.

## Phase 3 — Local context daemon

Goal: make Lexi context-ready before the user asks.

Implementation requirements:

- Track active app/window changes.
- Capture lightweight text context where permissions allow.
- Capture browser URL/title where possible.
- Cache recent OCR/text snippets with timestamps.
- Build a rolling current-context summary.
- Keep data local unless explicitly needed for inference.

Success criteria:

- When a highlight happens, Lexi can include recent app/window/page context without waiting for a fresh expensive capture.
- Context capture has privacy controls and diagnostics.

## Phase 4 — Personal memory retrieval

Goal: retrieve relevant personal context before calling a model.

Implementation requirements:

- Index prior Lexi interactions.
- Index selected Obsidian folders or notes.
- Add entity extraction for people, companies, projects, products, and niche terms.
- Retrieve top relevant snippets for each request.
- Add `PERSONAL MEMORY CONTEXT` to prompts.

Success criteria:

- Lexi can answer questions using previous Lexi answers and Obsidian context.
- The proxy meta identifies when personal memory was used.

## Phase 5 — Evaluation framework

Goal: stop making prompt/model changes by vibes.

Implementation requirements:

- Create a seed eval set from real Lexi interactions.
- Track latency, source accuracy, answer usefulness, and hallucination risk.
- Add simple feedback buttons or menu actions: useful, wrong, too slow, save.
- Store feedback events locally.
- Add a script to replay eval requests against proxy configurations.

Success criteria:

- Every major prompt/model/router change can be compared against real cases.
- Latency regressions are visible.

## Phase 6 — Specialized small models

Goal: own narrow inference tasks where data and latency justify it.

Candidate models:

- intent classifier
- research trigger classifier
- context ranker
- answer style/compression model
- transcript cleanup model
- local summary model

Likely base models:

- Llama 3.1/3.2 8B
- Qwen 2.5/3 7B or 14B
- Mistral small models
- Phi-class local models for very small local tasks

Serving options:

- Baseten
- Modal
- Fireworks
- Together
- AWS/GCP with vLLM or TensorRT-LLM
- local llama.cpp/Core ML for on-device tasks

Success criteria:

- A small model beats prompt-only routing on latency/cost without hurting quality.
- It is used for routing/ranking/compression before final synthesis.

## Phase 7 — Safe action layer

Goal: let Lexi act, not just explain.

Implementation requirements:

- Tool registry with scopes and permissions.
- Dry-run previews for destructive or external actions.
- Integrations: Obsidian, Gmail, Calendar, Slack, browser, files.
- Action audit log.
- Confirmation UX for real-world side effects.

Success criteria:

- Lexi can draft, file, summarize, create notes, and schedule with user approval.
- No irreversible actions run without explicit confirmation.

## Phase 8 — Dedicated inference infrastructure

Goal: own performance-critical model serving after usage justifies it.

Implementation requirements:

- Move specialized model serving to dedicated GPU infra.
- Add autoscaling and p95/p99 latency dashboards.
- Use quantization where quality allows.
- Benchmark providers.
- Keep provider abstraction in the orchestrator.

Success criteria:

- Common routes have predictable latency and lower marginal cost.
- The product can choose between rented frontier reasoning and owned narrow inference.

## Cost and team considerations

### Near term: RAG and orchestration

Typical cost:

- Low infra cost
- Mostly engineering time
- Can be built by one strong full-stack/native engineer with backend support

Skills needed:

- Swift/macOS
- TypeScript backend
- data modeling
- retrieval basics
- privacy/security judgment

### Mid term: memory and eval system

Typical cost:

- Moderate engineering time
- Some cloud storage/embedding cost
- One backend/data engineer useful

Skills needed:

- SQLite/Postgres
- embeddings/vector search
- eval harnesses
- telemetry design

### Later: fine-tuned small models

Typical cost:

- Prototype: hundreds to low thousands of dollars
- Serious iteration: thousands to tens of thousands monthly
- Production serving: depends heavily on usage and latency targets

Skills needed:

- ML engineer
- data pipeline experience
- fine-tuning/LoRA/DPO/eval experience
- inference optimization
- GPU serving

### Not recommended: foundation model from scratch

Training a useful foundation model from scratch requires major capital, research talent, large-scale data, and GPU infrastructure. This is not the right early strategy for Lexi.

## Privacy and safety requirements

Lexi's moat depends on private context, so trust is product-critical.

Required principles:

- local-first event storage
- visible controls for what is captured
- never log secrets
- do not upload screenshots by default unless needed for Buddy/vision
- show clear indicators when screen/image context is used
- allow local data export/delete
- require explicit confirmation for external actions
- keep provider keys server-side

## Immediate implementation commitments from this roadmap

This roadmap's first implementation step should ship:

1. backend inference plan/router metadata
2. Perplexity research policy controlled by the plan
3. route/research/done timing surfaced to the Mac diagnostics layer
4. local JSONL interaction event store
5. health/diagnostics fields that make the infrastructure observable

That gives Lexi the first owned infrastructure layer without overbuilding ML prematurely.

## Pipeline backlog

Status as of 2026-06-25: these items are intentionally parked behind the active composition feature work. They remain part of the defensibility roadmap, but they should not block the next product experiment.

### Now / active foundation

- [x] Backend inference route planner and telemetry
- [x] Perplexity research policy controlled by route plan
- [x] Route/research/done timing surfaced to Mac diagnostics
- [x] Local JSONL interaction event store
- [x] Lightweight active app/window context sampler
- [x] Lexical retrieval from prior local Lexi interactions

### Backlog — next infrastructure tasks

- [ ] Replace lexical retrieval with embeddings-backed local retrieval.
- [ ] Add selected Obsidian folders/notes to the personal memory index.
- [ ] Add entity extraction for people, companies, projects, products, and niche terms.
- [ ] Build an eval harness with real Lexi interactions and expected answer traits.
- [ ] Add answer feedback actions: useful, wrong, too slow, save to memory.
- [ ] Add latency dashboards for route, research provider, TTFT, and total completion time.
- [ ] Add privacy controls to view, export, and delete local Lexi event/context logs.
- [ ] Add a safe action registry with dry-run previews and explicit confirmations.
- [ ] Prototype a small route classifier once enough labeled events exist.
- [ ] Prototype a context reranker once embedding retrieval exists.
- [ ] Evaluate dedicated small-model inference only after evals prove a route can be owned.

### Parking-lot ideas

- [ ] On-device local summarizer for recent app/window context.
- [ ] Browser page-content extractor with per-domain privacy controls.
- [ ] Calendar/Gmail/Slack/Obsidian memory adapters.
- [ ] Fine-tuned transcript cleanup model for voice dictation/composition.
- [ ] Dedicated GPU inference endpoint for narrow Lexi tasks.
