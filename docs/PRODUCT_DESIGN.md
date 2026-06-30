# Lexi Product Design Document

This document is derived strictly from the current codebase. It describes observed behavior, state, copy, and routing only.

---

## 1. Overview

**Lexi** is a macOS accessory-mode app that lives in the menu bar and helps users understand or transform text in place.

- App lifecycle is anchored in `Sources/Lexi/LexiApp.swift` and `Sources/Lexi/AppDelegate.swift`.
- `LexiApp` installs `AppDelegate` via `@NSApplicationDelegateAdaptor` and exposes an empty SwiftUI settings scene.
- `AppDelegate` sets the app to `.accessory`, creates the status item, manages onboarding, hotkeys, capture flows, the answer panel, settings, diagnostics, and text-to-speech.
- The app talks to a local or hosted Node proxy through `Sources/Lexi/Network/ExplainClient.swift`.
- The proxy in `proxy/src/server.ts` streams assistant output over SSE and can also request web research, temporary AssemblyAI tokens, and ElevenLabs TTS.

The mental model is:

1. The user triggers one of three gestures.
2. Lexi captures either highlighted text, a screen region, or voice input.
3. The proxy generates an explanation, follow-up, or composition result.
4. Lexi shows the result in a pill/panel UI and can optionally speak it aloud or insert it back into the active editor.

---

## 2. Core concepts / glossary

| Concept | Precise meaning in code |
|---|---|
| Buddy Capture | The screen-region / spoken-question capture flow driven by `BuddyCaptureCoordinator`, `BuddyOverlayController`, `BuddyVoiceCapture`, and `RegionScreenshotCapture`. |
| Nested Lookup | A lookup initiated from inside an existing Lexi answer, tracked by `LookupNavigationStack` lineage and answered by `ExplainClient.explainNested` / `proxy buildUserMessage` lineage payloads. |
| Lineage | The parent/child structure of lookup nodes (`LookupNavigationStack`, `LookupNode`) that preserves root term, current node, and nested children. |
| Pill vs Panel | The answer UI can stay collapsed to a small pill or expand into a panel; `RawCapturePanelController` decides when it can collapse and when hover re-expands it. |
| Callout | A `[CALLOUT:x,y:label]` suffix parsed from buddy model output by `BuddyCalloutParser`; it positions a floating label over the source screenshot. |
| Cursor Buddy | The floating cursor-following activity indicator controlled by `BuddyCursorFollowerController` with states like idle, listening, selecting, working, streaming, and error. |
| Research Mode | Proxy-side web grounding via Perplexity; enabled by `proxy/src/server.ts` planning logic and injected into prompt builders as `WEB RESEARCH CONTEXT`. |
| Compose / Command | The text-writing/editing flow that uses `CompositionIntentDetector`, `ActiveTextContextCapture`, and `StreamingTextInserter` to insert or replace text in the active editor. |
| Session Memory | Short-lived recent context stored in `ResearchSessionMemory` and event history persisted by `LexiInteractionEventStore` for grounding future requests. |

---

## 3. Permissions model

Lexi’s permissions are defined by `BuddyPermission` and queried/requested through `BuddyPermissions`.

| Permission | Why needed | Features gated | How requested / rechecked | Blocked-state behavior |
|---|---|---|---|---|
| Accessibility | “Read highlighted text and run global hotkeys.” | Highlight lookup, composition, deletion, frontmost-window inspection, selected text capture, active text context capture, and global hotkey support. | `BuddyPermissions.request(.accessibility)` prompts via `AXIsProcessTrustedWithOptions(...)`; recheck is via `BuddyPermissions.status(.accessibility)` and menu/settings flows. | `SelectionCapture` returns `.accessibilityPermissionMissing`; the answer panel shows `.noPermission`; settings prompt users to re-check. |
| Screen Recording | “Capture the region you drag with the buddy.” | Buddy region capture, focused-window capture, cursor-screen capture, and screen-region explanations. | `BuddyPermissions.request(.screenRecording)` calls `CGRequestScreenCaptureAccess()` on a background queue; recheck uses `CGPreflightScreenCaptureAccess()`. | Buddy flows surface `.buddyPermissionMissing([.screenRecording, ...])` or capture errors like “Screen capture failed. Check Screen Recording permission.” |
| Microphone | “Hear your spoken question while you hold the key.” | Voice capture for both hold-to-talk lookup and Buddy capture. | `BuddyPermissions.request(.microphone)` uses `AVCaptureDevice.requestAccess(for: .audio)`. | Voice capture throws `microphonePermissionMissing`; Buddy quick capture emits “Microphone permission is required for push-to-talk Buddy Capture.” |
| Speech Recognition | “Transcribe your question on-device.” | Required for Apple Speech voice provider; also used in Buddy hold-to-talk when the provider is Apple Speech. | `BuddyPermissions.request(.speechRecognition)` uses `SFSpeechRecognizer.requestAuthorization`; recheck uses `SFSpeechRecognizer.authorizationStatus()`. | If Apple Speech is selected and speech permission is missing, voice capture throws `speechPermissionMissing`; Buddy quick capture emits “Speech Recognition permission is required for Apple Speech. Switch to AssemblyAI after configuring the proxy, or enable Speech Recognition.” |

