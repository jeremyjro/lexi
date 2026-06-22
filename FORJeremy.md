# FOR Jeremy — Lexi Phase 1 Debrief

## 2026-06-20 — Menu-bar app + Accessibility onboarding

### Step 1 — The Approach: What Did We Do and Why?

We started with your new v1 spec, but the important discovery was that this was not a blank project. The T7 drive already had an older Lexi/CursorAssistant-style Swift project at `/Volumes/T7/Projects/Jeremy/Lexi`. That changed the job from “create a new app from scratch” to “reuse the existing app and steer it toward the cleaner v1 spec.”

The first phase of the spec is intentionally boring: menu-bar app, no Dock icon, and Accessibility permission onboarding. That boring foundation matters because everything else depends on it. If the app cannot live quietly in the menu bar and get permission to read selected text in other apps, the hotkey, capture, streaming, and floating explanation panel are all decorations on top of a broken base.

So we added three things: `NSApp.setActivationPolicy(.accessory)` to make the app behave like a background utility, an `NSStatusItem` so Lexi appears in the menu bar, and a dedicated onboarding window that tells you why Accessibility permission is needed and opens the right System Settings pane.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

The first possible path was to keep building in the fresh `/Volumes/T7/Projects/lexi` folder I initially started. That was rejected once you clarified that the older project was CursorAssistant and I found the real existing project under `/Volumes/T7/Projects/Jeremy/Lexi`. Continuing in the new folder would have split the work into two competing apps.

The second path was to immediately rewrite the old app into the full new v1 architecture. That would have been tempting, because the existing app already has AI calls, OCR, follow-ups, a bubble UI, and capture logic. But that would violate your own spec’s build sequence. The right move was to stop at Phase 1 so you can test the base behavior before we touch the hotkey and capture loop.

The third path was to delete the stale `.build` cache after Swift complained it still referenced the old `CursorAssistant` path. I did not do that because it means deleting a directory I didn’t create. Instead, I used a separate temporary build path. Same verification benefit, less risk.

### Step 3 — How the Parts Connect: The Architecture of the Work

Think of Lexi like a waiter in a restaurant. Phase 1 is not about cooking the meal yet; it is about making sure the waiter is standing in the room, wearing the uniform, and allowed to enter the kitchen. The menu-bar item is the waiter being present. The accessory activation policy is the waiter not interrupting the customer. Accessibility permission is the kitchen pass.

The new status menu gives you four basic controls: enable/disable, set hotkey placeholder, re-check Accessibility permission, and quit. The permission onboarding window is connected to both first launch and the menu’s re-check path. That means if permission is missing, Lexi can guide you immediately; if you need to debug it later, you can reopen the flow from the menu bar.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

We stayed with Swift, AppKit, and SwiftUI because the existing project already uses them and because they are the right tools for this app shape. `NSStatusItem` is the native AppKit API for menu-bar apps. `NSWindowController` is the native AppKit pattern for managing a standalone onboarding window. SwiftUI is useful for the onboarding content because it lets the layout be simple and readable.

For build verification, Swift Package Manager was the right tool because this project is a `Package.swift` project, not an Xcode project. The normal `.build` directory had stale paths from the old CursorAssistant name, so the cleanest verification was `swift build --build-path /tmp/lexi-swift-build`.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized preserving existing work and making a small, testable Phase 1 change. That means the old experimental Option+Command flow still exists in the app for now. It is not the final v1 design, but ripping it out during Phase 1 would make the change riskier and harder to test.

We also prioritized native app behavior over packaging polish. `NSApp.setActivationPolicy(.accessory)` makes the running app behave like a background utility. A fully polished distributed macOS app would also use bundle-level `LSUIElement`, signing, and an app bundle Info.plist. For this SwiftPM/local-build phase, runtime accessory activation is the practical step.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The main wrong turn was project location. I initially created a new scaffold under `/Volumes/T7/Projects/lexi` before you clarified that the older project was CursorAssistant. Once I found `/Volumes/T7/Projects/Jeremy/Lexi`, I stopped using the new scaffold and continued in the correct project.

The second bit of mess was the build cache. The project had likely been renamed or moved from `CursorAssistant` to `Lexi`, and Swift’s cached module data still remembered the old path. That produced scary-looking errors about `SwiftShims`, but the source code itself was not the issue. Building with a separate temporary build path proved the code compiles.

### Step 7 — Watch Out: Future Pitfalls

The existing app is ahead of the new spec in some ways and off-spec in others. It already contains OCR, follow-up prompts, tabbed explanations, and direct Anthropic API usage from `.env`. The new v1 spec explicitly says not to build OCR, follow-ups, saved state, or client-side API keys for the real app. Future work needs to prune or bypass those pieces instead of accidentally treating them as requirements.

Also watch out for macOS permissions. Accessibility permission is granted to a specific executable identity/path. If you run from different build paths, macOS may treat those as different apps. That can make permission testing feel inconsistent unless you pay attention to which built executable you launched.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner might think the main work is the AI explanation. A senior person sees that the real product risk is the system loop: permission, focus behavior, hotkey reliability, capture quality, panel positioning, streaming, and latency. The AI call is only one piece.

