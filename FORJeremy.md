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

## 2026-06-24 — Lexi v0.3.0: Clicky-informed Buddy, voice, OCR, memory, and proxy upgrades

### Step 1 — The Approach: What Did We Do and Why?

We started with a comparison between Lexi and Clicky. The important conclusion was not “copy Clicky.” Clicky is strongest as a voice-first screen companion. Lexi is strongest as a research comprehension tool. So the right move was to borrow Clicky’s infrastructure where it helps the research loop, while protecting Lexi’s core shape: highlight-first, text-first, concise, contextual explanations.

That is why we first wrote a versioned technical spec in `LEXI_TECHNICAL_PRODUCT_SPEC_v0.3.0.md`. The spec acts like a blueprint taped to the wall before construction starts. Without it, this work could easily sprawl into “make a Clicky clone.” With it, every implementation decision had to answer the question: does this make Lexi faster and smarter for understanding research material?

Then we implemented the phases in layers: network hardening, image quality, quick push-to-talk, transcription providers, OCR, session memory, optional TTS, and visual callouts. The order matters because each layer feeds the next one. Better network handling makes image requests safer. Better images and OCR make Buddy answers smarter. Better voice transcription makes quick Buddy usable. Session memory ties the loops together.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

The biggest rejected road was turning Lexi into a full always-on cursor companion. That would be flashy, but it would blur the product. Lexi’s job is not to be a little character that lives on screen all day. Lexi’s job is to compress the time between confusion and understanding.

We also rejected sending huge screenshots just because the proxy now accepts up to 25 MB. A bigger pipe does not mean you should flood it. The better choice is adaptive compression: enough image quality for the model to read and reason, but not so much that every question becomes slow, expensive, and privacy-heavy.

Another rejected shortcut was putting AssemblyAI or ElevenLabs keys directly in the app. That would be convenient locally but wrong for a real product. The app now supports those providers through proxy placeholders, so secrets stay server-side and can be added later by configuration.

### Step 3 — How the Parts Connect: The Architecture of the Work

Think of this version like upgrading a research assistant from a notepad into a field kit. The notepad still matters: highlight text, get the answer, drill down. But now the kit also has a microphone, camera, OCR scanner, memory card, and optional speaker.

`ExplainClient` is the network pipe. It now uses a shared configured session and records diagnostics. `RegionScreenshotCapture` is the camera. It captures regions, focused windows, or cursor screens and compresses adaptively. `BuddyTextRecognizer` is the OCR scanner, pulling text out of screenshots before the model sees them. `BuddyVoiceCapture` plus the new transcription provider layer is the microphone, with Apple Speech as local fallback and AssemblyAI as the stronger streaming option. `ResearchSessionMemory` is the memory card, keeping recent context in RAM so follow-ups and Buddy questions can stay connected. `ElevenLabsTTSClient` is the optional speaker. `BuddyCalloutOverlayController` is the pointer, showing where the model says something relevant is on screen.

The proxy sits behind all of this as the external API gateway. It now has `/transcribe-token` for AssemblyAI, `/tts` for ElevenLabs, richer `/health`, and prompt support for OCR/session context/callout tags.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

We used ScreenCaptureKit because it is the right macOS framework for screen and window capture. We used Vision OCR because it is local, already available on macOS, and avoids adding another cloud OCR dependency. We used AVFoundation because microphone capture and audio playback are native macOS jobs. We used Speech as the local fallback because Apple Speech is already integrated with macOS permissions.

The transcription provider protocol is the important design move. Without that abstraction, AssemblyAI would get tangled directly into `BuddyVoiceCapture`. With the abstraction, Lexi can choose Apple Speech or AssemblyAI from Settings, and future providers can be added without rewriting the Buddy flow.

For the proxy, Express stayed in place because Lexi already has a working Railway proxy with SSE streaming, auth, health checks, and model routing. Replacing it with Clicky’s thinner Worker design would have thrown away useful product-specific infrastructure.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized completeness and integration over perfect polish. The main flows are implemented and compile: quick Buddy, provider selection, OCR, memory, TTS, callouts, adaptive images, and proxy placeholders. But manual end-to-end testing still needs real AssemblyAI and ElevenLabs secrets, and packaging/deploying should only happen once you confirm the side effects.

We prioritized privacy by default. Lexi still does not capture all screens by default. Quick Buddy captures the focused window or cursor screen, and precise Buddy captures only the dragged region. That sacrifices some “the AI sees everything” convenience, but it better matches Lexi’s research-assistant identity.

We prioritized text-first UX. Read-aloud exists, but it is off by default. That means Lexi does not become noisy or voice-dependent. The tradeoff is that the app will feel less like Clicky out of the box, but more like the product Lexi is supposed to be.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The messiest part was threading new context through existing call paths without breaking the follow-up work already in progress. Root lookups, nested lookups, follow-ups, and Buddy captures all now accept session context, but they each build payloads slightly differently. That required careful updates to Swift payload structs, proxy parsing, and prompt generation.

Another issue came from Vision OCR: the first implementation used a property that was not available on the project’s macOS SDK. The build caught it, and we removed that property instead of fighting the framework.

AssemblyAI also had a subtle behavioral trap. A realtime transcription service can emit “turn” messages before the user releases the hotkey. If Lexi finalized on the first turn, quick Buddy could submit too early. We fixed that by only delivering the final AssemblyAI transcript after `requestFinalTranscript()` is called on release.

### Step 7 — Watch Out: Future Pitfalls

The biggest future pitfall is assuming provider scaffolding equals production reliability. AssemblyAI and ElevenLabs are wired in, but they still need real proxy secrets and live testing. Voice systems fail in human ways: fast press-and-release, background noise, token endpoint errors, network changes, and permission oddities.

Another pitfall is image payload creep. The proxy can take large bodies, but latency and cost grow quietly. Adaptive compression should remain intentional. If answers are bad, first inspect OCR and image diagnostics before simply raising the cap.

Also watch out for callout coordinates. Mapping model-provided pixel coordinates back to macOS screen coordinates is easy to get 90% right and still feel wrong. The precise-region path is the safest because the source rectangle is known. Focused-window coordinates may need more real-world testing across Retina displays and multi-monitor setups.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner would see “add voice” as the feature. A senior person sees that voice is actually a pipeline: shortcut state, permission state, microphone buffers, transcription provider, finalization timing, screenshot timing, prompt context, streaming answer, cancellation, and optional playback. If any link is weak, the whole thing feels broken.