`BuddyPermissions.requiredPermissions` includes Accessibility, Screen Recording, and Microphone always, plus Speech Recognition only when `AppConfiguration.voiceProvider == .appleSpeech`.

**⚠️ Notes for the designer**

- Accessibility is treated specially: `BuddyPermissions.status(.accessibility)` only reports `.granted` or `.notDetermined`; there is no distinct denied case in this wrapper.
- `BuddyPermissions.buddyReady` excludes Accessibility on purpose; the Buddy gesture can be partially ready while still needing Accessibility for the broader app.

---

## 4. Onboarding & first-run journey

Onboarding is the most detailed flow in the app and is split across:

- `Sources/Lexi/AppDelegate.swift`
- `Sources/Lexi/Onboarding/WelcomeWindowController.swift`
- `Sources/Lexi/Onboarding/WelcomeFlowView.swift`
- `Sources/Lexi/Onboarding/GestureDemoView.swift`
- `Sources/Lexi/Onboarding/HomeView.swift`
- `Sources/Lexi/Onboarding/AppMarkView.swift`
- `Sources/Lexi/Onboarding/OnboardingStyle.swift`
- `Sources/Lexi/Views/PermissionOnboardingView.swift`

### 4.1 First launch gating

`AppDelegate.presentFirstRunIfNeeded()` checks `hasCompletedFirstRun`, which is stored in `UserDefaults` under `LexiHasCompletedFirstRun`.

- If the flag is `false`, `showWelcome()` is called.
- `showWelcome()` creates `WelcomeWindowController` once, shows the window, makes it key and frontmost, and activates the app.
- The completion callback passed to `WelcomeWindowController` sets `hasCompletedFirstRun = true` and nils out `welcomeWindow`.
- The menu bar item also contains **“Welcome to Lexi…”** as a replay action, so onboarding is not one-time-only.

`WelcomeWindowController`:

- Window title: **“Welcome to Lexi”**
- Fixed content size: `720 x 560`
- Calls the completion closure when the window closes
- Guards completion so it only fires once

### 4.2 Welcome flow structure

`WelcomeFlowView.Page` is a four-step flow:

1. `.hello`
2. `.gesture`
3. `.permissions`
4. `.allSet`

Navigation is sequential with back/continue controls and optional skip.

#### Page 1: Hello

Observed copy:

- **“Hold, highlight, understand.”**
- **“Lexi explains anything you’re reading — right where you are.”**

This page establishes the app’s core promise.

#### Page 2: Gesture

Observed copy:

- **“Your first move”**
- **“Hold ⌥ Space, highlight anything, then let go.”**
- **“Lexi follows your highlight, then gives you the short version — fast and calm.”**

This page introduces the main gesture and is visually reinforced by `GestureDemoView`.

#### Page 3: Permissions

Observed copy:

- **“A couple of quick permissions”**
- **“They help Lexi listen, read the spot you point to, and stay in step with your highlight.”**
- **“You can change these anytime in System Settings.”**

This page transitions the user into the permission model.

#### Page 4: All set

Observed copy:

- **“You’re all set”**
- **“A few gestures to keep close by:”**

Gesture cheat sheet rows:

- **“Explain highlighted text”** — **“Hold ⌥ Space”**
- **“Ask about a screen region”** — **“Hold ⌥⌘ and drag”**
- **“Ask out loud”** — **“Hold ⌃⌥ and speak”**
- **“Inside an answer”** — **“Highlight a phrase and press →”**

Final button:

- **“Start using Lexi”**

### 4.3 Gesture demo

`GestureDemoView` animates the main highlight lookup gesture.

- It highlights the phrase **“highlight anything”**
- It displays the explanation **“Lexi opens beside you with a calm explanation, then fades away.”**
- It shows a mock document, a keycap, and a floating answer card
- It respects reduce motion

### 4.4 Home popover / menu-bar home

`HomeView` is the home surface shown from the status item or as a fallback window.

Observed copy:

- Title: **“Lexi”**
- Subtitle: **“A calm little sidekick”**
- Status text: **“Listening for ⌥ Space”** or **“Paused”**