The other expert-level detail is not deleting caches casually. When a build cache is stale, deleting `.build` often works, but it is still a filesystem operation with side effects. Using a temporary build path is a cleaner diagnostic move because it separates “is the code broken?” from “is the cache dirty?”

### Step 9 — The Transfer: Lessons That Apply Everywhere

The transferable lesson is: when you inherit a half-built product, do not immediately add features. First, identify the real current state, compare it to the new spec, and make the smallest change that moves the foundation in the right direction.

This applies outside software too. If you take over a sales process, a hiring funnel, or a content engine, don’t start by adding fancy automation. First make sure the core loop is visible, testable, and under control. Then improve one phase at a time.

The single most important takeaway: Lexi’s success will come from a fast, reliable loop, not from having more features.

## 2026-06-20 — Phase 2: Hotkey + raw capture panel

### Step 1 — The Approach: What Did We Do and Why?

Phase 2’s job was to prove the front half of the loop: press a global hotkey, read the current selection, collect nearby context, and show the result in a floating panel. We deliberately did not call AI yet. That matters because if capture is unreliable, a beautiful model response later only hides the real problem.

We added a dedicated `HotkeyManager` for Option + Space, a fresh `SelectionCapture` path for Accessibility API reads, a `ClipboardFallback` for apps that do not expose selected text through Accessibility, and a `RawCapturePanelController` that shows exactly what Lexi captured. This makes Phase 2 a diagnostic tool: before asking Claude anything, you can see whether Lexi actually knows the term, passage, app, window, and source.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

The obvious shortcut was to reuse the existing CursorAssistant Option+Command flow. We rejected that because the new spec explicitly moved away from “hold keys while highlighting.” That gesture is harder to reason about and easy to trigger at the wrong moment. Select-then-press Option + Space is simpler and more reliable.

Another shortcut was to reuse the old `ContextInferenceService`. We rejected that for Phase 2 because it includes screenshots/OCR and AI-based inference, both of which are out of v1 scope. Reusing it would make the product seem more capable while making latency, privacy, and debugging worse.

### Step 3 — How the Parts Connect: The Architecture of the Work

The loop now works like a relay race. `HotkeyManager` hears Option + Space and hands the baton to `AppDelegate`. `AppDelegate` asks `SelectionCapture` for the current selection. `SelectionCapture` tries the clean Accessibility path first: selected text, full element value, selected range, surrounding passage, app name, window title, and selection bounds. If that fails, it hands the baton to `ClipboardFallback`, which briefly sends Command+C, reads the copied text, then restores your previous clipboard.

Finally, `RawCapturePanelController` displays the captured payload in a non-activating floating panel. The panel is not the final explanation UI yet. It is more like opening the hood of a car while the engine is running: you get to inspect whether fuel is reaching the engine before tuning performance.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

Carbon `RegisterEventHotKey` was used for the global hotkey because it is the classic macOS-level API for app-wide keyboard shortcuts. A global `NSEvent` monitor can work for some events, but it is not as clean for a true registered hotkey.

The Accessibility API was used because Lexi’s promise is system-wide reading, not browser-only reading. `kAXSelectedTextAttribute`, `kAXValueAttribute`, and `kAXSelectedTextRangeAttribute` are the core pieces: selected phrase, full text container, and where the selection sits inside it. The clipboard fallback exists because some apps do not expose rich Accessibility text.

SwiftUI was used inside the panel because the raw capture UI is mostly text layout. AppKit was used around it because native macOS window behavior — especially non-activating panels — is AppKit territory.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized observability over polish. The raw panel shows term, passage, app, window, and whether capture came from Accessibility or clipboard. That is not the final user experience, but it gives us the fastest way to debug real-world app behavior.

We also prioritized v1 scope discipline. The old repo still contains OCR, follow-ups, tabs, and direct AI calls. Phase 2 bypasses those instead of expanding them. The tradeoff is that some old code remains in the repo unused for now, but the active path is now much closer to the new build spec.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The main technical snag was Swift’s strict handling of CoreFoundation types like `AXValue`. Conditional casts such as `as? AXValue` produced compile errors because Swift knows the cast always succeeds for that bridged type. The fix was to guard that a value exists, then force-cast to `AXValue` before calling `AXValueGetValue`.

Another mess is that the repository still has legacy code paths. The old `handleModifierKeys` and AI-processing functions remain in the file but are no longer wired to the hotkey. That is acceptable for this phase, but it should be cleaned up once Phase 3/4 establishes the new proxy-based path.

### Step 7 — Watch Out: Future Pitfalls

The hardest bugs will not come from Swift syntax. They will come from app-by-app differences in Accessibility behavior. Safari, Preview, Notes, Slack, and Electron apps may each expose selection and context differently. That is why the Phase 2 test needs to happen across several apps before AI is added.

Clipboard fallback is powerful but delicate. The important thing is restoring the user’s clipboard after the synthetic copy. If that ever fails, Lexi becomes annoying fast because it silently destroys something the user copied earlier.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner might celebrate as soon as the hotkey shows a panel. A senior person asks, “Where did the text come from, how much context did we get, did the panel steal focus, and did the clipboard survive?” Those details are the difference between a demo and a tool you can use every day.