The non-obvious senior move was keeping Lexi’s identity intact. Clicky’s best ideas are useful, but copying the whole product would make Lexi less differentiated. The expert version of borrowing is selective: take the engine parts, not the paint job.

Another expert detail is bounded memory. Session context is valuable, but unbounded history becomes slow, expensive, and privacy-risky. Lexi keeps recent memory in-process and compact, which gives continuity without turning every request into a giant transcript dump.

### Step 9 — The Transfer: Lessons That Apply Everywhere

The transferable lesson is: when analyzing a competitor or adjacent product, do not ask “what should we copy?” Ask “which underlying capability changes our core loop?” Clicky’s cursor personality is not the point. Its low-friction voice loop, provider abstraction, screenshot labeling, and response-state machine are the reusable assets.

This applies to any product strategy. If you run a sales process, do not copy another company’s whole funnel just because it looks slick. Identify the one mechanism that shortens time-to-trust. If you build content, do not copy someone’s style wholesale. Find the mechanism that improves retention or clarity.

The single most important takeaway: Lexi gets stronger when it borrows infrastructure from companion apps while staying disciplined about being a research comprehension accelerator.

## 2026-06-24 — Cursor Buddy follower UI and activity polish

### Step 1 — The Approach: What Did We Do and Why?

We added the smallest possible always-visible sign that Lexi is alive: a tiny liquid-glass cursor Buddy that follows near the real cursor. The reasoning was product trust. A background helper feels broken if nothing on screen acknowledges that it exists. The follower gives Lexi a pulse without turning the app into a loud character.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not replace the real cursor or hide it. That would be risky and annoying because the system cursor is sacred UI. We also did not add a large panel or mascot. The request was polish and presence, not another attention-demanding surface.

### Step 3 — How the Parts Connect: The Architecture of the Work

The new `BuddyCursorFollowerController` owns transparent non-interactive overlay panels across screens. It samples the real mouse location, offsets a tiny Buddy next to it, and uses spring physics so it accelerates toward the cursor and decelerates as it catches up. `AppDelegate` and `BuddyCaptureCoordinator` now send activity states into that controller: idle, listening, selecting, working, streaming, and error.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

AppKit panels were the right tool because this UI must float above normal apps, follow the mouse globally, join Spaces, and ignore mouse events. A SwiftUI view inside a normal app window would not be able to follow the cursor across the whole desktop. The animation uses a timer plus a simple spring model rather than a fixed delay, because a spring gives the “catches up naturally” feeling you wanted.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized subtlety. The idle state is translucent and small. Active states add a minimal halo and three animated waveform bars. That means it is not yet a full branded animation system, but it should feel calmer and more premium than a big spinner.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The main design trap was making the follower useful without interfering with clicks. The overlay panels must be high enough to be visible but also `ignoresMouseEvents = true`, otherwise Lexi would literally block the user from using their computer.

### Step 7 — Watch Out: Future Pitfalls

The next testing risk is visual feel, not compilation. The spring constants, cursor offset, opacity, and waveform size will probably need tuning after you use it for a few minutes. Cursor-follow UI can go from delightful to annoying very quickly if it is too bright, too close, or too laggy.

### Step 8 — The Expert Eye: What a Beginner Would Miss

The expert detail is that polish is state architecture, not just drawing. A pretty cursor blob is not enough. It has to know when Lexi is listening, capturing, asking, streaming, done, or errored. That is what makes the animation communicate something real instead of becoming decoration.

### Step 9 — The Transfer: Lessons That Apply Everywhere

Good ambient UI should answer one question: “Is the system with me right now?” If the answer is yes, it can stay tiny. This applies to voice apps, automations, AI agents, and even sales tools. The best status indicator is often not a dashboard; it is a small, timely signal that the machine is paying attention.

## 2026-06-24 — Hold-to-select shortcuts and synchronized Buddy feedback

### Step 1 — The Approach: What Did We Do and Why?

We changed Lexi’s highlight and precise Buddy gestures from “press/release to trigger” into “hold while selecting, release to submit.” This matters because it gives the user a clear physical contract: while the keys are down, Lexi is listening for a selection; when the keys come up, Lexi either acts or cancels.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not keep showing a no-selection panel on empty Option+Space release. That would make a canceled gesture feel like an error. Empty release now cancels quietly for the text path.

### Step 3 — How the Parts Connect: The Architecture of the Work

`HotkeyManager` now emits Option+Space press and release. `BuddyHotkeyMonitor` now begins precise screen capture on Option+Command press and ends it on modifier release. `BuddyCaptureCoordinator` records the region on mouse-up but waits for modifier release before submitting when the capture came from the shortcut.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

Carbon hotkeys still handle Option+Space because they are reliable for global keyboard shortcuts. The CGEvent-based Buddy monitor remains right for Option+Command because it needs more nuanced modifier-state tracking and cancellation.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized gesture clarity and synced feedback. The tradeoff is that Option+Space now asks the user to hold keys while selecting text, which can be physically more demanding than selecting first and pressing later. The UX is more intentional, but less casual.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The subtle part was deciding when screen capture should submit. Mouse-up means “the rectangle exists,” but modifier release now means “I am done and want Lexi to act.” Separating those two moments makes the behavior match the user’s mental model.

### Step 7 — Watch Out: Future Pitfalls

Some apps may treat Option+Space or held modifiers specially while selecting text. If text selection feels awkward in particular apps, the shortcut may need to become configurable.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner might focus on the hotkey alone. The expert detail is synchronization: the key state, cursor Buddy animation, selection state, and submission/cancellation state all need to tell the same story.

### Step 9 — The Transfer: Lessons That Apply Everywhere

Good interaction design makes invisible state tangible. Holding the key is not just input; it is a temporary mode. The UI should breathe only while that mode exists.

## 2026-06-24 — Moving capture hint, strict selection, voice-highlight, and liquid-glass panel polish

### Step 1 — The Approach: What Did We Do and Why?

We removed the static precise-capture prompt and moved that instruction into the cursor Buddy itself. The point is spatial consistency: if Buddy follows the cursor, its guidance should follow the cursor too. We also made highlight lookup stricter so Lexi only acts on actual selected text, not stale clipboard content.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not keep the full-screen overlay caption because it created a dead, static UI element. We also did not show an error when Option+Space has no selected text, because empty release is a cancel, not a failure.

