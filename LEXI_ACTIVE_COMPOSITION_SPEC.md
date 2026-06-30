# Lexi Active Composition Spec

Last updated: 2026-06-25

## Summary

Lexi should let the user speak an instruction while focused in any writable text surface, then stream AI-generated writing directly into that text surface. The experience should feel closer to Wispr Flow plus Claude: the user stays in Obsidian, Notion, Slack, Google Docs, a plain notepad, or another text box; holds Option+Space; says what they want; releases; and watches the generated answer type into the page where their cursor already is.

This is different from the existing Lexi reading flow. The existing flow explains selected text in a Lexi panel. Active Composition writes into the user's current document.

## User problem

Today, generative AI usually writes inside a chat app. If the user wants the output in Obsidian, Notion, Slack, Google Docs, or a blank planning note, they must:

1. open a chatbot
2. write a prompt
3. wait for output
4. copy the result
5. paste into the real workspace
6. manually edit it there

That breaks flow. Lexi already has a native hotkey, voice capture, app/window context, and streaming backend. It should use those primitives to write where the user already is.

## Product goal

Make Lexi a universal AI writing layer for active text fields.

The user should be able to say:

- "Generate a financial model for my life. Include rent, food, travel, software, income, savings rate, and monthly burn."
- "Draft a Slack reply saying yes, but ask for the timeline."
- "Turn these bullets into a polished paragraph."
- "Create a table of costs and income assumptions."
- "Write a first-pass essay outline about defensible AI infrastructure."

Lexi should stream the generated text directly into the active editor.

## First-version UX

### Trigger

Use the existing Option+Space hold gesture.

- Press Option+Space: Lexi starts listening.
- Speak the instruction.
- Release Option+Space: Lexi decides whether this is reading/explaining or writing/composition.

### Routing behavior

1. If the user selected text and the spoken instruction is not a writing command, keep the current Lexi explain flow.
2. If the user selected text and the spoken instruction clearly asks to write, draft, generate, create, compose, rewrite, format, turn, convert, make, or model something, use Active Composition.
3. If there is no selection, there is a spoken instruction, and the focused UI element looks writable, use Active Composition.
4. If there is no selection and no spoken instruction, do nothing.
5. If there is a spoken instruction but no writable target, show a lightweight hint instead of pasting into a random app.

### Streaming behavior

- Lexi should not open the answer panel during composition because that can steal focus.
- Lexi should show cursor-buddy activity/hints only.
- As model deltas arrive, Lexi should paste/insert them into the active field.
- The text should appear progressively, not all at the end.
- The user's clipboard should be restored after streaming.

## What context Lexi should send

For each composition request, send:

- spoken instruction
- selected text, if any
- nearby/surrounding text from the focused text element, if accessible
- active app name
- active window title
- current session memory
- relevant prior Lexi memory retrieved locally

Do not send screenshots for this first version.

## Backend behavior

Add a new `/compose` streaming endpoint to the proxy.

Input:

```json
{
  "instruction": "Generate a financial model...",
  "selectedText": "optional selected text",
  "surroundingText": "optional active editor context",
  "currentText": "optional full focused text value, trimmed client-side",
  "appName": "Obsidian",
  "windowTitle": "Personal Finance.md",
  "sessionContext": "optional recent/personal Lexi context"
}
```

Output:

Server-sent events matching `/explain` where possible:

- `meta`
- `timing`
- `delta`
- `done`
- `error`

The model should output only the text to insert. No preamble like "Sure, here's...".

## Prompting rules

Lexi Active Composition should:

- obey the user's instruction directly
- write in the user's document, not about the document
- preserve useful structure when requested
- use Markdown tables/lists when suitable for notes and docs
- avoid chatbot preambles
- avoid wrapping the output in code fences unless explicitly requested
- infer practical structure when the user asks for a model, plan, essay, table, or draft
- use selected/surrounding text as context, not as text to summarize unless asked

## Engineering design

### Mac app components

1. `ActiveTextContextCapture`
   - Finds the focused UI element via Accessibility.
   - Captures app name, window title, selected text, selected range, full/current text, and surrounding text.
   - Determines whether the current target is plausibly writable.

2. `StreamingTextInserter`
   - Saves clipboard state.
   - For each model delta, places the delta on the pasteboard and synthesizes Command+V.
   - Restores the clipboard after streaming finishes or fails.
   - This works across more apps than direct Accessibility value-setting, especially web editors.

3. `CompositionIntentDetector`
   - Small heuristic gate to avoid hijacking normal explain lookups.
   - Detects explicit writing commands.

4. `ExplainClient.compose(...)`
   - Calls proxy `/compose`.
   - Streams deltas back to the app.
   - Reuses SSE metadata/timing handling.

5. `AppDelegate` integration
   - Reuses Option+Space voice capture.
   - If composition mode is selected, bypasses the answer panel and streams into focused field.

### Proxy components

1. `POST /compose`
   - Validates payload.
   - Uses a composition-specific system prompt.
   - Streams Claude output as SSE.
   - Emits metadata with route `active_composition`.

2. Prompt builder
   - Keeps composition rules separate from reading/explanation rules.

## Why paste-based insertion first?

There are three possible insertion strategies:

1. Accessibility `AXValue` replacement
2. Keyboard event typing
3. Pasteboard + synthetic Command+V

Pasteboard insertion is the best first version because it works across many app types, including web-based editors where Accessibility value-setting is inconsistent. The tradeoff is that the clipboard is temporarily used during generation. Lexi mitigates this by saving and restoring the clipboard afterward.

Future versions can prefer direct Accessibility insertion for native text fields and fall back to paste for complex web editors.

## Privacy and safety

- Do not stream text into password fields.
- Do not compose unless there is a spoken instruction.
- Do not paste if the focused target does not look writable.
- Restore clipboard after the operation.
- Keep generated content local to the active field; no extra copies beyond normal proxy inference and local event logs.
- Avoid screenshot capture in this flow.

## Known limitations in first version

- Google Docs/Notion/Slack behavior depends on whether synthetic paste events are accepted.
- Some editors may batch pasted chunks oddly.
- The clipboard is temporarily overwritten during generation.
- The route decision is heuristic, not a trained classifier.
- There is no undo grouping control; the host app decides how paste chunks appear in undo history.
- Full active-document context may not be available in web editors.

## Backlog

- Prefer direct Accessibility insertion for native text views.
- Add chunk throttling/coalescing to reduce undo spam.
- Add a user setting to choose instant streaming vs insert-on-completion.
- Add a small floating cancel control.
- Add rewrite mode that replaces selected text intentionally.
- Add browser/Obsidian/Notion-specific context adapters.
- Add an eval set for composition quality.
- Fine-tune a small model for composition intent detection after enough real data exists.