Cheat sheet items:

- **“Explain highlighted text”** / **“Hold ⌥ Space”**
- **“Precise Buddy”** / **“Hold ⌥⌘ and drag”**
- **“Quick Buddy”** / **“Hold ⌃⌥ and speak”**
- **“Inside an answer”** / **“Highlight + →”**

Buttons:

- **“Start Buddy”**
- **“Pause Lexi”** / **“Resume Lexi”**
- **“Getting started”**
- **“Settings…”**
- **“Quit Lexi”**

`AppMarkView` is a thin wrapper around `LexiBrandMark(size:)` and is the app badge used throughout onboarding.

### 4.5 Permission onboarding

`PermissionOnboardingView` shows per-permission rows, status pills, and request actions.

Observed statuses:

- **“Allowed”**
- **“Needs attention”**
- **“Not yet”**

Buttons:

- **“Re-check”**
- **“Allow”**
- **“Open Settings”**

Permission-specific benefit copy:

- Accessibility: **“So Lexi can read the text you highlight.”**
- Screen Recording: **“So Lexi can see the area you point at.”**
- Microphone: **“So you can just ask out loud.”**
- Speech Recognition: **“So your spoken questions turn into text.”**

The view requests the selected permission, then opens system settings for it.

### 4.6 First-run completion and replay

Completion is set only when the welcome window’s completion callback runs. Replay is available from the status menu via **“Welcome to Lexi…”**.

**⚠️ Notes for the designer**

- The code does not show a separate first-run analytics event; the only persistence is the `LexiHasCompletedFirstRun` boolean.
- The welcome flow and the menu-bar home both activate the app on presentation, so they are treated as primary surfaces, not passive tooltips.

---

## 5. The three input gestures

### 5.1 Option + Space hold

Implemented by `HotkeyManager.registerOptionSpace(...)` and handled in `AppDelegate.beginLookupHotkeyHold()` / `finishLookupHotkeyHold()`.

Behavior:

- Pressing Option+Space starts a hold state and arms either text selection or voice capture.
- Releasing Option+Space finalizes the capture.
- If Lexi is disabled, the gesture is ignored.

What it can do on release:

1. If the answer panel is already visible, release is treated as a nested-lookup attempt from the currently selected answer text.
2. Otherwise, Lexi captures selected text via `SelectionCapture.capture()`.
3. If the spoken question or selected text matches a composition intent, Lexi routes into compose/edit.
4. If the spoken question or selected text matches a whole-deletion intent, Lexi routes into delete-selection.
5. Otherwise Lexi opens the explanation panel.

Cancel conditions:

- No active hold state
- Lexi disabled
- No selection and no spoken question
- Permission failures
- Capture failures
- Non-writable target when trying to compose or delete

### 5.2 Option + Command drag

Implemented by `BuddyHotkeyMonitor` and orchestrated by `BuddyCaptureCoordinator`.

Behavior:

- Pressing Option+Command begins Buddy capture.
- Dragging draws a rubber-band selection overlay.
- Releasing finalizes the region.
- Pressing Escape during active capture cancels.

What it captures:

- The dragged screen region
- Optional spoken question if the microphone is available and voice capture starts
- OCR text from the captured image

Fallbacks:

- If no region is drawn, quick capture may fall back to the focused window or cursor screen depending on path
- If voice is not enabled, the overlay still appears and the user can drag only

### 5.3 Control + Option hold

Implemented by `BuddyPushToTalkMonitor`.

Behavior:

- Holding Control+Option starts quick Buddy capture.
- Releasing Control+Option finalizes the spoken question and screen-context capture.
- The monitor uses flags only; it does not require a drag.

Fallback capture:

- Tries the focused window first
- If none is available, tries the cursor screen

Cancel conditions:

- Missing microphone permission
- Missing Speech Recognition permission when using Apple Speech
- Empty question plus no screenshot

---

## 6. Feature flows

### 6.1 Highlight lookup

Relevant symbols:

- `AppDelegate.finishLookupHotkeyHold(spokenQuestion:hotkeyStartedAt:)`
- `SelectionCapture.capture()`
- `SelectionCaptureStatus`
- `ExplainClient.explain(...)`
- `AppDelegate.requestExplanation(for:hotkeyStartedAt:)`
- `RawCapturePanelController.show/update(status:)`

Flow:

1. User holds Option+Space.
2. `SelectionCapture.capture()` tries Accessibility first.
3. If selection exists, the capture includes:
   - `term`
   - `passage`
   - `windowTitle`
   - `appName`
   - `anchorRect`
   - `source`
   - optional `question`
