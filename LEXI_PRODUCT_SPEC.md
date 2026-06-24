# Lexi Product Specification and Project Summary

Last updated: 2026-06-24

## 1. Product overview

Lexi is a native macOS menu-bar assistant for instant, context-aware explanations while reading, working, or learning. Its core job is to remove the context-switching cost of looking up unfamiliar words, concepts, interfaces, charts, screenshots, or dense text.

The product is designed around three principles:

1. **Stay in flow.** Explanations should appear where the user already is, without opening a browser tab or chat app.
2. **Use context.** Lexi should use selected text, surrounding passage, app/window metadata, screenshots, and optionally voice questions to infer what the user actually wants to know.
3. **Give immediate feedback.** Every user action should produce visible state: captured, loading, streaming, nested lookup pending, permission missing, or error.

## 2. Current product identity

- Product name: Lexi
- Platform: macOS
- App type: menu-bar utility / accessory app
- Primary repo: `/Volumes/T7/Projects/Jeremy/Lexi`
- Installed app path used during development: `/Applications/Lexi.app`
- Proxy URL currently used in app settings: `https://lexi-production-9152.up.railway.app`
- Local proxy default: `http://127.0.0.1:8787`
- Bundle identifier: `com.jeremyro.lexi`
- Current packaged version observed in builds: `0.2.0 (25)`

## 3. Current architecture

### 3.1 macOS app

Lexi is a Swift Package Manager macOS app using AppKit and SwiftUI together.

Key responsibilities:

- Register global shortcuts.
- Capture selected text across apps.
- Show floating explanation UI.
- Support nested lookups inside existing explanations.
- Coordinate Buddy Capture screenshot + optional voice input.
- Manage permissions and settings.
- Stream answers from the proxy.

Important files:

- `Sources/Lexi/LexiApp.swift` — SwiftUI app entry point with `AppDelegate` adaptor.
- `Sources/Lexi/AppDelegate.swift` — central app wiring: menu bar, hotkeys, panel callbacks, Buddy Capture, proxy checks, streaming explanation requests.
- `Sources/Lexi/Hotkey/HotkeyManager.swift` — Option+Space release hotkey for text explanation and nested lookup.
- `Sources/Lexi/Panel/RawCapturePanelController.swift` — floating answer panel, loading states, nested lookup UI, Buddy Capture states.
- `Sources/Lexi/Selection/SelectionCapture.swift` — selected-text capture path.
- `Sources/Lexi/Network/ExplainClient.swift` — Swift HTTP/SSE client for `/health` and `/explain`.
- `Sources/Lexi/Settings/SettingsWindowController.swift` — Settings UI.
- `Sources/Lexi/Views/PermissionOnboardingView.swift` — consolidated permission onboarding.

### 3.2 Buddy Capture subsystem

Buddy Capture is the multimodal feature that combines a screen region with an optional spoken question.

Important files:

- `Sources/Lexi/Buddy/BuddyCaptureCoordinator.swift` — Buddy Capture state machine.
- `Sources/Lexi/Buddy/BuddyHotkeyMonitor.swift` — Option+Command release detection and Esc cancellation.
- `Sources/Lexi/Buddy/BuddyOverlayController.swift` — full-screen capture overlay and drag selection UI.
- `Sources/Lexi/Buddy/RegionScreenshotCapture.swift` — ScreenCaptureKit screenshot capture, crop, downscale, JPEG compression.
- `Sources/Lexi/Buddy/BuddyVoiceCapture.swift` — microphone/speech transcription path.
- `Sources/Lexi/Buddy/BuddyPermissions.swift` — Accessibility, Screen Recording, Microphone, and Speech Recognition status/request helpers.

### 3.3 Proxy backend

Lexi uses a Node.js/TypeScript Express proxy to talk to Anthropic and stream responses back to the app.

Important files:

- `proxy/src/server.ts` — Express app, auth, `/health`, `/explain`, SSE streaming, error classification.
- `proxy/src/prompt.ts` — prompt construction for text, nested, and Buddy Capture requests.
- `proxy/package.json` — proxy scripts and dependencies.
- `proxy/railway.json` and `railway.json` — Railway deployment config.
- `scripts/deploy_railway_proxy.sh` — typecheck/build/deploy helper for Railway.

Current proxy behavior:

- `GET /health` returns model, nested model, vision model, body limit, and configuration status.
- `POST /explain` handles:
  - text explanation
  - nested explanation
  - Buddy Capture image + question explanation