The non-obvious product insight is that raw capture is itself a feature during development. It gives you a truth window. Without it, every bad AI answer would be ambiguous: was the model wrong, was the prompt wrong, or did capture send garbage?

### Step 9 — The Transfer: Lessons That Apply Everywhere

When building a loop, isolate each handoff before optimizing the whole thing. In Lexi, the handoffs are hotkey → capture → panel → proxy → model → streamed UI. In any business process, the same rule applies: do not optimize the sales pitch before confirming leads are qualified; do not automate follow-up before confirming the form data is clean.

The transferable lesson is to build temporary diagnostic surfaces early. They may not survive into the polished product, but they help you see the system clearly while it is still forming.

## 2026-06-20 — Phase 3: Backend proxy + full answer

### Step 1 — The Approach: What Did We Do and Why?

Phase 3 connected the proven capture loop to a real explanation. We added a small local Node proxy, then taught the Mac app to send the captured term, passage, app name, and window title to that proxy. The proxy calls Anthropic and returns a complete answer as JSON.

The reason for the proxy is simple: your API key should not live in the app. The Mac app now only knows `http://127.0.0.1:8787/explain`; the proxy is the part that knows Anthropic.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not call Anthropic directly from Swift, even though the old repo had direct API code. That path is simpler for a personal prototype but weaker as a product foundation. We also did not stream yet. Streaming is the next phase; for this phase, proving one clean round trip was the goal.

### Step 3 — How the Parts Connect: The Architecture of the Work

The loop is now hotkey → capture → panel loading state → local proxy → Anthropic → full answer → panel answer state. This is the first end-to-end product loop, even though it is not yet optimized for latency.

The proxy owns the prompt and model choice. The app owns native capture and display. That split keeps secrets and model behavior server-side while keeping the user experience native.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

The proxy uses Node, Express, TypeScript, dotenv, and Anthropic’s official SDK. That gives us a tiny server with type checking and minimal ceremony. The Swift app uses `URLSession` with a small `ExplainClient`, which is the native macOS networking tool.

We confirmed the current Haiku model string as `claude-haiku-4-5-20251001`, matching your spec and Anthropic docs/search results.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized correctness and clean architecture over speed. The answer currently appears only after the full response returns. That is less magical than streaming, but easier to debug. Once this works, Phase 4 can stream deltas without changing the basic shape.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The main practical issue was environment loading. Your key already lives in the repo root `.env`, while the proxy runs from `proxy/`. The fix was to let the proxy load both `proxy/.env` and `../.env`, without printing the key.

### Step 7 — Watch Out: Future Pitfalls

Do not ship the local proxy as-is to other users. For personal testing it is fine. For real use, this proxy should be hosted somewhere warm and close to you to avoid latency. Also, Phase 4 needs streaming; otherwise Lexi will feel slower than the spec demands.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner might think “the AI works” is the finish line. A senior person sees that the important milestone is the boundary: the app does capture/display, the proxy does model/API/prompt. Good boundaries make later changes cheaper.

### Step 9 — The Transfer: Lessons That Apply Everywhere

When a system needs a secret, put the secret behind a boundary. Whether it is an API key, payment credential, or private dataset, the client should ask for the result, not hold the sensitive raw power itself.

## 2026-06-20 — Phase 6: Polish and edge-case hardening

### Step 1 — The Approach: What Did We Do and Why?

Phase 6 was not about adding a new capability. It was about making the working loop less brittle. The app already captured text, called the proxy, and streamed an answer. The polish pass focused on the small things that make a utility feel dependable: dismiss behavior, panel placement, labels that do not expose internal phase names, and accessibility-respectful loading.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

The tempting path was a large cleanup of every old CursorAssistant code path. I avoided turning this into a broad refactor because the core loop is now working and broad deletion can introduce unrelated breakage. Instead, the active path was polished first. The old code should still be removed, but as a separate refactor with its own build/test pass.

### Step 3 — How the Parts Connect: The Architecture of the Work

The most important polish change is dismissal cancellation. Before this, clicking away or pressing Escape hid the panel, but the in-flight stream could continue invisibly. Now the panel controller exposes an `onDismiss` hook, and `AppDelegate` uses that hook to cancel the current explain task. That keeps the UI state and network state aligned.

Panel positioning was also improved. Instead of blindly trying below then flipping only when it runs out of room, the panel now considers available space above and below the selection, clamps to the visible screen, and nudges away from the selected text if clamping would cause overlap.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

This stayed in AppKit + SwiftUI because the boundary is natural: AppKit owns window behavior and SwiftUI owns panel content. The `@Environment(\.accessibilityReduceMotion)` value lets the panel avoid animated loading UI when the user has Reduce Motion enabled.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized stabilizing the current user-facing path over fully deleting legacy internals. That leaves some old code in the repo, but it keeps this phase focused on what the user can feel immediately. The right next cleanup is to remove unused old AI/bubble/tab code in a dedicated pass.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The dead legacy method body was harder to remove with exact edit matching than expected because the file has older comments/log text and hidden exact-string differences. Rather than risk a broad rewrite of `AppDelegate`, the safer move was to leave the deep deletion for a refactor and continue with the visible polish changes that compiled cleanly.