4. The panel enters `.loading`.
5. `ExplainClient.explain(...)` streams answer tokens.
6. The panel moves through `.streaming` and then `.lookup`.
7. The answer is stored in `lastAnswer`, `ResearchSessionMemory`, and `LexiInteractionEventStore`.
8. If read-aloud is enabled, `ElevenLabsTTSClient.speak(...)` runs.

Edge cases:

- If the capture returns `.noSelection`, Lexi may still interpret the spoken phrase as compose/delete/ask-about-screen.
- If Accessibility permission is missing, the panel shows `.noPermission`.
- If the proxy call fails, the panel shows `.error(...)` with the proxy error string or a fallback message.

### 6.2 Buddy region capture

Relevant symbols:

- `AppDelegate.startBuddyCapture()`
- `BuddyCaptureCoordinator`
- `BuddyOverlayController`
- `BuddyVoiceCapture`
- `RegionScreenshotCapture.captureRegion(_:)`
- `AppDelegate.requestBuddyExplanation(for:)`
- `ExplainClient.explainBuddy(...)`

Flow:

1. User starts Buddy from the menu or the Option+Command gesture.
2. `BuddyCaptureCoordinator` shows the overlay and begins voice capture if permissions allow.
3. The user drags a region.
4. On release, the overlay hides, voice is stopped, and the final question / screenshot / OCR / metadata are packaged into `BuddyCaptureContext`.
5. `requestBuddyExplanation(for:)` shows `.buddyLoading`.
6. `ExplainClient.explainBuddy(...)` streams output.
7. The panel transitions to `.lookup(LookupNavigationStack)` using the final answer.
8. If the model emits a callout tag, `BuddyCalloutOverlayController` is shown.

Possible messages and errors:

- “Drag anywhere on the screen to capture”
- “Finalizing”
- “Transcribing and capturing your current screen context…”
- “Microphone permission is required for push-to-talk Buddy Capture.”
- “Speech Recognition permission is required for Apple Speech. Switch to AssemblyAI after configuring the proxy, or enable Speech Recognition.”
- “Voice unavailable; drag to capture”

### 6.3 Quick Buddy question / current-screen answer

Relevant symbols:

- `BuddyPushToTalkMonitor`
- `BuddyCaptureCoordinator.beginQuickCapture()`
- `AppDelegate.requestFocusedScreenAnswer(question:fallbackAppName:fallbackWindowTitle:)`

Flow:

1. User holds Control+Option.
2. Lexi starts microphone capture and shows a listening message.
3. On release, Lexi finalizes the spoken question.
4. It captures the focused window if possible; otherwise the cursor screen.
5. It also samples visible text context from the active editor.
6. If there is neither screenshot nor text context, Lexi shows an error hint.
7. Otherwise it sends a Buddy explanation request with `modeLabel: "Current screen"`.

Key copy:

- “Listening”
- “Speak your question, then release Control + Option.”
- “Finalizing”
- “Transcribing and capturing your current screen context…”
- “Couldn’t read current screen”

### 6.4 Nested Lookup

Relevant symbols:

- `RawCapturePanelController.requestNestedLookup(term:)`
- `RawCapturePanelController.beginNestedLookup(term:)`
- `AppDelegate.requestNestedExplanation(term:stack:)`
- `ExplainClient.explainNested(...)`
- `LookupNavigationStack.pushPending(...)`

Flow:

1. The user is already looking at an answer.
2. They highlight a phrase inside the answer and press →, or the panel selects the term automatically.
3. Lexi creates a child lookup node.
4. `ExplainClient.explainNested(...)` sends lineage: root term, root source text, parent term, parent answer, depth, and the highlighted term.
5. The new answer streams into the child node.
6. The panel keeps the lineage path visible.

If nested lookup fails:

- The child node answer is replaced with the error message.
- `lastAnswer` is set to that message.
- The menu is rebuilt so “Copy Last Answer” reflects the latest text.

### 6.5 Follow-up

Relevant symbols:

- `RawCapturePanelController.requestFollowUp()`
- `RawCapturePanelController.beginFollowUp(question:)`
- `AppDelegate.requestFollowUp(question:stack:)`
- `ExplainClient.explainFollowUp(...)`

Flow:

1. In an answer panel, the user types a follow-up question in the field labeled **“Ask a follow-up…”**.
2. Enter or the **“Enter”** button triggers the request.
3. A child node is appended to the lookup stack.
4. The proxy receives the current lineage plus the question.
5. The answer streams into the new child node.

### 6.6 Compose / Edit

Relevant symbols:

- `CompositionIntentDetector.isCompositionInstruction(_:)`
- `ActiveTextContextCapture.capture(...)`
- `StreamingTextInserter.begin/insert/finish/replaceSelection(...)`
- `AppDelegate.requestComposition(instruction:context:)`

Flow:

1. Option+Space release happens with text that looks like a writing/editing command.
2. Lexi captures the active editor context.
3. `ActiveTextContextCapture` returns:
   - `appName`
   - `windowTitle`
   - `selectedText`
   - `surroundingText`
   - `currentText`
   - `isWritable`
4. `AppDelegate.requestComposition(...)` decides between replace and insert:
   - `context.hasSelection == true` → replace mode
   - `context.hasSelection == false` → insert mode
5. `ExplainClient.compose(...)` streams text.
6. In insert mode, deltas are streamed directly into the editor.
7. In replace mode, Lexi waits for the full answer and replaces the selection in one shot.

Observed hints:

- “Rewriting selection in \(context.appName)…”
- “Composing into \(context.appName)…”
- “Updated selection”
- “Inserted draft”
- “Couldn’t update that selection”
- “Couldn’t compose there”

Replace-vs-insert decision:

- `ActiveTextCompositionContext.hasSelection` is the switch.
- If there is a selection, the code explicitly avoids streaming replacement token-by-token because that can duplicate/drop text and break undo in editors.
- If there is no selection, streaming insert is used so the user sees draft text appear live.

### 6.7 Delete-selection

Relevant symbols:

- `CompositionIntentDetector.isWholeDeletionInstruction(_:)`
- `AppDelegate.requestDeletion(instruction:context:)`
- `StreamingTextInserter.replaceSelection(with:"", allowKeyboardFallback: true)`

Flow:

1. The spoken or typed instruction matches a whole-delete intent.
2. Lexi captures the active editor context.
3. If a selection exists and the target is writable, Lexi deletes it.
4. If accessibility write-back fails, Lexi falls back to keyboard-driven deletion.

Observed hints:

- “Deleting selection…”
- “Deleted selection”
- “Select text to delete”
- “Couldn’t delete there”
- “Click into a text field first”

### 6.8 Research

Relevant symbols:

- `proxy/src/server.ts` `planResearch(...)` / `maybeResearch(...)`
- `proxy/src/prompt.ts` `RESEARCH_SYSTEM_PROMPT`
- `ExplainClient.explain*`

Behavior:

- Research is proxy-controlled, not app-controlled.
- The proxy can use Perplexity when research mode is `auto` and a Perplexity API key exists.
- Research context is injected into the user message as `WEB RESEARCH CONTEXT`.
- The model is instructed to lead with facts when research is present.

### 6.9 Text-to-speech

Relevant symbols:

- `AppDelegate.speakIfEnabled(_:)`
- `ElevenLabsTTSClient.speak(_:configuration:)`
- `proxy/src/server.ts` `/tts`

Behavior:

- Read-aloud only runs if `AppConfiguration.current.isReadAloudEnabled` is true.
- The client posts the final answer to `/tts`.
- The proxy forwards to ElevenLabs with `model_id: "eleven_flash_v2_5"` by default.
- If TTS fails, Lexi logs the failure and does not block the main UX.

### 6.10 Clipboard-backed selection capture

Relevant symbols:

- `SelectionCapture.capture()`
- `ClipboardFallback.copyCurrentSelection()`
- `PasteboardSnapshot`

Behavior:

- `SelectionCapture` tries Accessibility capture first.
- When Accessibility capture does not yield a selection, the clipboard fallback synthesizes Command+C, waits briefly, reads the resulting string, and restores the original pasteboard contents.
- If the clipboard round-trip still does not produce a meaningful selection, the capture resolves as `.noSelection(...)`.

### 6.11 Audio conversion for streaming transcription

Relevant symbols:

- `BuddyPCM16AudioConverter`
- `BuddyAudioConversionSupport.swift`

Behavior:

- Converts `AVAudioPCMBuffer` input to mono PCM16 at the requested sample rate.
- Reuses the converter when the source format stays stable.
- Returns `nil` if the target format cannot be built or conversion fails.
- This is the adapter that prepares audio for the AssemblyAI websocket session.

---

## 7. Answer panel UI states

Implemented primarily in `Sources/Lexi/Panel/RawCapturePanelController.swift`.

### 7.1 Status enum

```swift
enum RawCapturePanelStatus {
    case captured(CapturedSelection)
    case loading(CapturedSelection)
    case streaming(CapturedSelection, String)
    case answered(CapturedSelection, String)
    case lookup(LookupNavigationStack)
    case buddyMessage(title: String, message: String)
    case buddyLoading(BuddyCaptureContext)
    case buddyStreaming(BuddyCaptureContext, String)
    case buddyError(BuddyCaptureContext?, String)
    case buddyPermissionMissing([BuddyPermission])
    case error(CapturedSelection?, String)
    case noSelection(appName: String, windowTitle: String)
    case noPermission
}
```