- Responses stream as Server-Sent Events with `meta`, `timing`, `delta`, `error`, and `done` events.
- Railway proxy has been redeployed with the updated health fields and body limit.

Current verified deployed `/health` shape:

```json
{
  "ok": true,
  "model": "claude-sonnet-4-6",
  "nestedModel": "claude-sonnet-4-6",
  "visionModel": "claude-sonnet-4-6",
  "jsonBodyLimit": "25mb",
  "anthropicApiKeyConfigured": true,
  "proxyTokenConfigured": true
}
```

## 4. Implemented user-facing features

### 4.1 Menu-bar app shell

Implemented:

- Lexi runs as a menu-bar/accessory app.
- Status item appears in the macOS menu bar.
- Menu actions include:
  - Enable/Disable
  - Settings
  - Hotkeys
  - Start Buddy Capture
  - Re-check Permissions
  - Check Proxy Status
  - Copy Last Answer
  - Quit Lexi

Primary implementation:

- `AppDelegate.swift`

### 4.2 Settings window

Implemented:

- Settings window opens on launch/reopen.
- Proxy URL field.
- Proxy token field.
- Reset to local proxy.
- Reset to Railway proxy.
- Save settings.
- Check proxy status.
- Displays:
  - online status
  - text model
  - nested model
  - vision model
  - proxy body limit
  - local token status
  - backend API key status
  - backend proxy token status
- Displays shortcut instructions.
- Provides manual Start Buddy Capture button.
- Displays permission statuses and buttons to open relevant macOS settings panes.
- Displays installed bundle ID, app path, and version.

Primary implementation:

- `SettingsWindowController.swift`

### 4.3 Permission onboarding

Implemented:

- Consolidated permission onboarding for:
  - Accessibility
  - Screen Recording
  - Microphone
  - Speech Recognition
- Re-check permissions flow.
- Settings UI shows current permission status.
- Package script includes required Info.plist usage strings.

Primary implementation:

- `BuddyPermissions.swift`
- `PermissionOnboardingView.swift`
- `scripts/package_app.sh`

### 4.4 Highlighted text explanation

Implemented:

- User highlights text in another app.
- User holds Option+Space and releases.
- Lexi captures selected text and surrounding context.
- Lexi shows a floating panel.
- Panel streams answer from proxy.
- Last answer can be copied from menu.

Current shortcut:

- Hold Option+Space, then release.

Primary implementation:

- `HotkeyManager.swift`
- `SelectionCapture.swift`
- `AppDelegate.swift`
- `RawCapturePanelController.swift`
- `ExplainClient.swift`

### 4.5 Raw capture / answer panel

Implemented:

- Floating non-intrusive panel.
- Captured selection metadata display.
- Loading state.
- Streaming answer state.
- Final answered state.
- Error state.
- No-selection state.
- Permission-missing state.
- Buddy-specific states:
  - Buddy starting message
  - Buddy loading
  - Buddy streaming
  - Buddy error
  - Buddy permission missing
- Reduced-motion support for loading indicators.

Primary implementation:

- `RawCapturePanelController.swift`

### 4.6 Nested definitions / drill-down lookups

Implemented:

- User can highlight a word/phrase inside a Lexi answer.
- Option+Space release while panel is visible requests a nested explanation.
- Right arrow also supports drill-down or re-opening latest child.
- Left arrow pops back up the navigation stack.
- Nested lookup stack tracks root, parent, child, depth, answer, and source context.
- Pending child lookup appears immediately instead of waiting for a completed answer.
- Live selected text is now read directly from the active `NSTextView`, fixing stale/cached selection issues.

Current controls:

- Highlight inside answer + hold Option+Space then release: create nested lookup.
- Right arrow: drill down or reopen latest child.
- Left arrow: pop up.
- Esc: close panel.

Primary implementation:

- `LookupNavigationStack.swift`
- `RawCapturePanelController.swift`
- `AppDelegate.swift`
- `ExplainClient.swift`
- `proxy/src/prompt.ts`
- `proxy/src/server.ts`

### 4.7 Buddy Capture screenshot mode

Implemented:

- User can start Buddy Capture from:
  - Settings button
  - menu-bar item
  - Option+Command release shortcut
