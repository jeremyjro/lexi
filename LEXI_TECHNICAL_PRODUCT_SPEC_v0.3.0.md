# Lexi Technical Product Spec v0.3.0

Last updated: 2026-06-24

## Objective

Lexi v0.3.0 turns the current highlight-first research assistant into a faster, lower-friction comprehension system informed by the Clicky review. The product goal remains distinct from Clicky: Lexi is not primarily an always-on voice buddy. Lexi helps users understand concepts they are researching faster, without interrupting their learning flow, by inferring likely questions from highlighted text, surrounding passage, screen captures, OCR, voice, and recent session context.

## Product thesis

Lexi should optimize for three loops:

1. **Highlight loop:** highlight text anywhere, release Option+Space, get a concise contextual explanation.
2. **Drill-down loop:** highlight inside the Lexi answer or ask a typed follow-up, continue without leaving the answer card.
3. **Buddy loop:** ask about visible material using either a precise region drag or a faster push-to-talk quick capture.

Clicky is better at the voice-first companion loop. Lexi should borrow its infrastructure where it improves speed and reliability, while preserving Lexi's stronger text-first research workflow.

## Scope for v0.3.0

### Phase 1: Network/session hardening

Implementation requirements:

- Replace per-request reliance on `URLSession.shared` with a shared configured session in `ExplainClient`.
- Use longer timeouts for image/Buddy requests than for text lookups.
- Disable response cache and cookie storage in the assistant session.
- Warm up the proxy TLS connection once per host.
- Record request bytes and HTTP status in local diagnostics.

Files:

- `Sources/Lexi/Network/ExplainClient.swift`
- `Sources/Lexi/Diagnostics/LexiDiagnostics.swift`
- `Sources/Lexi/Settings/SettingsWindowController.swift`

### Phase 2: Adaptive Buddy image quality

Problem:

The previous 18 KB screenshot target was a defensive response to a stale Railway deployment rejecting small payloads. Now that the deployed proxy has a 25 MB body limit, 18 KB is too aggressive for comprehension quality.

Implementation requirements:

- Replace the fixed 18 KB target with adaptive JPEG quality tiers.
- Preserve a hard client-side cap well below the proxy limit.
- Record encoded image bytes and dimensions for diagnostics.
- Keep selected-region capture privacy-preserving by default.
- Add cursor-screen/focused-window capture for quick Buddy mode.

Files:

- `Sources/Lexi/Buddy/RegionScreenshotCapture.swift`
- `Sources/Lexi/Panel/RawCapturePanelController.swift`
- `Sources/Lexi/Diagnostics/LexiDiagnostics.swift`

### Phase 3: Push-to-talk quick Buddy flow

Problem:

The current Buddy region-drag flow is precise but too modal for fast research questions. Clicky's push-to-talk loop is faster.

Implementation requirements:

- Add a listen-only global CGEvent tap for Control+Option push-to-talk.
- On press: begin listening and show immediate panel feedback.
- On release: finalize transcript, capture focused window or cursor screen, and submit.
- Keep existing Option+Command region selection for precise captures.
- Cancel any active response/TTS when a new quick Buddy session starts.

Files:

- `Sources/Lexi/Buddy/BuddyPushToTalkMonitor.swift`
- `Sources/Lexi/Buddy/BuddyCaptureCoordinator.swift`
- `Sources/Lexi/AppDelegate.swift`
- `Sources/Lexi/Settings/SettingsWindowController.swift`

### Phase 4: Voice provider layer with AssemblyAI placeholder support

Problem:

Apple on-device speech is not robust enough for technical/proper-noun research vocabulary.

Implementation requirements:

- Add a transcription provider protocol.
- Keep Apple Speech as a local fallback.
- Add AssemblyAI realtime streaming provider scaffold using `/transcribe-token` from the Lexi proxy.
- Do not store AssemblyAI secrets in the app.
- Expose provider selection in Settings.
- Add `.env.example` placeholders for AssemblyAI.

Files:

- `Sources/Lexi/Buddy/BuddyVoiceCapture.swift`
- `Sources/Lexi/Buddy/BuddyTranscriptionProvider.swift`
- `Sources/Lexi/Buddy/BuddyAudioConversionSupport.swift`
- `Sources/Lexi/Network/AppConfiguration.swift`
- `proxy/src/server.ts`
- `proxy/.env.example`

Required manual config after implementation:

```bash
ASSEMBLYAI_API_KEY=
```

### Phase 5: OCR and transcription keyterms

Problem:

For research comprehension, text in screenshots matters more than raw pixels. Voice transcription also improves when biased toward relevant technical vocabulary.

Implementation requirements:

- Run Vision OCR on captured Buddy screenshots.
- Attach OCR text to Buddy requests.
- Include OCR text in the proxy prompt.
- Extract keyterms from OCR, selected text, session history, app/window title, and recent answers.
- Pass keyterms into AssemblyAI when available.