### Step 7 — Watch Out: Future Pitfalls

The biggest remaining pitfall is stale legacy code. It is not hurting the current loop, but it makes the app harder to understand. The more phases Lexi gets, the more expensive that old code becomes. Remove it soon while the active architecture is still fresh.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner often thinks polish means visual styling. In a system utility, polish is mostly state correctness: hidden panel means canceled request, click-away means dismiss, Escape behaves predictably, and the app does not steal focus. Those details are what make the tool feel native.

### Step 9 — The Transfer: Lessons That Apply Everywhere

Once a loop works, the next layer of quality is aligning visible state with hidden state. If the UI says something is gone, the underlying work should usually stop too. That principle applies to software, operations, sales workflows, and any system where background work can drift away from what the user thinks is happening.

## 2026-06-20 — Phase 7: AppDelegate cleanup and architecture simplification

### Step 1 — The Approach: What Did We Do and Why?

Phase 7 cleaned the app entrypoint. Before this pass, `AppDelegate` still contained the old CursorAssistant-style direct AI, OCR, bubble, tab, retry, and follow-up flow. The working Lexi path did not need any of it. The goal was to make the file say what the product now does: menu bar, permission check, hotkey, capture, proxy streaming, panel.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not delete the old service/view files yet. Instead, we removed their wiring from `AppDelegate`. That is a safer step because it cleans the active architecture while preserving old files for reference until a later dead-file deletion pass.

### Step 3 — How the Parts Connect: The Architecture of the Work

The active delegate now has one clear loop: `HotkeyManager` triggers `handleLookupHotkey`, `SelectionCapture` returns a `CapturedSelection`, `ExplainClient` streams SSE deltas from the proxy, and `RawCapturePanelController` renders those deltas. The old direct Anthropic client no longer sits in the app entrypoint.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

This was mostly Swift code removal and verification. The important method was dependency tracing: grep for old properties/methods, remove the entrypoint wiring, then build. The proxy still owns API-key/model logic; the app only owns native macOS behavior.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized clarity over total repository deletion. There are still old files in `Services`, `Views`, and `Models`, but they are no longer orchestrated by `AppDelegate`. That means the app’s main loop is now easier to understand, while the final dead-code deletion can happen separately.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The old delegate had grown organically. It mixed permission setup, old OCR, direct AI calls, bubble rendering, retry handling, nested tabs, and the new Lexi streaming flow in one file. The cleanup worked because we rewrote the file around the actual current architecture instead of trying to surgically patch every stale branch.

### Step 7 — Watch Out: Future Pitfalls

The next cleanup should remove or isolate unused old files. If they stay forever, future work may accidentally revive the wrong path. A good next pass is to grep for unreferenced old types and delete them only after a clean build proves they are not needed.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner often judges progress by adding code. A senior engineer knows that deleting the wrong architecture is progress too. Once the working loop exists, old unused paths become risk: they confuse future debugging and make the app look more complicated than it is.

### Step 9 — The Transfer: Lessons That Apply Everywhere

Simplification is a product feature. When a system’s entrypoint is clean, every future change is cheaper because you can see where behavior begins and ends. This applies to codebases, teams, sales funnels, and operating rhythms: fewer active paths means fewer hidden failure modes.

## 2026-06-20 — Phase 8: Package polish and safe legacy exclusion

### Step 1 — The Approach: What Did We Do and Why?

Phase 8 made the package match the product. After Phase 7, the app entrypoint no longer used the old CursorAssistant services, views, models, configuration, or examples. But SwiftPM was still compiling those files because the target path included all Swift files under `Sources/Lexi`. This phase excluded the old prototype files from the active build without deleting them.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

The aggressive path was deleting the old files. That would be clean, but file deletion is irreversible enough that it should be explicitly approved. The safer Phase 8 move was to use SwiftPM `exclude` entries. That gives us the build benefit and architectural clarity while preserving the old files for review.

### Step 3 — How the Parts Connect: The Architecture of the Work

The active SwiftPM target now compiles only the current Lexi path: `AppDelegate`, `LexiApp`, Capture, Hotkey, Network, Panel, and permission onboarding. Old folders like `Services`, `Models`, `Configuration`, and `Examples` are excluded from the target, along with old bubble/cursor follower views.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

Swift Package Manager supports target-level excludes. That is the right tool here because we are changing what belongs to the app build, not changing runtime behavior. We also fixed a small Swift warning by changing an unmutated hotkey variable from `var` to `let`.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized safe cleanup over physical deletion. The repository still contains the old files, but the running app no longer compiles them. The final deletion pass can happen once you explicitly approve removing them.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The messy part is inherited structure. The repo had both the new Lexi flow and older experimental systems living together. Phase 8 did not pretend those files were gone; it made the build honest by saying which ones are no longer part of the product.

### Step 7 — Watch Out: Future Pitfalls