- Buddy Capture shows visible starting feedback.
- Full-screen overlay appears for region selection.
- Overlay uses an `NSPanel` wrapper rather than a fragile custom `NSWindow` subclass, fixing a crash on start.
- Overlay handles mouse/trackpad drag directly.
- Dragging creates a visible selection rectangle.
- Releasing mouse/trackpad finishes capture.
- Esc cancels active Buddy Capture.
- ScreenCaptureKit captures the selected region.
- Lexi excludes its own overlay/panel windows from screen capture where possible.
- Captured image is cropped, downscaled, JPEG-compressed, base64-encoded, and sent to the proxy.
- If microphone or speech permissions are missing, screenshot capture still works and voice is treated as optional.
- If no region exists, the coordinator can fall back to focused-window capture where available.

Current intended shortcut:

- Hold Option+Command, release to enter Buddy Capture.
- Drag a region.
- Release mouse/trackpad to submit.

Primary implementation:

- `BuddyCaptureCoordinator.swift`
- `BuddyHotkeyMonitor.swift`
- `BuddyOverlayController.swift`
- `RegionScreenshotCapture.swift`
- `BuddyVoiceCapture.swift`
- `AppDelegate.swift`

### 4.8 Buddy Capture voice input

Implemented:

- Optional microphone + Speech Recognition transcription during Buddy Capture.
- Transcript appears in the overlay caption when available.
- If voice is unavailable, overlay still allows screenshot-only capture.

Primary implementation:

- `BuddyVoiceCapture.swift`
- `BuddyCaptureCoordinator.swift`
- `BuddyPermissions.swift`

### 4.9 Buddy Capture image transport and 413 handling

Implemented:

- Client aggressively downscales/compresses Buddy Capture images before upload.
- Client targets a small encoded image size to avoid Railway/proxy payload rejection.
- Proxy body limit is configurable with `LEXI_JSON_BODY_LIMIT` and defaults to `25mb`.
- Proxy returns structured `payload_too_large` errors for oversized JSON bodies.
- Proxy classifies Anthropic-side image-too-large errors.
- Swift client maps HTTP 413 and `payload_too_large` to a user-friendly error.
- Swift client logs request byte counts for debugging.

Current approach:

- Any selected screen region should be allowed.
- Lexi does not send arbitrary original-resolution screenshots.
- Lexi sends a downscaled/compressed representation suitable for transport and model vision input.

Primary implementation:

- `RegionScreenshotCapture.swift`
- `ExplainClient.swift`
- `proxy/src/server.ts`

### 4.10 Proxy deployment to Railway

Implemented:

- Railway project linked:
  - Project: `comfortable-serenity`
  - Service: `lexi`
  - Environment: `production`
- Proxy redeployed successfully with updated Buddy/vision/body-limit code.
- Verified deployed health endpoint includes `visionModel` and `jsonBodyLimit`.

Primary implementation/config:

- `scripts/deploy_railway_proxy.sh`
- `proxy/railway.json`
- `railway.json`

### 4.11 Packaging and installation

Implemented:

- `scripts/package_app.sh` builds release executable and creates `/dist/Lexi.app` bundle.
- Info.plist includes required usage descriptions.
- App is signed ad-hoc by default unless a signing identity is provided.
- Development workflow backs up the existing `/Applications/Lexi.app` before installing a new build.

Primary implementation:

- `scripts/package_app.sh`
- `scripts/build_release.sh`

## 5. Implemented backend features

### 5.1 Text explanation endpoint

Implemented:

- Request validation for term, passage, app name, window title.
- Prompt construction for concise context-aware explanation.
- Streaming Anthropic response via SSE.
- Timing metadata for first token and total completion.

### 5.2 Nested explanation endpoint behavior

Implemented:

- Nested lookup payload includes lineage:
  - root term
  - root source text
  - parent term
  - parent answer
  - depth
- Uses nested model config, defaulting to main model.
- Produces shorter continuation-style definitions.

### 5.3 Buddy multimodal endpoint behavior

Implemented:

- Buddy request mode.
- Optional image input.
- Optional spoken question.
- App/window context.
- Vision model config, defaulting to main model.
- Buddy-specific system prompt.
- SSE streaming output.

### 5.4 Proxy auth and configuration

Implemented:

- Optional bearer token auth using `LEXI_PROXY_TOKEN`.
- `/health` exempt from auth.
- Anthropic key read from `ANTHROPIC_API_KEY`.
- Models configurable via:
  - `ANTHROPIC_MODEL`
  - `ANTHROPIC_NESTED_MODEL`
  - `ANTHROPIC_VISION_MODEL`
- Body limit configurable via:
  - `LEXI_JSON_BODY_LIMIT`

## 6. Current known limitations and risks

