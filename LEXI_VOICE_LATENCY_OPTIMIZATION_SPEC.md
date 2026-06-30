# Lexi Voice Latency Optimization Spec

## Goal

Make Lexi feel closer to a Wispr Flow-style voice interface: capture voice quickly, finalize transcripts quickly, preserve partial transcript responsiveness, and reduce the time from hotkey release to first useful AI output.

This work focuses on the path that matters for personal agents:

```text
hotkey down
→ microphone capture starts
→ partial transcript appears
→ hotkey up
→ transcript finalizes
→ route intent
→ /compose or /explain streams
→ output lands in the active work surface
```

## Freeflow findings

The Freeflow codebase has several useful patterns for Lexi:

1. **Low-level audio capture and normalized PCM streams**
   - Freeflow captures audio with `AVCaptureSession`, converts audio to normalized mono PCM, and supports streaming chunks to a realtime socket while also writing an upload file.
   - Lexi currently uses `AVAudioEngine` with an input tap, which is simpler and already supports streaming to Apple Speech or AssemblyAI.
   - Immediate takeaway: reduce Lexi's audio tap buffer size and instrument the capture path before replacing the audio stack.

2. **Realtime transcription as the latency-first path**
   - Freeflow has a dedicated realtime WebSocket transcription service.
   - Lexi already has a realtime AssemblyAI WebSocket path, but it pays token fetch/open costs on each session.
   - Immediate takeaway: keep AssemblyAI as Lexi's latency-first provider, prewarm token availability, and shorten finalization fallback.

3. **Groq Whisper upload as a fast fallback, not a streaming replacement**
   - Freeflow uses Groq's OpenAI-compatible `/audio/transcriptions` endpoint with `whisper-large-v3` or `whisper-large-v3-turbo`.
   - This is probably not a fine-tuned Wispr model. It is hosted Whisper via Groq, plus post-processing models.
   - Immediate takeaway: add Groq/Whisper as a future fallback option for long dictation or when realtime streaming is unavailable. Do not replace Lexi's streaming path with upload-only transcription for agent commands.

4. **Post-processing model separation**
   - Freeflow separates raw ASR from cleanup/edit-command transformation.
   - Lexi's composition/explanation path already sends the transcript as an instruction to Claude, so separate cleanup would add latency today.
   - Immediate takeaway: defer transcript cleanup until Lexi supports pure dictation. For agent commands, route raw-but-fast transcript directly.

5. **Tight timeouts and request isolation**
   - Freeflow uses explicit timeout races and ephemeral sessions for potentially flaky upload calls.
   - Lexi should add explicit voice timing diagnostics and avoid hiding slow phases behind generic errors.

## Current Lexi bottlenecks

### 1. Audio buffer size

Lexi currently taps the microphone with a 4096-frame buffer. At common input rates, that can add roughly 85ms at 48kHz before a buffer is handed to the STT session. Reducing this to 1024 frames gives faster partial updates without changing providers.

### 2. AssemblyAI session startup

Lexi fetches a short-lived token and opens a WebSocket only after the user starts speaking. That setup time is visible on every session.

### 3. Final transcript fallback

Lexi waits up to 2.8s for AssemblyAI final transcript fallback. That is safe, but too conservative for short push-to-talk commands.

### 4. Missing phase diagnostics

Lexi logs model/proxy TTFT, but voice phases are less explicit:

- provider session ready time
- audio engine start time
- partial transcript time
- stop-to-final-transcript time

Without these, latency work becomes guesswork.

## Implemented v1 changes

### 1. Smaller audio tap buffer

Use a 1024-frame audio tap buffer for voice capture instead of 4096.

Expected impact:

- faster first audio chunk
- faster partial transcript updates
- better perceived responsiveness

Risk:

- slightly more frequent audio callback work
- should be acceptable for short push-to-talk commands

### 2. Voice timing instrumentation

Add per-session timing logs:

- provider selected
- provider session ready
- audio engine started
- first partial transcript
- stop requested
- final transcript returned

Expected impact:

- makes future latency work measurable
- helps distinguish STT, audio, proxy, and model latency

### 3. AssemblyAI token/session optimization

Use a shared low-latency URLSession for token fetches instead of `URLSession.shared`, add token fetch timeout, and prewarm token availability when AssemblyAI is selected.

Expected impact:

- lower connection overhead
- faster failure if the proxy/token path is broken
- less cold-start surprise when the user first speaks

### 4. Shorter AssemblyAI final fallback

Reduce final transcript fallback from 2.8s to 1.2s, while still allowing earlier final delivery when AssemblyAI sends formatted/end-of-turn transcript.

Expected impact:

- shorter hotkey-release-to-agent-start latency

Risk:

- very slow final formatting may be skipped in favor of latest partial transcript
- acceptable for voice commands, where speed matters more than perfect punctuation

## Deferred work

### Realtime OpenAI/Groq transcription socket

Freeflow's `RealtimeTranscriptionService` is a useful pattern, but Lexi does not yet have a Groq API key UX or provider abstraction for direct OpenAI-compatible realtime sockets. Add this after measuring AssemblyAI.

### Upload transcription fallback

Add Groq `/audio/transcriptions` support for longer dictation and non-realtime fallback. This should be a fallback lane, not the main command lane.

### Dedicated transcript cleanup model

Use a small/fast model to clean transcript text only for pure dictation. For agent commands and composition, avoid cleanup first because it adds another network round trip.

### Audio stack rewrite

Freeflow's `AVCaptureSession` stack is more advanced, including device selection and dual output formats. Lexi can adopt this later if AVAudioEngine becomes a bottleneck, but the safer first step is to optimize the existing engine.

## Success metrics

Track these manually from logs first:

- hotkey down → audio engine started
- audio engine started → first partial transcript
- hotkey up → final transcript returned
- final transcript returned → `/compose` or `/explain` request sent
- request sent → first model delta visible

Target for short voice commands:

```text
hotkey release → final transcript: under 1.5s
final transcript → first AI delta: under 1.5s local proxy warm path
```

## Strategic principle

Lexi should optimize for the personal-agent voice loop, not generic long-form transcription. The best path is:

```text
streaming STT
→ immediate intent routing
→ streaming AI output
→ native insertion/action
```

Freeflow validates that the latency moat comes from the whole pipeline, not only the model choice.