Files:

- `Sources/Lexi/Buddy/BuddyTextRecognizer.swift`
- `Sources/Lexi/Buddy/RegionScreenshotCapture.swift`
- `Sources/Lexi/Buddy/BuddyCaptureCoordinator.swift`
- `Sources/Lexi/Memory/ResearchSessionMemory.swift`
- `proxy/src/prompt.ts`
- `proxy/src/server.ts`

### Phase 6: Compact research session memory

Problem:

Lexi has nested lookups and follow-ups, but no compact chronological research-session memory.

Implementation requirements:

- Track recent terms/questions and answers in memory only.
- Keep bounded history.
- Send compact recent context to the proxy.
- Use memory to generate transcription keyterms.
- Do not persist sensitive content by default.

Files:

- `Sources/Lexi/Memory/ResearchSessionMemory.swift`
- `Sources/Lexi/AppDelegate.swift`
- `Sources/Lexi/Network/ExplainClient.swift`
- `proxy/src/prompt.ts`
- `proxy/src/server.ts`

### Phase 7: Optional ElevenLabs read-aloud

Problem:

Clicky demonstrates that voice response can reduce friction for some screen-help workflows, but Lexi should remain text-first.

Implementation requirements:

- Add optional TTS setting, default off.
- Add proxy `/tts` endpoint using ElevenLabs placeholders.
- Add Swift TTS client that plays returned MP3 data.
- Speak final answers only when the setting is enabled.
- Add stop playback behavior when a new request starts.

Files:

- `Sources/Lexi/Audio/ElevenLabsTTSClient.swift`
- `Sources/Lexi/Network/AppConfiguration.swift`
- `Sources/Lexi/AppDelegate.swift`
- `Sources/Lexi/Settings/SettingsWindowController.swift`
- `proxy/src/server.ts`
- `proxy/.env.example`

Required manual config after implementation:

```bash
ELEVENLABS_API_KEY=
ELEVENLABS_VOICE_ID=
```

### Phase 8: Buddy visual callouts

Problem:

For screen/UI/chart questions, a visual pointer can be more useful than another sentence.

Implementation requirements:

- Extend Buddy prompt to allow a final `[CALLOUT:x,y:label]` tag or `[CALLOUT:none]`.
- Strip callout tags from displayed/spoken answer text.
- Map screenshot pixel coordinates back to the selected region when available.
- Display a temporary non-activating overlay marker/label at that screen coordinate.
- Keep this Buddy-only; do not turn Lexi into a global cursor clone.

Files:

- `Sources/Lexi/Buddy/BuddyCalloutOverlayController.swift`
- `Sources/Lexi/AppDelegate.swift`
- `proxy/src/prompt.ts`

## Proxy configuration

The proxy remains the single external API gateway for production. Manual secrets are configured after deployment, never committed.

Required/optional variables:

```bash
ANTHROPIC_API_KEY=
ANTHROPIC_MODEL=claude-sonnet-4-6
ANTHROPIC_NESTED_MODEL=
ANTHROPIC_VISION_MODEL=
LEXI_PROXY_TOKEN=
LEXI_JSON_BODY_LIMIT=25mb
ASSEMBLYAI_API_KEY=
ELEVENLABS_API_KEY=
ELEVENLABS_VOICE_ID=
```

## UX surface after v0.3.0

Shortcuts:

- Option+Space release: explain highlighted text.
- Option+Command release: precise Buddy region capture.
- Control+Option hold/release: quick Buddy push-to-talk capture.
- Inside Lexi answer: typed follow-up field.
- Inside Lexi answer: highlight text and press right arrow for nested lookup.

Settings:

- Proxy URL/token.
- Voice provider: Apple Speech or AssemblyAI.
- Read answers aloud toggle.
- Proxy health with Anthropic/AssemblyAI/ElevenLabs configuration status.
- Diagnostics: last request bytes, HTTP status, Buddy image size, OCR length, last mode.

## Non-goals

- Do not make voice/TTS mandatory.
- Do not capture all screens by default.
- Do not ship third-party API secrets in the app.
- Do not replace Lexi's concise reading-assistant behavior with casual spoken-buddy behavior.
- Do not persist research history unless explicitly added later with user controls.

## Verification

Run before considering implementation complete:

```bash
swift build --package-path "/Volumes/T7/Projects/Jeremy/Lexi"
npm run typecheck --prefix "/Volumes/T7/Projects/Jeremy/Lexi/proxy"
"/Volumes/T7/Projects/Jeremy/Lexi/scripts/package_app.sh"
"/Volumes/T7/Projects/Jeremy/Lexi/scripts/deploy_railway_proxy.sh"
curl -sS "https://lexi-production-9152.up.railway.app/health"
```