### 6.1 Buddy Capture image fidelity

Full-screen region selection is supported conceptually, but the image is compressed/downscaled before upload. This is necessary because screenshots travel through JSON/base64, the Railway proxy, and Anthropic's vision API. The risk is that tiny text or dense dashboards may become unreadable after aggressive compression.

Potential solution:

- Send a low-resolution overview plus one or more high-resolution tiles/crops.
- Add OCR and send extracted text alongside the image.
- Let users choose “high detail” for small/dense regions.

### 6.2 Buddy Capture request size ambiguity

Before the Railway redeploy, the deployed proxy rejected requests around 56–66 KB despite local code allowing more. The proxy has now been redeployed with a 25 MB body limit, but practical upstream limits may still exist at Railway, reverse proxy, or Anthropic layers.

Potential solution:

- Keep app-side byte logging.
- Add proxy request-size logging.
- Add a `/debug/limits` endpoint or include body limit in `/health` as currently done.
- Add client-side adaptive retry: if 413 occurs, recompress smaller and retry once.

### 6.3 Global hotkey reliability

Modifier-only hotkeys can be brittle on macOS, especially with Accessibility/TCC state. Manual menu/settings Buddy Capture fallback is implemented and should remain.

Potential solution:

- Add configurable shortcut recorder.
- Use a less ambiguous hotkey such as Control+Option+Space if preferred.
- Display hotkey detection status in Settings.

### 6.4 Permission/TCC state

macOS Screen Recording and Accessibility permissions are tied to app identity and install path. Replacing app bundles repeatedly during development can leave stale TCC entries.

Potential solution:

- Add Settings diagnostics showing exact bundle path, bundle ID, and permission status.
- Add a “copy reset instructions” button for TCC troubleshooting.
- Eventually ship with stable signing/notarization.

### 6.5 Documentation drift

Older docs still mention Function-key and older Option+Command highlight flows. The actual current flow is Option+Space release for text lookup and Option+Command release for Buddy Capture.

Potential solution:

- Update `README.md`, `PROJECT_SUMMARY.md`, and `TESTING.md` to match this spec.
- Treat this file as the current canonical spec.

### 6.6 Persona/inference system not fully integrated

The inference docs describe a richer persona-aware query inference system. The current shipping path uses prompt logic and captured context, but does not expose a full persona setup UI or advanced inference configuration.

Potential solution:

- Add persona/learning style settings.
- Route prompt generation through a unified inference layer.
- Add privacy-sensitive detection before sending context.

## 7. Product roadmap

### Phase 1: Stabilize daily-use reliability

Priority: highest.

Goals:

- Buddy Capture should work reliably from Settings, menu, and hotkey.
- Text lookup should reliably show loading and streaming states.
- Nested lookup should visibly create a child lookup immediately.
- Errors should tell the user what happened and what to do next.

Work items:

1. Add client-side adaptive retry for Buddy 413 errors.
2. Add proxy request-size logging for Buddy captures.
3. Add “recent diagnostic events” in Settings.
4. Add hotkey status diagnostics.
5. Add crash/log inspection notes to testing docs.
6. Update all stale user-facing docs.

Success criteria:

- No silent failures.
- No app termination on Buddy Capture start.
- Full-screen Buddy Capture produces either an answer or a clear recoverable error.
- Nested lookup pending state appears immediately.

### Phase 2: Improve Buddy Capture answer quality

Priority: high.

Goals:

- Full-screen captures should be accepted without losing necessary visual detail.
- Dense text, charts, and UI screenshots should be legible to the model.

Work items:

1. Add OCR extraction for selected region.
2. Send OCR text alongside compressed screenshot.
3. Add image tiling for large/full-screen captures:
   - low-resolution overview
   - high-resolution focused tiles
4. Add “high detail” retry path when model cannot read text.
5. Include screenshot dimensions and compression metadata in proxy logs.
6. Optionally show captured thumbnail in the Buddy result panel.

Success criteria:

- Buddy Capture can explain full-screen UI/chart/context.
- Tiny text failures are reduced by OCR/tile fallback.
- Average Buddy response remains fast enough for interactive use.

### Phase 3: Settings and personalization

Priority: high.

Goals:

- Users should configure how Lexi explains things.
- Users should understand which backend/model is active.

Work items:

1. Add learning style selector:
   - simple
   - technical
   - analogy
   - examples
   - visual
2. Add persona selector:
   - General
   - Go-to-Market
   - Technical
   - Executive
   - Student