### Step 3 — How the Parts Connect: The Architecture of the Work

`BuddyCursorFollowerController` now owns short-lived hint text that rides with the orb. `BuddyOverlayController` only draws the scrim and selection rectangle. `ClipboardFallback` clears and restores the pasteboard around synthetic copy, preventing stale clipboard answers. Highlight captures can now carry an optional voice question through `CapturedSelection`, `ExplainClient`, and the proxy prompt.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

The cursor hint belongs in the AppKit overlay because it needs global desktop positioning. The answer panel remains SwiftUI because product styling, layout, and composer controls are much faster to iterate there.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized correctness over convenience for highlight lookup. If nothing is selected, Lexi cancels. That removes accidental answers but means users need to be intentional about the selection. For voice-highlight, spoken questions are optional; no transcript keeps the existing automatic explanation flow.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The clipboard bug was a classic macOS trap. If synthetic copy fails, the pasteboard may still contain old text. Reading it directly makes the app look like it selected something random. Clearing first and restoring afterward makes the fallback honest.

### Step 7 — Watch Out: Future Pitfalls

The highlight voice question depends on the proxy understanding the optional `question` field. The app can send it now, but production responses need the updated proxy deployed too.

### Step 8 — The Expert Eye: What a Beginner Would Miss

The expert detail is ownership of transient UI. The full-screen capture overlay should own selection geometry, not instruction copy. The cursor Buddy should own ephemeral command feedback because it is the thing the user is visually tracking.

### Step 9 — The Transfer: Lessons That Apply Everywhere

Good product UI avoids dead surfaces. If an instruction is tied to an action near the cursor, put it near the cursor and make it move with the action. Static overlays are useful for boundaries; dynamic companions are useful for guidance.

## 2026-06-24 — Top-right answer panel, cleaner answer surface, and deeper inference

### Step 1 — The Approach: What Did We Do and Why?

We treated this as two connected problems: the answer panel was visually noisy, and the backend was being instructed to be too brief. The UI fix removed the source/context material beneath generated answers, moved the panel to a predictable top-right home, and gave the answer area more room. The inference fix removed the old “under ~60 words” behavior and told the backend to answer spoken questions first or infer the likely question when there is no voice prompt.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not redesign the whole panel or remove loading/error diagnostics. Those are still useful when something goes wrong. We also did not remove the optional voice-highlight path because it was already wired through the app; the smarter move was to make the backend respect that question field more strongly.

### Step 3 — How the Parts Connect: The Architecture of the Work

The Swift panel owns where the answer appears and how much space it gets. The proxy owns how the model thinks. Those two pieces need to agree: a deeper answer needs a taller answer box, and a taller answer box only matters if the backend stops producing tiny replies.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

The UI stayed in AppKit plus SwiftUI because AppKit controls the floating `NSPanel` placement and SwiftUI controls the glass card layout. The inference change stayed in the TypeScript proxy because prompt policy and token limits belong server-side, not inside the Mac app.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized predictability and reading comfort. The tradeoff is that the panel no longer appears near the selected text, so your eyes travel to the top-right instead of staying at the highlight. That is intentional: Lexi now behaves more like a stable assistant tray than a cursor tooltip.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The main discovery was that the source/context clutter appeared in more than one UI state. Streaming answers appended capture details, and final lookup cards also displayed source/window/app rows. Fixing only one would have left the problem half-solved.

### Step 7 — Watch Out: Future Pitfalls

The deployed Railway proxy must receive the prompt/token-limit changes before production answers get deeper. The local Swift build passes, but the installed `/Applications/Lexi.app` will not change until the app is packaged and replaced.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner might only make the box taller. The senior move is noticing that answer length, scroll comfort, metadata noise, and panel position are one product loop. If one part changes without the others, the experience still feels wrong.

### Step 9 — The Transfer: Lessons That Apply Everywhere

When a product feels “thin,” check both the surface and the engine. Sometimes the UI is cramped; sometimes the prompt is timid; often it is both. Good fixes line up the physical space with the quality of thought you expect inside it.

## 2026-06-24 — Collapsed answer pill with hover-to-expand

### Step 1 — The Approach: What Did We Do and Why?

We changed the answer panel from “always open as the full card” to “start as a tiny signal, then expand only when you ask for it by hovering.” The reason is attention budgeting: Lexi should tell you it is working without stealing the entire top-right corner.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not just visually shrink the panel while keeping the full invisible window. That would still block screen space. Instead, the actual `NSPanel` now changes physical size between a small pill and the full answer card.

### Step 3 — How the Parts Connect: The Architecture of the Work

The AppKit panel owns real window geometry, while the SwiftUI view owns the two visual states. Hover changes the SwiftUI expansion flag; that flag calls back into AppKit to animate the window frame from the top-right anchor.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

SwiftUI `onHover` is the right tool for the interaction. AppKit `setFrame(... animate:)` is the right tool for making the desktop window itself expand smoothly instead of faking it inside a big hitbox.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized a quiet default state. The tradeoff is that the user now has one extra gesture — hover — before reading the full answer. That is intentional because the answer should be available, not automatically dominant.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The subtle issue was final answers. Lexi converts a completed stream into a lookup card, so the collapse behavior had to include `.lookup`, not just `.loading` and `.streaming`. Otherwise the card would still pop open when the answer finished.

### Step 7 — Watch Out: Future Pitfalls

If the cursor happens to already be in the top-right when the pill appears, it may expand immediately. That is logically correct hover behavior, but if it feels jumpy in practice, the next refinement would be a tiny hover delay.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner might animate the view but leave the window big. The expert detail is making the real interactive footprint match the visual footprint. What you see and what blocks your screen should be the same size.

### Step 9 — The Transfer: Lessons That Apply Everywhere

Good UI often starts as a low-commitment signal. Notification badges, typing indicators, and loading pills all follow the same idea: show enough to reassure the user, then reveal depth only when they lean in.

## 2026-06-24 — Fixing hover expansion hang and deploying deeper inference

### Step 1 — The Approach: What Did We Do and Why?