### 7.2 Collapse and auto-expand model

- `canCollapseToPill` is true for:
  - `.loading`
  - `.streaming`
  - `.answered`
  - `.lookup`
  - `.buddyLoading`
  - `.buddyStreaming`
- `shouldAutoExpandOnEntry` is true for:
  - `.answered`
  - `.lookup` when the current node already has an answer

The panel behaves as:

1. Show a compact pill while work is in progress or after an answer is available.
2. Hover to expand.
3. Collapse again after the configured hover timeout.

### 7.3 Keyboard interactions

- Left arrow (`keyCode == 123`) pops one lookup level.
- Right arrow (`keyCode == 124`) requests nested lookup from selected answer text; if that fails, it jumps to the latest child.
- Escape (`keyCode == 53`) hides the panel.

### 7.4 State content

#### `.captured`

Shows capture details before the request is sent.

#### `.loading`

Shows:

- “Thinking…”
- the capture details beneath it

#### `.streaming` / `.answered`

Shows a chat conversation with:

- “You”
- “Lexi”

#### `.lookup`

Shows the lineage conversation path plus follow-up composer when the current node has an answer.

Observed helper copy in the lookup area includes:

- **“Ask a follow-up…”**
- **“Enter”**

#### `.buddyMessage`

Displays a message plus guidance:

- **“If no full-screen overlay appears, open Settings → Permissions and re-check Accessibility and Screen Recording for Lexi.”**

#### `.buddyLoading`

Shows:

- “Reading your screen…”

#### `.buddyStreaming`

Uses the same conversation renderer as lookup, but titled from the buddy display title.

#### `.buddyError`

Shows:

- “What happened”
- the error message
- capture details if available

#### `.buddyPermissionMissing`

Shows:

- **“Open System Settings and enable these permissions for Lexi, then choose Re-check Permissions from the menu bar.”**

#### `.error`

Shows:

- “What happened”
- the error message
- capture details if available

#### `.noSelection`

Shows:

- **“Hold Option + Space while selecting a word or phrase, then release.”**

If present, it also shows a source chip based on the originating app.

#### `.noPermission`

Shows:

- **“Open Lexi from the menu bar and choose Re-check Accessibility Permission after enabling Lexi in System Settings → Privacy & Security → Accessibility.”**

### 7.5 Exact user-facing strings in the panel

Observed strings include:

- “Thinking…”
- “Reading your screen…”
- “You”
- “Lexi”
- “Ask a follow-up…”
- “Enter”
- “What happened”
- “Open System Settings and enable these permissions for Lexi, then choose Re-check Permissions from the menu bar.”
- “Hold Option + Space while selecting a word or phrase, then release.”
- “Open Lexi from the menu bar and choose Re-check Accessibility Permission after enabling Lexi in System Settings → Privacy & Security → Accessibility.”

**⚠️ Notes for the designer**

- The panel uses both “pill” and “panel” states, but the code’s exact collapse/expand timings are implemented in view logic rather than a named state machine.
- In the lookup flow, right-arrow behavior is dual-purpose: if there is selected answer text, it initiates a nested lookup; otherwise it jumps to the latest child.

---

## 8. Cursor Buddy states

Implemented in `Sources/Lexi/Buddy/BuddyCursorFollowerController.swift`.

### 8.1 Activity enum

```swift
enum BuddyCursorFollowerActivity: Equatable {
    case idle
    case listening
    case selecting
    case working
    case streaming
    case error
}
```

### 8.2 State transitions

- `start()` creates one non-activating panel per screen and begins a 60 FPS timer.
- `setActivity(_:)` updates all windows immediately.
- `settleToIdle(after:)` schedules an idle transition after the delay.
- `pulse(_:duration:)` sets an activity, then returns to idle.
- `showHint(_:duration:)` displays a hint bubble temporarily.

### 8.3 Motion behavior

The buddy follows the mouse with spring-like smoothing:

- target position = mouse location offset by `(14, -13)`
- a short-distance spring model runs at 60 FPS
- very large jumps snap directly to the target

### 8.4 Visual semantics

The controller shows:

- an active halo while activity is not idle
- a hint card when `hintText` is set
- per-screen windows that ignore mouse input and join all spaces

Observed hint copy:

- “Drag anywhere on the screen to capture”
- “Reading current screen…”
- “Deleting selection…”
- “Rewriting selection in …”
- “Composing into …”
- “Couldn’t read current screen”
- “Couldn’t delete there”
- “Couldn’t compose there”