3. Add output length setting.
4. Add model configuration UI.
5. Add custom prompt fields.
6. Add Settings reset/export/import.

Success criteria:

- User can tune Lexi without editing code or environment variables.
- Settings accurately reflect the deployed proxy and active app config.

### Phase 4: History, cache, and learning memory

Priority: medium.

Goals:

- Lexi should become more useful over time.
- Repeated lookups should be instant.

Work items:

1. Add local cache for text lookups.
2. Add cache for nested lookups.
3. Add lookup history.
4. Add “recently learned” dashboard.
5. Add search over past explanations.
6. Add export history.
7. Add privacy controls for local storage.

Success criteria:

- Repeated terms return quickly.
- User can revisit prior explanations.
- History remains local and user-controlled.

### Phase 5: Context inference and privacy layer

Priority: medium.

Goals:

- Lexi should infer the user’s likely question more intelligently.
- Sensitive content should be detected before sending to the proxy.

Work items:

1. Integrate persona-aware inference models from existing docs.
2. Classify app category:
   - browser
   - code editor
   - messaging
   - social media
   - document/PDF
   - terminal
3. Classify term type:
   - technical jargon
   - slang
   - acronym
   - proper noun
   - general vocabulary
4. Add privacy checks for secrets, tokens, passwords, financial data, and personal identifiers.
5. Add confidence score internally.
6. Add fallback strategies for ambiguous text.

Success criteria:

- Explanations adapt more clearly to app/context/persona.
- Lexi avoids sending obviously sensitive content.

### Phase 6: Expanded input/output modes

Priority: medium/low.

Work items:

1. Pronunciation guide.
2. Text-to-speech output for answers.
3. Multi-language explanations.
4. Translation mode.
5. PDF/image OCR mode.
6. Follow-up questions inside the panel.
7. Copy/share/export answer actions.

### Phase 7: Distribution hardening

Priority: medium.

Work items:

1. Stable Developer ID signing.
2. Notarization.
3. Versioned release ZIP/DMG.
4. Auto-update strategy.
5. Cleaner permission reset flow.
6. Documented install/uninstall steps.

## 8. Recommended immediate next steps

1. **Test Buddy Capture after Railway redeploy.**
   - Try small region.
   - Try medium region.
   - Try full screen.
   - Confirm no 413.
   - Confirm generated answer quality.

2. **Add adaptive 413 retry.**
   - If proxy returns 413, client recompresses image smaller and retries once automatically.

3. **Add OCR for Buddy Capture.**
   - This is the right way to support full-screen captures without sending giant images.

4. **Polish nested lookup UI.**
   - Make pending child lookups visually obvious.
   - Show tab/chip loading state.
   - Automatically jump to the new child.

5. **Update README and TESTING docs.**
   - Replace old Function-key flow.
   - Document Option+Space release and Option+Command Buddy Capture.
   - Add Railway deploy procedure.

6. **Add a diagnostics panel.**
   - Recent hotkey events.
   - Recent capture sizes.
   - Last proxy request bytes.
   - Last HTTP status.
   - Active proxy URL.
   - Proxy health result.

## 9. Verification commands

Swift app build:

```bash
swift build --package-path "/Volumes/T7/Projects/Jeremy/Lexi"
```

Proxy typecheck:

```bash
npm run typecheck --prefix "/Volumes/T7/Projects/Jeremy/Lexi/proxy"
```

Proxy build:

```bash
npm run build --prefix "/Volumes/T7/Projects/Jeremy/Lexi/proxy"
```

Package app:

```bash
"/Volumes/T7/Projects/Jeremy/Lexi/scripts/package_app.sh"
```

Deploy Railway proxy:

```bash
"/Volumes/T7/Projects/Jeremy/Lexi/scripts/deploy_railway_proxy.sh"
```

Verify deployed proxy:

```bash
curl -sS "https://lexi-production-9152.up.railway.app/health"
```

Expected deployed proxy health should include:

```json
{
  "visionModel": "claude-sonnet-4-6",
  "jsonBodyLimit": "25mb"
}
```

## 10. Current status

Lexi now has a working foundation for:

- text lookup
- streaming explanations
- nested definitions
- Settings UI
- permission onboarding
- Buddy Capture overlay
- Buddy screenshot capture
- optional Buddy voice capture
- Railway proxy deployment
- multimodal proxy support

The next major product challenge is not basic feature existence. It is reliability and answer quality under real-world conditions, especially for Buddy Capture with large/dense screenshots.