We fixed the hover expansion by removing the feedback loop. The original version expanded on hover and collapsed on hover exit, but changing the real window size during the transition can create rapid enter/exit events near the edge. The safer behavior is one-way: each answer starts as a pill, hover expands it, and it stays expanded.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not try to tune the spring animation first because the bug was structural, not aesthetic. A prettier animation still would have had the same oscillation risk.

### Step 3 — How the Parts Connect: The Architecture of the Work

SwiftUI now changes only from collapsed to expanded. AppKit only resizes the native panel when the expanded state actually changes, not on every streamed token. That separation keeps streaming text updates from repeatedly poking the window manager.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

The important tool was restraint: fewer state transitions. We also deferred the AppKit resize with `DispatchQueue.main.async`, letting SwiftUI finish its hover update before the native window frame moves.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized stability. The tradeoff is that the panel does not auto-collapse when the cursor leaves. That is acceptable because the main pain was startup screen takeover; once you intentionally expand, keeping it open is predictable.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The rainbow spinner was likely not an AI/backend delay. It was UI churn: hover state, SwiftUI transition, native frame animation, and streaming updates all interacting too frequently.

### Step 7 — Watch Out: Future Pitfalls

If auto-collapse comes back later, it should use a delay and explicit mouse tracking, not raw `onHover` exit during a resizing transition.

### Step 8 — The Expert Eye: What a Beginner Would Miss

The expert detail is that animation bugs are often state-machine bugs. The fix is not always “make it smoother”; sometimes it is “make fewer states possible.”

### Step 9 — The Transfer: Lessons That Apply Everywhere

When a system hangs during a transition, look for loops between signal and response. If the act of responding creates a new signal, you may have built a tiny machine that argues with itself.

## 2026-06-24 — Auto-expand completion and Perplexity research path

### Step 1 — The Approach: What Did We Do and Why?

We split the work into UI timing and answer accuracy. For UI, Lexi now stays small while generating, auto-opens when the final answer is ready, and collapses after the cursor leaves. For accuracy, we added a proxy-side Perplexity research step so exact names and niche definitions can be web-grounded before Claude writes the final answer.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not put Perplexity directly in the Mac app because API keys belong behind the proxy. We also did not force every lookup through research with no controls; the new mode is configurable so accuracy and latency can be tuned.

### Step 3 — How the Parts Connect: The Architecture of the Work

The Mac app still owns capture and display. The Railway proxy now owns both research and final synthesis: Perplexity gathers source-grounded context, then Claude uses that context plus the passage to answer in Lexi’s voice.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

Perplexity Sonar fits this use case because it is built for web-grounded answers and citations. Exa is strong for search/retrieval, but Sonar gives an answer-shaped research brief that can be fed directly into Claude.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized accuracy for ambiguous/niche terms. The tradeoff is added latency when research triggers. That is why research is guarded by environment variables and auto heuristics.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The key constraint is credentials. The integration is deployed, but production research remains inactive until `PERPLEXITY_API_KEY` is set in Railway. Code alone cannot create the external research capability without that key.

### Step 7 — Watch Out: Future Pitfalls

Research should be monitored for latency. If it feels slow, use `LEXI_RESEARCH_MODE=auto`; if accuracy matters more than speed, use `always`.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner might ask Claude to “search harder.” The expert move is adding a second system with a different job: retrieval first, synthesis second. Accuracy improves when each model does the job it is best at.

### Step 9 — The Transfer: Lessons That Apply Everywhere

When a system guesses too well, that is still a bug. Prediction is not evidence. For high-accuracy workflows, separate “find the facts” from “explain the facts.”

## 2026-06-25 — Turning Lexi from wrapper into context infrastructure

### Step 1 — The Approach: What Did We Do and Why?

We started from the uncomfortable truth: Lexi was useful, but the backend still looked too much like a nice Mac wrapper around Claude. The strategic move was not to pretend we can out-train Anthropic. The better move was to own the layers Claude does not own: Jeremy's laptop context, Jeremy's repeated questions, Jeremy's workflow data, and the routing logic that decides whether an answer should be fast, researched, personal, visual, or action-oriented.

So we wrote the roadmap first, then implemented the first infrastructure pieces. The doc gives Lexi a north star. The code gives that north star its first rails: an inference route planner, route telemetry, durable local events, a lightweight local context sampler, and lexical retrieval from prior Lexi interactions.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not jump straight into fine-tuning. That would be like buying a race engine before knowing whether the car has wheels. Fine-tuning only makes sense once Lexi has examples, labels, and evals. We also did not build a full vector database or a GPU inference stack today. Those are real future pieces, but they would add complexity before the product has enough data to justify them.

The rejected shortcut was “just make the prompt smarter.” Better prompts help, but they do not create a moat. A moat comes from owned data, retrieval, feedback, and latency control.

### Step 3 — How the Parts Connect: The Architecture of the Work

The roadmap describes the whole house. The implementation poured the foundation. The proxy now creates an `InferencePlan` for each request, which is the start of a real orchestration layer. The Mac app now records completed interactions locally, which is the start of a data layer. The app also samples active app/window context locally, which is the start of a context daemon. Finally, old Lexi answers can be retrieved lexically and included in future inference context, which is the first tiny version of personal memory retrieval.

The order matters. You cannot fine-tune before you collect data. You cannot route intelligently before you name the routes. You cannot personalize before you remember. This work puts those prerequisites in place.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

We used JSONL files instead of SQLite or a vector database for the first data store because JSONL is boring in the best way. Each event is one line. It is easy to append, inspect, back up, and migrate. We used TypeScript route objects in the proxy because the backend already lives there and because routing belongs before model calls. We used macOS `NSWorkspace` and window metadata for lightweight context because it gives useful signal without screenshotting the user by default.

Those choices are intentionally modest. This is infrastructure scaffolding, not a science project.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized building durable seams. The route planner is not yet an ML classifier. The memory retrieval is lexical, not embedding-based. The context sampler records app/window changes, not full page content. These are weaker than the eventual versions, but they are safe, fast, and validate the architecture.

The sacrifice is intelligence depth today. The benefit is that the system now has places where deeper intelligence can be plugged in later without rewriting everything.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The main implementation snag was TypeScript narrowing. The first version of the research helper used a type predicate, which made the route planner's false branch narrow the request to `never`. That is TypeScript saying, “based on your logic, this code can never run,” even though we knew it could. The fix was to make the helper return a plain boolean and keep type narrowing explicit.