---

## 9. Settings

Implemented in `Sources/Lexi/Settings/SettingsWindowController.swift` and `Sources/Lexi/Settings/SettingsDesignSystem.swift`.

### 9.1 Window

- Title: **“Lexi Settings”**
- Size: `720 x 780`
- Style mask: titled, closable, miniaturizable, resizable

### 9.2 Sections

The settings view contains:

1. Header
2. Quick guide / shortcuts
3. Voice
4. Permissions
5. Advanced disclosure

### 9.3 Header

Observed copy:

- Wordmark
- **“Your reading companion.”**

Status pill states are driven by connection health and animation.

### 9.4 Shortcuts card

Observed rows:

- **“Explain what you’re reading”** — **“Hold the keys, highlight any text, release”**
- **“Precise Buddy”** — **“Hold, drag a region on screen, release to ask”**
- **“Quick Buddy”** — **“Hold, speak your question, release”**
- **“Nested look-up”** — **“Inside an answer, highlight a word and press →”**
- **“Dismiss”** — **“Close the panel or cancel anytime”**

Button:

- **“Try it now”**

### 9.5 Voice card

Contains:

- **“Voice questions”**
- a provider picker using `LexiVoiceProvider`
- **“Read answers aloud”**

Provider helper text varies by provider:

- Apple Speech path is on-device and requires Speech Recognition permission.
- AssemblyAI path uses the proxy.

### 9.6 Permissions card

Observed copy:

- **“Permissions”**
- **“Grant the system access Lexi needs to watch, capture, and speak on your Mac.”**

### 9.7 Advanced disclosure

Observed sections:

- Connection
- Status / health
- About this app

Observed controls:

- **“Use the built-in server”**
- **“Use the hosted server”**
- **“Save”**
- **“Copy details”**
- **“Check again”**

Observed status text includes:

- **“Checking…”**
- **“Connected”**
- **“Can’t reach Lexi”**

The code also explicitly offers the hosted server URL:

`https://lexi-production-9152.up.railway.app`

### 9.8 Settings design system

`SettingsDesignSystem` provides:

- `SettingsTheme.accent`
- spacing tokens: `section`, `card`, `row`, `tight`
- radius tokens: `card`, `chip`, `inner`
- reusable `SettingsCard`, `SettingsEyebrow`, `Keycap`, and shortcut row styling

---

## 10. Design system tokens

### 10.1 Core color and material system

Defined in `Sources/Lexi/DesignSystem/LexiTheme.swift`.

Observed tokens:

- `Color.lexiAccent`
- `Color.lexiAccentText`
- `Color.lexiAccentDeep`
- `Color.lexiPaper`
- `Color.lexiPaperElevated`
- `Color.lexiPaperSunken`
- `Color.lexiInk`
- `Color.lexiInkSecondary`
- `Color.lexiInkTertiary`
- `Color.lexiHairline`
- `Color.lexiAccentWash`

Material tokens:

- `LexiTheme.Material.panel = .ultraThinMaterial`
- `LexiTheme.Material.popover = .regularMaterial`
- `LexiTheme.Material.card = .thinMaterial`

### 10.2 Spacing

`LexiTheme.Spacing`:

- `xxs = 2`
- `xs = 4`
- `sm = 8`
- `md = 12`
- `lg = 16`
- `xl = 24`
- `xxl = 32`
- `xxxl = 48`

### 10.3 Radius

`LexiTheme.Radius`:

- `xs = 6`
- `sm = 10`
- `md = 14`
- `lg = 20`
- `xl = 28`
- `pill = 999`

### 10.4 Motion

`LexiTheme.Motion`:

- `spring = Animation.spring(response: 0.42, dampingFraction: 0.82)`
- `quick = Animation.easeOut(duration: 0.18)`
- `reveal = Animation.easeInOut(duration: 0.28)`

### 10.5 Typography

`Font.lexiDisplay`, `Font.lexiTitle`, `Font.lexiTitle2`, `Font.lexiHeadline`, `Font.lexiBody`, `Font.lexiCallout`, `Font.lexiSubheadline`, `Font.lexiCaption`, and `Font.lexiFootnote` define the app’s type scale.

### 10.6 Wordmark / brand mark

Defined in `Sources/Lexi/DesignSystem/LexiWordmark.swift`.

- `LexiWordmark` is the serif “Lexi” wordmark, optionally paired with `LexiBrandMark`.
- `LexiBrandMark` is a warm gradient badge.
- `LexiMonogram` is a flat glyph used for compact placements.
- Accessibility label: **“Lexi”**