If a future developer sees the old excluded files, they might think they are still product code. The next step should either delete them with approval or move them into a clearly labeled archive outside the active source tree.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner might think unused files are harmless if they are not referenced. In SwiftPM, files under the target path compile unless excluded. That means dead code can still cause build failures, warnings, compile time, and confusion. Excluding it is a real cleanup step.

### Step 9 — The Transfer: Lessons That Apply Everywhere

A system should make the active path obvious. If obsolete pieces are still visible, label or exclude them so people do not route work through the wrong machinery. In code and companies, clarity beats archaeology.

## 2026-06-20 — Phase 10: Physical legacy deletion

### Step 1 — The Approach: What Did We Do and Why?

Phase 10 removed the old prototype code from the repository instead of merely excluding it from the build. Phase 8 made the active app ignore the old folders. Phase 10 made the source tree match that reality.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not delete anything outside the exact legacy list from Phase 8. The `Utilities` folder, active Capture/Hotkey/Network/Panel files, permission onboarding, proxy, and app entrypoint were left alone. The deletion was intentionally narrow.

### Step 3 — How the Parts Connect: The Architecture of the Work

The remaining Swift app source now points clearly at the current Lexi architecture: app delegate, app entrypoint, capture, hotkey, proxy client, panel, and permission onboarding. Because the old folders are gone, `Package.swift` no longer needs exclusion rules.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

`git rm` was used rather than a blind filesystem delete because this is a tracked repository. That records the deletion cleanly in version control and makes review straightforward.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized repository clarity over preserving old experiments in place. The old code remains recoverable through git history, but it no longer distracts from the product code in the current tree.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The only practical issue was shell-session saturation during build/restart commands. After clearing old sessions, the Swift build and proxy type-check both passed cleanly.

### Step 7 — Watch Out: Future Pitfalls

If a feature from the old prototype is needed later, recover it intentionally from git history rather than reintroducing the whole old architecture. Cherry-pick ideas, not systems.

### Step 8 — The Expert Eye: What a Beginner Would Miss

Deleting code is safe when the dependency path is understood and the build proves the deletion. It is unsafe when done as cleanup theater. The key difference is verification.

### Step 9 — The Transfer: Lessons That Apply Everywhere

Once a new operating model works, remove the old operating model. Keeping two systems around feels safe, but it usually creates confusion and hidden maintenance cost.

## 2026-06-20 — Phase 11: Local macOS app bundle packaging

### Step 1 — The Approach: What Did We Do and Why?

Phase 11 turned the SwiftPM executable into a local `.app` bundle. Before this, Lexi was mostly launched with `swift run`, which is fine for development but not how a Mac utility should normally be opened. The packaging script now builds Lexi and assembles `dist/Lexi.app`.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not jump straight to signing, notarization, installer creation, or App Store-style distribution. Those steps matter later, but the first packaging milestone is simply a valid local app bundle with the executable and `Info.plist` in the right places.

### Step 3 — How the Parts Connect: The Architecture of the Work

The script builds the SwiftPM release executable, creates the macOS bundle structure, copies the executable into `Contents/MacOS/Lexi`, and writes `Contents/Info.plist`. The plist includes `LSUIElement` so Lexi remains a menu-bar utility instead of becoming a Dock-first app.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

A shell script is the right tool for this phase because the project is still a SwiftPM app, not an Xcode archive workflow. `plutil` validates the generated plist. The app bundle follows the standard macOS layout: `.app/Contents/MacOS`, `.app/Contents/Resources`, and `.app/Contents/Info.plist`.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized repeatable local packaging over distribution polish. The app is not signed or notarized yet. It is good enough for local testing as a real `.app`, but not yet ready for frictionless installation on other Macs.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

After launching the packaged app, an older debug Lexi process was still running. That could cause duplicate hotkey behavior, so it was stopped. This is a useful reminder that packaging tests should check process state, not just whether `open` returns successfully.

### Step 7 — Watch Out: Future Pitfalls

The packaged app may appear as a new app identity for Accessibility permission because macOS permissions are tied to the executable/bundle identity and path. If capture fails in the packaged app, re-enable Accessibility permission for the packaged Lexi app.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A `.app` is not just a renamed executable. It needs the expected bundle layout and metadata. The `Info.plist` is part of runtime behavior: `LSUIElement` affects Dock/menu-bar behavior, and bundle IDs affect permissions and future signing.

### Step 9 — The Transfer: Lessons That Apply Everywhere

Packaging is where a working prototype starts becoming an artifact. A product is not only what runs on your machine; it is also the repeatable process that creates the thing users can launch.

## 2026-06-20 — Phase 12: Proxy configuration and status UX

### Step 1 — The Approach: What Did We Do and Why?

Phase 12 made the app more resilient around the backend boundary. Until now, Lexi assumed the proxy lived at `http://127.0.0.1:8787`. That still remains the default, but the app can now resolve a custom proxy URL and expose proxy status from the menu bar.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not build a full settings window yet. A settings UI is useful later, but the lightweight step was a central configuration object plus a status menu item. That gives us better behavior without adding another window/screen.

### Step 3 — How the Parts Connect: The Architecture of the Work

`AppConfiguration` owns proxy URL resolution. `ExplainClient` uses that base URL for both `/explain` and `/health`. `AppDelegate` adds a `Check Proxy Status` menu item that calls `ExplainClient.health()` and shows the model/URL or a clear offline error.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