This is a good example of infrastructure work: sometimes the hard part is not the feature but making the shape of the system precise enough that the compiler agrees.

### Step 7 — Watch Out: Future Pitfalls

The next danger is collecting lots of local data without a retrieval/eval discipline. Data alone is not a moat; useful, structured, retrievable data is. Another pitfall is turning every request into deep research. That will make Lexi accurate but slow. The product needs both lanes: fast answers for common context and deep research for ambiguous facts.

Also watch privacy. The moment Lexi starts seeing more of the laptop, trust becomes the product.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner might think the moat is “use a better model.” The senior view is that the model is only one ingredient. The recipe is context selection, memory, routing, evaluation, and latency. The non-obvious thing is that the first defensible model is not a neural network. It is the data model: what Lexi chooses to remember and how it retrieves it.

### Step 9 — The Transfer: Lessons That Apply Everywhere

When you are building on top of a powerful platform, do not compete with the platform where it is strongest. Own the surrounding workflow. Shopify did not need to own Visa. Uber did not need to own GPS satellites. Lexi does not need to own Claude yet. It needs to own the private context layer that makes Claude useful in a way no generic chatbot can match.

## 2026-06-25 — Active Composition: writing directly into the user's text box

### Step 1 — The Approach: What Did We Do and Why?

We turned your idea into a separate product mode instead of jamming it into the existing explanation panel. The old Lexi loop was “highlight text, ask what it means, show answer in Lexi.” The new loop is “click into a text field, speak what you want written, stream the answer into the field.” Those are different jobs, so they needed different routing, prompting, and insertion behavior.

The first implementation uses the existing Option+Space voice flow because that is already the muscle memory. If there is selected text and the spoken question sounds like explanation, Lexi still explains. If the spoken command sounds like writing — write, draft, generate, create, model, outline, rewrite — Lexi composes into the active editor.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not start with app-specific integrations for Notion, Google Docs, Obsidian, Slack, and every editor. That would be too slow and fragile. We also did not use direct Accessibility value-setting as the only insertion method because many modern editors are web views and do not expose clean writable values.

The pragmatic first version uses pasteboard streaming: Lexi receives model deltas, temporarily puts each delta on the clipboard, synthesizes Command+V, and restores the clipboard afterward. It is not perfect, but it is the most universal first bridge into arbitrary text boxes.

### Step 3 — How the Parts Connect: The Architecture of the Work

There are four pieces. The context capturer asks macOS, “what app and text field is focused?” The intent detector asks, “is this a writing command or a reading question?” The proxy `/compose` endpoint asks Claude for only the text that should be inserted. The streaming inserter pastes each generated chunk into the active editor.

The key is that the Lexi panel stays out of the way. If the panel appeared, it might steal focus, and then Lexi would paste into itself instead of your note.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

We used macOS Accessibility to detect the active text target and capture surrounding context. We used the existing voice transcription path because the product already knows how to listen while Option+Space is held. We used SSE streaming from the proxy because Lexi already has a robust streaming model path. We used pasteboard insertion because it works across more apps than direct text mutation.

This is a classic wedge: build the cross-app primitive first, then specialize later where needed.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized universality and speed of implementation. The tradeoff is that pasteboard streaming can create lots of undo steps and temporarily owns the clipboard. Direct native insertion would be cleaner in some apps, but less universal. App-specific APIs would be best in a few apps, but would not solve the general product idea.

The current version is good enough to test whether the workflow feels magical. It is not the final insertion engine.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The main design mess was deciding when Option+Space should explain versus write. If we made every voice prompt compose, we would break the reading assistant. If we made every selection explain, we would lose rewrite/generate workflows. The compromise is a simple intent detector. It is heuristic, not intelligent yet, but it protects the existing product while opening the new mode.

Another subtle issue is focus. The whole feature depends on not stealing focus from the text editor. That is why composition uses cursor hints, not the normal Lexi answer card.

### Step 7 — Watch Out: Future Pitfalls

The biggest pitfall is assuming every app handles synthetic paste the same way. Google Docs, Notion, Slack, Obsidian, native TextEdit, and web forms may all behave differently. This needs hands-on testing in each major target. The second pitfall is undo behavior: streaming chunk-by-chunk may create many undo states. Later, we may want chunk coalescing or an “insert on completion” mode.

Also, never allow this in password fields or sensitive secure inputs.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner would think the feature is “call Claude and paste the answer.” The senior view is that the hard part is routing and focus. The model is easy. The difficult part is knowing when the user wants writing vs explanation, preserving the active app's focus, inserting text universally, and not damaging trust by pasting in the wrong place.

### Step 9 — The Transfer: Lessons That Apply Everywhere

Great AI products do not just answer; they land output where work actually happens. The interface shift from “chat response” to “native insertion” is the product insight. In any workflow, ask: where does the user ultimately need the output to live? Build the AI so it appears there directly.

## 2026-06-25 — Voice latency pass from Freeflow/Wispr Flow analysis

### Step 1 — The Approach: What Did We Do and Why?

We used Freeflow as a practical benchmark for the part of Lexi that matters most for personal agents: the voice loop. The lesson was not “copy Freeflow wholesale.” The lesson was to identify where Freeflow is latency-oriented and port the low-risk ideas into Lexi's existing architecture.

The changes focused on the path from hotkey press to first useful output: faster audio chunks, faster transcript finalization, less startup overhead for realtime transcription, and better timing logs.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not rewrite Lexi's audio stack around `AVCaptureSession` yet. Freeflow has a more advanced recorder, but Lexi's current `AVAudioEngine` path is simpler and already supports streaming providers. A rewrite would be higher risk than necessary for a first latency pass.

We also did not add Groq Whisper upload transcription as the main path. Freeflow uses Groq-hosted Whisper models, not a magical fine-tuned Wispr model. Upload transcription can be fast, but it is still end-of-recording transcription. For short agent commands, realtime streaming remains the better default.

### Step 3 — How the Parts Connect: The Architecture of the Work

Freeflow separates the pipeline into capture, transcription, context, cleanup, and paste. Lexi already has similar seams: `BuddyVoiceCapture`, `BuddyTranscriptionProvider`, the local proxy, and `/compose` or `/explain` streaming. We improved the seams instead of replacing them.

The new flow is: start voice capture, use a smaller audio tap buffer, open the provider session with better diagnostics, stream partial transcript, shorten AssemblyAI final fallback, then route into compose/explain.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