The status item icon is generated by `LexiBrand.statusItemImage()`.

---

## 11. Edge-case matrix

| Edge case | Expected behavior | Exact copy / output |
|---|---|---|
| No highlighted text on Option+Space | Lexi can still interpret the spoken text or ask about the current screen. | Panel shows “Hold Option + Space while selecting a word or phrase, then release.” or composition/deletion hints depending on intent. |
| Accessibility permission missing | Selection capture fails; Lexi routes to the permission surface. | “Accessibility permission needed” in the panel; settings / permission UI requests re-checking. |
| Screen Recording permission missing | Buddy region capture cannot complete. | “Screen capture failed. Check Screen Recording permission.” |
| Microphone permission missing | Voice capture does not start. | “Microphone permission is required for push-to-talk Buddy Capture.” |
| Speech Recognition missing for Apple Speech | Apple Speech voice capture is blocked. | “Speech Recognition permission is required for Apple Speech. Switch to AssemblyAI after configuring the proxy, or enable Speech Recognition.” |
| Empty spoken question and no screenshot in Buddy quick capture | Capture is cancelled. | No request is sent; activity returns to idle. |
| Buddy overlay installed incorrectly / event tap fails | Lexi surfaces install failure. | It opens settings and shows a buddy permission-missing panel, or a Buddy error message. |
| Current-screen answer has neither screenshot nor text context | Lexi cannot ground the request. | “Couldn’t read current screen” |
| Delete intent but target is not writable | Lexi refuses the write-back. | “Click into a text field first” or “Select text to delete” |
| Compose intent but target is not writable | Lexi refuses the write-back. | “Click into a text field first” |
| Replace-selection write-back fails | Lexi does not silently stream a partial replacement. | “Couldn’t update that selection” |
| Insert write-back fails | Lexi reports failure. | “Couldn’t compose there” |
| Proxy is offline | Health check and request errors surface. | “Lexi proxy is offline” / “Couldn’t reach the assistant — try again.” |
| Proxy returns an assistant error | Lexi preserves the error code/message from proxy SSE. | Error panel shows the message from `ExplainClientError.proxyError(...)`. |
| TTS unavailable | Read-aloud fails silently except for logging. | Logged as “Lexi read-aloud failed: …” |
| Buddy callout absent | No overlay appears. | No `BuddyCalloutOverlayController.show(...)` call. |
| User presses Esc during Buddy capture | Capture cancels. | Overlay hides and activity returns idle. |
| Selected answer text not present when trying nested lookup | Right-arrow or release does not drill deeper. | The panel stays or falls back to latest child navigation. |

**⚠️ Notes for the designer**

- The error text for proxy failures is heterogeneous: some errors come from the app’s fallback strings, others from proxy-generated SSE errors. UI should be prepared for both concise and detailed messages.
- The current-screen capture path may use a focused-window screenshot or a cursor-screen screenshot; the fallback choice is internal and not surfaced in copy.

---

## 12. State persistence

### 12.1 UserDefaults keys

Observed persistent keys:

- `LexiHasCompletedFirstRun`
- `LexiProxyBaseURL`
- `LexiProxyToken`
- `LexiVoiceProvider`
- `LexiTTSReadAloudEnabled`
- `LexiVoiceAudioBufferSizeFrames`
- `LexiAssemblyAIFinalFallbackSeconds`
- `LexiVoiceTokenFetchTimeoutSeconds`
- diagnostics keys under `LexiDiagnostics...`

### 12.2 Proxy / configuration resolution

`AppConfiguration` resolves values in this order:

1. UserDefaults
2. Environment variables
3. Code default

Defaults include:

- proxy base URL: `http://127.0.0.1:8787`
- voice provider fallback: Apple Speech
- TTS read-aloud fallback: disabled unless explicitly enabled

### 12.3 Memory layers

- `ResearchSessionMemory` keeps the most recent 8 entries in process memory.
- `LexiInteractionEventStore` persists interaction events as JSONL in Application Support.
- `LexiContextSampler` persists sampled frontmost-app context events in Application Support.
- `LexiDiagnostics` persists the latest diagnostic snapshot fields in UserDefaults.

`LexiContextSampler` specifics:

- samples every 2.5 seconds
- records app name, bundle identifier, process identifier, and frontmost window title
- suppresses duplicate writes when the signature is unchanged

### 12.4 What resets

- `ResearchSessionMemory` is in-memory and resets when the app relaunches.
- `BuddyVoiceCapture` and `StreamingTextInserter` state is session-local and clears when a capture or insertion ends.
- `LexiHasCompletedFirstRun` remains until explicitly changed, so onboarding does not replay automatically after completion.