`UserDefaults` and environment variables are simple enough for this phase. The app checks `LexiProxyBaseURL` first, then `LEXI_PROXY_BASE_URL`, then falls back to localhost. That gives local flexibility without committing a hardcoded production URL.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized debuggability over a polished settings UI. You can now tell whether the proxy is online from the menu bar, but editing the proxy URL is still a developer-style configuration path.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The recurring mess is shell-session saturation in this environment during build/restart cycles. The product change itself was straightforward: centralize URL resolution, add health check, improve connection error messaging.

### Step 7 — Watch Out: Future Pitfalls

A hosted proxy will need auth and abuse protection. Configuring a URL is only the first half. The moment the proxy is public, it must identify legitimate clients and protect the Anthropic key.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner might treat “backend URL” as a constant. A product engineer treats it as an environment boundary. Local, staging, and production should be swappable without rewriting the app.

### Step 9 — The Transfer: Lessons That Apply Everywhere

Every useful system has boundaries. Make those boundaries observable. If one side is down, the user should know which side failed and what to do next.

## 2026-06-20 — Phase 13: Railway hosted-backend readiness

### Step 1 — The Approach: What Did We Do and Why?

Phase 13 prepared the proxy for Railway hosting. The local proxy already worked, but hosted deployment has different requirements: compile TypeScript to JavaScript, bind to the platform host/port, provide health checks, and avoid exposing the Anthropic key to the Mac app.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not complete the live Railway deploy because the Railway CLI is not authenticated on this machine. That is the right stopping point: deployment requires account access. Instead, the repo is now ready to deploy once `railway login` and `railway link` are complete.

### Step 3 — How the Parts Connect: The Architecture of the Work

The proxy now builds to `proxy/dist` and starts with `node dist/server.js`. `railway.json` tells Railway how to build and start the service. The server binds to `0.0.0.0` when Railway environment variables are present, while preserving `127.0.0.1` local behavior.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