The main tool was measurement. Before chasing model choices, we added logs for provider startup, audio engine startup, first partial transcript, stop request, and final transcript. Latency work without phase timing is just vibes.

We kept AssemblyAI as the realtime provider because Lexi already supports it. We optimized around it by reusing provider state, prewarming a temporary token, and bounding token fetch time.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized responsiveness over perfect final transcript formatting. Shortening AssemblyAI fallback from 2.8s to 1.2s means Lexi may sometimes proceed with the latest partial instead of waiting for a fully formatted final. For voice commands, that is usually the right tradeoff. If you are dictating a polished paragraph, you may want a different lane later.

We also reduced the audio buffer from 4096 to 1024 frames. That improves responsiveness but slightly increases callback frequency.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The main subtlety was token prewarming. A naive cache could accidentally reuse a temporary AssemblyAI token across sessions if the provider treats the token as session-scoped. The safer design is a one-shot prewarm: fetch a token ahead of time, consume it once, and then clear it.

Another subtlety is measurement origin. Lexi's earlier hotkey timing was closer to release-time than press-time for one path, which makes latency look better than it feels. We changed that so future logs are more honest.

### Step 7 — Watch Out: Future Pitfalls

Do not blindly optimize only the model. The user's felt latency is the sum of hotkey handling, mic startup, STT first partial, transcript finalization, request routing, model first token, and insertion. A faster model cannot fix a slow finalization delay.

Also, do not add transcript cleanup into the agent-command path until it is proven necessary. Cleanup is useful for dictation, but it adds a network hop and can accidentally change commands.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner would ask, “Which model is Wispr using?” A senior engineer asks, “Where are the milliseconds going?” Freeflow's value is not just model selection. It is the whole pipeline: realtime audio, context-aware processing, tight timeouts, paste orchestration, and run logs.

### Step 9 — The Transfer: Lessons That Apply Everywhere

Latency is a product feature, not only an engineering metric. If the assistant is going to feel like an extension of your intent, every stage must be designed to start early, stream incrementally, and avoid waiting for perfection when good-enough is enough to act.

## 2026-06-29 — Chat-style Lexi conversation history

### Step 1 — The Approach: What Did We Do and Why?

We started by finding where Lexi actually renders answers. The important file was `RawCapturePanelController.swift`, because that one class owns the floating panel, its expanded state, the answer display, and the follow-up composer. The existing app already had the concept of a lookup stack: every answer can have a child follow-up or nested lookup. So the right move was not to invent a second chat system. We turned the existing stack into a visible conversation timeline.

The reason this matters is that chat UI is mostly about continuity. Before this change, Lexi behaved like a microscope: you looked at the current answer only. After the change, it behaves more like a conversation: your prompt appears, Lexi's answer appears, then follow-ups append underneath in order. You can scroll back up instead of losing the previous turn.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

One possible path was to build a brand-new chat model separate from `LookupNavigationStack`. That would have made the UI look fresh, but it would duplicate state and create bugs where the UI conversation and the actual request lineage disagree. We rejected that because Lexi already uses the stack to know what answer a follow-up belongs to.

Another path was to only rename the button and leave the answer panel as a single large card. That would be quick, but it would not solve the real product problem: when you ask follow-ups, you need memory on screen. A single-card answer is fine for one-off explanations; it is weak for an actual assistant.

### Step 3 — How the Parts Connect: The Architecture of the Work

Think of the conversation like a string of beads. Each `LookupNode` is one bead: it has the thing you asked about and the answer Lexi generated. `LookupNavigationStack.activePath` is the current string of beads from the original question to the latest follow-up. The UI now loops over that path and renders each node as two bubbles: your prompt on the left, Lexi's answer on the right.

The follow-up composer stays pinned below the scrollable history. That order matters. If the composer were inside the long scroll area, it could drift out of reach after a long answer. By keeping the history scrollable and the input below it, Lexi feels closer to ChatGPT or Perplexity: read above, type below.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

We used SwiftUI's `ScrollView`, `ScrollViewReader`, and `LazyVStack` because the job is dynamic vertical layout. `ScrollView` gives the history area. `LazyVStack` is efficient for a growing list of turns. `ScrollViewReader` lets the panel jump to the latest message while streaming tokens arrive.

We also kept the existing AppKit panel architecture. The window behavior, Escape dismissal, hover expansion, and floating-panel behavior were already working. This was a content/layout change, not a reason to rebuild the shell.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized preserving Lexi's existing follow-up mechanics. That means the history shown is the active branch of the conversation, not every sibling branch you might have explored earlier. For normal follow-up conversations, that is exactly what you expect. For complex tree-style research, a future version might need a sidebar or branch switcher.

We also prioritized a clean single scroll area over the older selectable answer view. The previous answer card used a custom AppKit text view for selection. The new bubbles use selectable SwiftUI text, and the panel now asks the live selection when triggering a nested lookup. That keeps the keyboard workflow intact while making the UI much closer to a modern chat surface.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The main subtle issue was selection. It would have been easy to replace the old answer view with plain text and accidentally break the “highlight inside an answer, then press right arrow” workflow. The fix was to route nested lookup requests through the panel's live selected text, not only through the view model's cached selection.

The other practical mess was auto-scrolling. Streaming answers update many times as tokens arrive. If the UI does not scroll to the bottom on each answer-length change, the latest output can grow below the fold and feel broken. The scroll ID now includes answer lengths so streaming updates keep the newest content visible.

### Step 7 — Watch Out: Future Pitfalls

The biggest future pitfall is branch history. The underlying structure is a tree, but chat UI is linear. Right now we show the active path through that tree. If you start jumping between old nodes and asking alternate follow-ups, the UI will feel like a branch path rather than a complete transcript. That is acceptable for now, but it is the next thing to revisit if Lexi becomes a research companion.

Also watch the left/right convention. You specifically asked for user questions on the left and AI answers on the right, so that is how this works. Many chat products put the user on the right and the assistant on the left. If the UI ever feels visually reversed, this is the reason.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner might treat this as “add bubbles.” A senior person sees that the real work is state alignment: the visual transcript must match the request lineage the model is using. If those drift apart, the app becomes confusing fast. You might see one conversation on screen while the backend answers using a different parent answer.

The non-obvious part is that UI polish often means respecting existing invisible workflows. The nested lookup shortcut, live text selection, Escape dismissal, and hover expansion all still matter. A prettier UI that breaks those flows would be a regression.

### Step 9 — The Transfer: Lessons That Apply Everywhere

When improving a product interface, first find the existing source of truth. Do not create a new surface that merely looks right. Attach the new interface to the same state the product already trusts.

This applies outside software too. If you redesign a CRM dashboard, use the pipeline data sales already operates from. If you redesign a hiring tracker, use the candidate state recruiters actually update. Beautiful UI wrapped around duplicate state is just a prettier way to get confused.

The single most important takeaway: a great chat interface is not just bubbles and scrolling — it is a faithful visual history of the same context the assistant is actually using.

## 2026-06-29 — Command mode composition tuning

### Step 1 — The Approach: What Did We Do and Why?

We treated command mode as two systems that have to cooperate: the Mac app decides whether you are trying to write into an active field, and the proxy decides what text should be generated. The original behavior was weak because those two systems were not specific enough. Lexi could hear “make this paragraph more concise,” but the intent detector was too narrow, the writable-field detection was too conservative in some places and too vague in others, and the compose prompt did not strongly tell the model to replace selected text instead of talking about it.

So we tightened both halves. In Swift, we improved command detection and active text-field recognition. In the proxy, we made the compose prompt understand rewrite mode versus new-draft mode. That is the difference between “write a Slack reply” and “make this selected paragraph more concise.” One creates new text at the cursor; the other should replace the selected text.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

One tempting route was to call this a model problem and jump straight to “fine-tuning.” That would be premature. The failure was mostly instruction design and routing, not lack of model capability. A fine-tuned model would still behave badly if Lexi sent ambiguous context or failed to mark selected text as replacement material.

Another option was to make every spoken command inside any app write into the app no matter what. That is dangerous. Lexi should work across active text fields, but it should not paste into random non-editable surfaces or secure fields. So we broadened recognition of real text targets while keeping password/secure-field rejection.

### Step 3 — How the Parts Connect: The Architecture of the Work

Command mode now has a clearer pipeline. First, `CompositionIntentDetector` asks, “Does this sound like a writing/editing command?” It now recognizes more real phrases: shorten, tighten, polish, improve, proofread, fix grammar, make more concise, and similar commands.

Then `ActiveTextContextCapture` asks, “Is the current focused thing plausibly writable?” It checks direct Accessibility attributes, parent elements, child elements, roles, subroles, titles, descriptions, and common field labels like message, reply, comment, compose, input, editor, and textarea. If it is not writable, Lexi now shows “Click into a text field first” instead of accidentally explaining the selected text.

Finally, the proxy receives the composition request. The prompt now includes a `COMPOSITION MODE` line. For selected-text transformations, it says to replace the selected text only. For empty-cursor writing, it says to insert new text at the cursor and use context only for tone and format.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

We used Swift's Accessibility APIs because Lexi is a native macOS layer. That is how it can work in TextEdit, Notes, browsers, Slack, Obsidian, Notion, and other editors instead of being tied to one website.

We used the Railway production proxy because your installed app is configured to call `https://lexi-production-9152.up.railway.app`. Local prompt changes would not have mattered until the proxy was deployed. The verification therefore had to test both local builds and live production `/compose` responses.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized command accuracy over maximum creativity. Compose temperature was lowered so “make this paragraph more concise” is less likely to become a chatty critique. The tradeoff is that creative writing may be slightly less varied, but for command mode, obedience matters more than surprise.

We also added a direct Accessibility insertion path before paste fallback. Native fields can be edited more reliably this way. Web editors still need paste fallback because they often do not expose clean settable text values.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The useful mess was testing. A temporary local probe could confirm that TextEdit was considered writable, but it could not fully simulate installed Lexi's permissions for event posting. That exposed an important reality of macOS development: the executable identity matters. A random temp binary is not the same as `/Applications/Lexi.app` in the eyes of Accessibility and input monitoring.

The first production `/compose` test also showed the prompt was still too loose. The model produced a concise sentence, but it was too meta — it described the paragraph instead of simply rewriting it. That was valuable because it caught the exact failure mode you complained about. We tightened the prompt again, redeployed, and then production returned the kind of concise rewrite we actually wanted.

### Step 7 — Watch Out: Future Pitfalls

The next tricky area is app-specific editor behavior. TextEdit, Slack, Notion, Google Docs, Chrome textareas, and Obsidian may all accept insertion differently. Direct Accessibility insertion works best for native controls. Paste fallback works best for complex web editors. Some apps may still require special adapters later.

Also, “all active text fields” should never mean “all apps everywhere.” Password fields and secure inputs must stay off-limits. The safe version is: all normal writable fields that macOS exposes or that known editor hosts can accept paste into.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner might only tweak the prompt. A senior person checks the whole loop: intent detection, focused-field capture, selected-text semantics, insertion method, backend prompt, deployment target, and live verification. If any one of those is wrong, the feature feels broken even if the model is smart.

The non-obvious product detail is replacement semantics. “Make this concise” is not the same operation as “write a concise paragraph.” One should overwrite selected text; the other should insert new text. Great command tools understand that difference.

### Step 9 — The Transfer: Lessons That Apply Everywhere

When a tool follows commands poorly, do not immediately blame the intelligence layer. First check whether the system framed the task correctly. Did it know the user's intent? Did it know the object being edited? Did it know whether to replace or append? Did the deployed service actually receive the new instructions?

This applies to any workflow: sales automation, CRM cleanup, AI assistants, hiring ops. The output quality depends on routing and context as much as raw intelligence.

The single most important takeaway: command mode gets good when the system knows the difference between drafting new text and transforming the thing you selected.

## 2026-06-29 — Command mode edge-case hardening

### Step 1 — The Approach: What Did We Do and Why?

We treated your feedback as a routing and semantics problem, not just a “make the model better” problem. The two failures were concrete: delete commands did not actually delete, and Lexi could confuse answer questions with write commands when a text field was active.

So we separated command mode into clearer lanes: whole-selection deletion, selected-text transformation, new-text writing, and current-screen answering. Each lane now has a different behavior instead of everything getting pushed through the same compose endpoint.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not try to make the model output an empty string for deletion. That sounds simple but fails in streaming systems because no tokens means no insertion event. Delete needed to be an app-side action, not a model answer.