Railway uses project configuration plus environment variables. The proxy now supports `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, `PORT`, `HOST`, and optional `LEXI_PROXY_TOKEN`. A helper script verifies Railway auth/link state before deploying.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized safe hosted readiness over forcing a deploy. The proxy is ready, but it is not yet public because Railway authentication is missing. That avoids accidental deployment into the wrong account/project.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The Railway CLI was installed but returned `Unauthorized. Please login with railway login`. That is not a code problem; it is an account/auth step. The helper script now detects that condition cleanly.

### Step 7 — Watch Out: Future Pitfalls

If the Railway proxy is public, set `LEXI_PROXY_TOKEN` and configure the Mac app with the same token via `LexiProxyToken` or `LEXI_PROXY_TOKEN`. A public unauthenticated proxy with an Anthropic key behind it can be abused.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A hosted backend is not just “run the same server elsewhere.” It needs startup commands, build output, health checks, host binding, environment variables, and auth boundaries. Those details are the difference between a local service and a deployable service.

### Step 9 — The Transfer: Lessons That Apply Everywhere

Moving from local to hosted means converting assumptions into configuration. Local paths, local ports, and local secrets must become explicit platform settings.

## 2026-06-21 — Phase 14: Settings and install polish

### Step 1 — The Approach: What Did We Do and Why?

Phase 14 moved Lexi away from hidden Terminal-only configuration. The app now has a real Settings window from the menu bar where the proxy URL and proxy token can be managed, the backend can be checked, and the URL can be reset to Railway or local defaults.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not build a full preference system, Keychain token storage, or Launch at Login yet. Those are still useful, but the immediate friction was that the working cloud configuration lived in `defaults write` commands instead of the product UI.

### Step 3 — How the Parts Connect: The Architecture of the Work

`SettingsWindowController` hosts a SwiftUI `SettingsView`. It writes to the same UserDefaults keys Lexi already uses: `LexiProxyBaseURL` and `LexiProxyToken`. `AppDelegate` now creates fresh `ExplainClient` instances when checking status or running a lookup, so saved settings can take effect without relying on an old cached client.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

SwiftUI was used for the settings form because it is compact and already available in the app. The existing AppKit menu-bar architecture remains in place. The install script uses the existing packaging script, then copies the signed bundle into `/Applications` with `ditto`.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized operational usability over deeper security polish. The token is still stored in UserDefaults rather than Keychain. That is acceptable for this personal-use phase, but not for broad distribution.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The main friction was the development shell environment repeatedly saturating with old sessions. The app-side implementation itself stayed straightforward once the settings boundary was clear.

### Step 7 — Watch Out: Future Pitfalls

Once Lexi is installed into `/Applications`, Accessibility permissions should be granted to that stable app path. Rebuilding and launching from `dist/` can still create permission confusion if both copies exist.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A setting is not just a text field. It is a contract between UI, runtime configuration, saved defaults, and diagnostics. The important part is that the Settings window uses the same keys as the runtime app, so it changes the real behavior.

### Step 9 — The Transfer: Lessons That Apply Everywhere

When a prototype starts working, the next bottleneck is usually not capability; it is operability. Make the working path visible, editable, and recoverable from inside the product.

## 2026-06-21 — Phase 15: Reliability and error handling

### Step 1 — The Approach: What Did We Do and Why?

Phase 15 made Lexi failures more diagnosable. Instead of every assistant failure collapsing into “couldn’t reach the assistant,” the proxy now classifies common Anthropic and auth failures, and the Mac client maps those codes into clearer user-facing messages.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not add a full observability stack, persistent error reporting, or user-facing debug console. Those can come later. The immediate need was better categorization at the proxy/client boundary.

### Step 3 — How the Parts Connect: The Architecture of the Work

The Railway proxy now sends structured errors like `assistant_auth_failed`, `assistant_model_unavailable`, `assistant_rate_limited`, and `unauthorized`. `ExplainClient` decodes both JSON HTTP errors and SSE `error` events with optional codes, then maps them to specific messages in the panel.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

The system already uses HTTP JSON for pre-stream failures and SSE for streaming failures, so Phase 15 extended those existing protocols rather than adding a new diagnostics channel.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized actionable messages over perfect detail. The app still avoids exposing raw provider errors or secrets, but it gives enough direction to know whether to check Railway variables, proxy token settings, model availability, or rate limits.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The main historical mess was that many different problems looked the same: missing Anthropic key, wrong model, bad token, unavailable proxy, and Accessibility issues. Phase 15 reduces that ambiguity without overbuilding.

### Step 7 — Watch Out: Future Pitfalls

If the proxy adds more providers or models, keep error codes stable. The app should depend on semantic codes, not raw provider message strings.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A good error message is part of the product architecture. The moment Lexi became cloud-backed, failures could happen in more places, so the boundary needed structured language.

### Step 9 — The Transfer: Lessons That Apply Everywhere

As systems become distributed, reliability starts with naming failure modes. If you cannot name where something broke, every problem feels like the whole system failed.

## 2026-06-21 — Phase 16: UX polish

### Step 1 — The Approach: What Did We Do and Why?

Phase 16 made the core popup feel more like a deliberate product surface instead of a raw debug panel. The floating panel now has clearer status treatment, a larger reading area, better footer hints, and a more polished visual hierarchy.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not add in-panel interactive buttons yet because the panel is intentionally non-activating and click/dismiss behavior needs care. Instead, copying was added through the menu bar as `Copy Last Answer`, which fits the current app architecture.

### Step 3 — How the Parts Connect: The Architecture of the Work

`RawCapturePanelController` still owns the floating panel, but `RawCapturePanelView` now has a top status bar, state-specific status labels, color accents, and clearer footer copy. `AppDelegate` stores the last successful answer and exposes a menu item to copy it.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

SwiftUI remains the right tool for panel presentation because the layout changes are declarative and compact. AppKit remains responsible for menu bar lifecycle, global hotkey behavior, and pasteboard integration.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized low-risk polish over deep interaction. The panel still avoids complex clickable controls. That preserves the current dismissal model while improving readability and everyday utility.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The install script surfaced a LaunchServices `-600` open failure after copying the app. The copy and signature were fine, so the installer now tolerates open failures rather than treating a post-install launch hiccup as an install failure.

### Step 7 — Watch Out: Future Pitfalls

If clickable panel controls are added later, revisit `NSPanel` activation behavior and the global mouse dismissal monitor. Otherwise clicks intended for controls may dismiss the panel first.

### Step 8 — The Expert Eye: What a Beginner Would Miss

UX polish is not only colors and spacing. It is also about preserving the interaction contract: fast popup, readable answer, obvious state, easy dismissal, no accidental focus stealing.

### Step 9 — The Transfer: Lessons That Apply Everywhere

Once something works, reduce the cognitive load around using it. The best product improvements often make the user think less, not do more.

## 2026-06-22 — Phase 17: Distribution identity

### Step 1 — The Approach: What Did We Do and Why?

Phase 17 gave Lexi the basics of a real distributable Mac app identity. The app now has centralized version metadata, a bundled icon, Info.plist identity fields, optional Developer ID signing support, and a release ZIP builder.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not perform real Apple Developer ID signing or notarization because that requires Jeremy's Apple developer certificate and notary credentials. Instead, the scripts now support those paths when the credentials are available, while preserving local ad-hoc signing for development.

### Step 3 — How the Parts Connect: The Architecture of the Work

`VERSION` is now the source of the marketing version. `scripts/package_app.sh` reads that file, computes a build number from Git history by default, copies `assets/Lexi.icns` into the app bundle, writes icon/category/version keys into Info.plist, and signs with either ad-hoc or a provided `SIGN_IDENTITY`. `scripts/build_release.sh` packages the app and creates a ZIP in `releases/`.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

Mac apps need identity at the bundle level: Info.plist metadata, icon resources, version/build numbers, and code signing. `iconutil` creates the `.icns` from the generated iconset, `codesign` verifies the bundle, and `ditto` creates a standard distributable ZIP.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized a repeatable distribution pipeline over App Store-level polish. The icon is generated and good enough for identity, but it is not yet a professionally designed brand asset. Notarization is supported but not executed.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The key product distinction is that local installation and public distribution are not the same thing. Phase 17 made that boundary explicit: ad-hoc signing is fine for Jeremy's Mac, while Developer ID signing and notarization are needed for smooth sharing.

### Step 7 — Watch Out: Future Pitfalls

If `SIGN_IDENTITY` is set for notarization, it must be a valid `Developer ID Application` certificate. Notarization also requires `APPLE_ID`, `APPLE_TEAM_ID`, and an app-specific `APPLE_APP_PASSWORD` or equivalent notarytool credentials.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A Mac app's perceived legitimacy comes from boring metadata: stable bundle ID, icon, version, category, signature, and notarized archive. Without those, even a working app feels like a script.

### Step 9 — The Transfer: Lessons That Apply Everywhere

Distribution is an engineering feature. If the build, identity, signing, and archive steps are not reproducible, every release becomes a manual ritual.

## 2026-06-22 — Nested lookups Phase 1: Selectable answers and navigation stack

### Step 1 — The Approach: What Did We Do and Why?

This pivot starts Lexi V2's nested lookup system. The first implementation phase intentionally does not call the model for child explanations yet. It proves the hard local product mechanics first: representing answers as a navigation stack, rendering breadcrumbs, selecting text inside Lexi's own answer panel, pushing a child layer, popping back, and jumping to root instantly.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not wire real lineage-aware generation yet because the spec explicitly recommends stopping after stack mechanics are testable. We also did not persist lookup trees between root lookups; a new root lookup should still discard the old stack.

### Step 3 — How the Parts Connect: The Architecture of the Work

`LookupNavigationStack` owns the active path of `LookupNode`s. Root answers are now converted into a stack after the first model response completes. `RawCapturePanelViewModel` mutates that stack for dummy drill-down, Esc pop, Command-Up root jump, and breadcrumb jumps. The panel owns selectable answer text through an AppKit `NSTextView` wrapper, avoiding Accessibility capture for nested selections.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

Nested capture is inside Lexi, so AppKit text selection is the right primitive. The main app still uses Accessibility for external app capture, but nested lookup selection uses Lexi-owned UI state. This separation keeps the original capture path untouched.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized navigational correctness over answer quality. Child nodes use placeholder text for now. That lets us test infinite-ish depth, breadcrumbs, back, root jump, and cached parent restoration before adding network complexity.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The panel had to become key-capable enough for owned text selection and local key handling. This is subtle because Lexi's panel is intentionally non-activating and should not feel like a normal document window.

### Step 7 — Watch Out: Future Pitfalls

When real nested generation lands, preserve the invariant that only push generates. Pop, root jump, and breadcrumb jump must only read cached node answers. If those paths make network calls, the feature loses its main product value.

### Step 8 — The Expert Eye: What a Beginner Would Miss

Nested lookup is not just “call explain again.” It is a navigation model. Without a stack and cache, the reader cannot safely drill down because they lose their place.

### Step 9 — The Transfer: Lessons That Apply Everywhere

For exploration UIs, orientation matters as much as generation. Users will only go deeper if getting back feels instant and guaranteed.

## 2026-06-22 — Nested lookups Phase 2: Real lineage-aware child generation

### Step 1 — The Approach: What Did We Do and Why?

Phase 2 replaced dummy nested lookup children with real streamed explanations. When the reader selects or double-clicks a term inside a Lexi answer, Lexi now pushes a pending child node, streams a real explanation into that node, and keeps the parent/root answers cached for instant navigation.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not add the learning-loop event store yet, and we did not force a separate nested Haiku model in production because the currently working Railway model configuration should remain stable. The proxy now supports `ANTHROPIC_NESTED_MODEL`, but defaults nested calls to the existing model until that env var is deliberately set.

### Step 3 — How the Parts Connect: The Architecture of the Work

`ExplainClient.explainNested` builds a lineage payload from the current `LookupNavigationStack`. The proxy accepts optional `lineage`, builds a nested prompt from root source, parent answer, highlighted term, and depth, then streams the result back through the same SSE path. The panel updates the child node's cached answer as tokens arrive.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

We reused the existing `/explain` route and SSE parser instead of adding another endpoint. The request shape is backward compatible: root lookups send the old fields, nested lookups add optional lineage.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized preserving root lookup behavior and instant cached navigation. Nested generation is real now, but analytics and formal tests are still deferred to later phases.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The key refactor was moving nested lookup initiation out of the SwiftUI view and back into `AppDelegate`, where network tasks already live. That keeps UI state and async generation coordinated without making the view own backend concerns.

### Step 7 — Watch Out: Future Pitfalls

If a user pops away while a nested answer is still streaming, the child node can continue updating in cache. That is acceptable for now, but future UI may want explicit cancellation or a visible background-generation state.

### Step 8 — The Expert Eye: What a Beginner Would Miss

The important part is not simply that a second explanation can be requested. The important part is that the second explanation is aware of the parent answer and that returning to the parent requires no regeneration.

### Step 9 — The Transfer: Lessons That Apply Everywhere

When adding depth to a product, make deeper work contextual and make returning cheap. That combination is what turns exploration from a tangent into a loop.