We also did not let every spoken sentence in a text field become a write command. If you ask, “What should I do next based on this email?” Lexi should answer using screen context, not paste text into the email draft.

### Step 3 — How the Parts Connect: The Architecture of the Work

The flow now works like a traffic controller. `CompositionIntentDetector` decides whether the instruction is a write/edit command, a whole-delete command, or an answer question. `AppDelegate` routes accordingly. `StreamingTextInserter` now has a direct `replaceSelection` path, so deletion can happen without waiting for the model.

For context awareness, answer questions with no selected text now use current-screen capture/OCR through the Buddy explain route. Compose requests also include visible-screen OCR in session context when available, so writing can reflect what is on screen, not only what is inside the focused editor.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

We reused Lexi's existing ScreenCaptureKit plus Vision OCR path because it already powers Buddy Capture. That gave current-screen context without inventing a new subsystem.

For testing, we used three layers: Swift routing tests for command classification, proxy prompt tests for compose-mode instructions, and live Railway `/compose` and `/explain` tests for real model behavior.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized correctness and safety over broad magic. “Delete this” now requires selected text; if there is no selected text, Lexi asks you to select text instead of guessing what to delete.

Screen OCR adds useful context but can add latency and depends on Screen Recording permission. That is the cost of making the agent see the current screen.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The routing tests caught a real bug: “what should I do next based on this customer email” was classified as compose because the detector saw the word “email.” That is exactly why edge-case tests matter. We added an answer-question guard so question-shaped prompts route to answering unless they explicitly begin as write/edit commands.

The delete classifier also needed nuance. “Delete this sentence” should delete. “Remove the em dashes” should not delete the whole selection; it should transform punctuation. We split those apart.

### Step 7 — Watch Out: Future Pitfalls

The hardest future bugs will be ambiguous commands. “Remove this paragraph” means delete. “Remove the em dashes from this paragraph” means transform. Humans infer that instantly; software needs explicit rules.

Also, current-screen context depends on permissions and app behavior. If Screen Recording or Accessibility is missing, the agent will have less context.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner might only test happy-path prompts like “write a reply.” A senior tests adversarially: answer questions containing writing-related nouns, delete commands with selected text, punctuation transforms, and context-dependent prompts where the answer must mention visible screen content.

The expert-level detail is that “delete” is not generation. It is an editor operation. Treating it like generation is why it failed.

### Step 9 — The Transfer: Lessons That Apply Everywhere

When an AI feature behaves badly, split intent from execution. First decide what operation the user wants. Then decide which tool should execute it. Do not use the model as a hammer for every nail.

The single most important takeaway: robust command mode is a router plus tools, not just a smarter prompt.

## 2026-06-30 — Safely finding and pushing the real running Lexi code

### Step 1 — The Approach: What Did We Do and Why?

We treated this like matching a physical object to its blueprint. The running object was `/Applications/Lexi.app`, but that app bundle is only the built artifact, not the source code. So we first identified the running process, read its bundle metadata, and then traced backward through Xcode's DerivedData and Jeremy's own Lexi handoff notes until the real source repo surfaced at `/Volumes/T7/Projects/Jeremy/Lexi`.

The key reason for this order was safety. Pushing the wrong repo is like mailing the wrong house keys to someone: Git will happily do it, but the result is confusion later.

### Step 2 — The Roads Not Taken: What Was Considered and Rejected?

We did not assume the first `Lexi` thing we found was source. Some matches were app caches, Chrome IndexedDB files, old app backups, or documentation. We also did not trust the stale Xcode blueprint alone, because it pointed to an older `openclicky` path that no longer existed locally.

The better path was triangulation: running process, bundle ID, executable hash, handoff documentation, local repo status, and GitHub repo metadata all had to agree.

### Step 3 — How the Parts Connect: The Architecture of the Work

The chain was: running app process → `/Applications/Lexi.app` → bundle ID `com.jeremyro.lexi` → matching packaged app in `/Volumes/T7/Projects/Jeremy/Lexi/dist/Lexi.app` → source repo at `/Volumes/T7/Projects/Jeremy/Lexi` → GitHub repo `jeremyjro/lexi`.

That chain matters because the app you use daily is the compiled result of the source. The source is what GitHub should receive. The hash match between the running executable and the packaged executable confirmed we were not pushing some unrelated Lexi experiment.

### Step 4 — Tools, Methods, Frameworks: Why These Specifically?

We used macOS process inspection to identify what was actually running, `plutil` and `codesign` to inspect app identity, Git commands to inspect repo state, and Swift/TypeScript builds to verify the code still compiled. This is a practical release checklist: identify, compare, verify, then commit.

### Step 5 — The Tradeoffs: What Was Prioritized, What Was Sacrificed?

We prioritized correctness over speed. It took longer than blindly running `git push`, but it avoided pushing the wrong folder. We also excluded the stray `._LEXI_PRODUCT_SPEC.md` AppleDouble file because that is external-drive metadata, not product source.

### Step 6 — The Mess: Mistakes, Dead Ends, Wrong Turns

The main wrong turn was the stale Xcode blueprint. It mentioned `openclicky` and an older `Percy` remote, which looked plausible but did not match the actual source checkout. The recovery move was to keep looking until the T7 path appeared in the handoff notes and Spotlight results.

### Step 7 — Watch Out: Future Pitfalls

External drives and renamed projects create archaeological layers. A Mac app can be in `/Applications`, the package can be in `dist/`, and the real repo can be somewhere else entirely. Before pushing, always prove the repo matches the artifact you care about.

Also watch for secrets in Git remotes and env files. The code content had only placeholders, but remote URLs and local config can contain credentials and should not be repeated in public notes.

### Step 8 — The Expert Eye: What a Beginner Would Miss

A beginner might search for “Lexi” and push the first repo. The senior move is checking identity from multiple angles: bundle identifier, build version, executable hash, remote repo, branch, and diff contents. One signal can lie; five matching signals are evidence.

### Step 9 — The Transfer: Lessons That Apply Everywhere

When you inherit or revisit a project, do not start by acting. Start by establishing identity. In code, as in operations, the first question is not “what command do I run?” It is “am I standing in the right place?”

The single most important takeaway: before pushing code, prove that the source repo, built artifact, and GitHub destination all point to the same product.
