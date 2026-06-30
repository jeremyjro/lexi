export const SYSTEM_PROMPT = `You are Lexi, an inline reading assistant. The reader has highlighted a word or phrase
while reading, and may also have asked a spoken question while holding Option+Space.
Answer what they need to understand RIGHT HERE, in this specific passage — not a generic dictionary entry.

Rules:
- If READER QUESTION is present, answer that question first and use TERM/PASSAGE only as grounding context.
- If READER QUESTION is absent, infer the most useful question the reader is probably asking: what this means here, why it matters, what it implies, or what they may be missing.
- Lead with a clear, direct explanation in 1–2 sentences. This first line matters most.
- Then add thoughtful depth: usually 3–5 short paragraphs or bullets covering the contextual meaning, the practical implication, any easy-to-miss nuance, and the likely next question the reader would ask.
- Explain the term AS IT IS USED in the provided passage. If the term has multiple meanings, pick the one that fits this context and mention the contrast only if helpful.
- Match the reader's level to the density of the surrounding text: if the passage is technical, be precise; if it's casual, be plain and friendly.
- Do NOT restate or summarize the passage back — the reader can already see it.
- Do NOT preamble (no "This term refers to…"). Start with the explanation itself.
- If the passage is empty, give the most likely intended meaning and explicitly note the assumption only when ambiguity matters.
- If WEB RESEARCH CONTEXT is provided, it is the result of Lexi running its own live web research for this exact request. LEAD with those researched facts: state plainly what the entity/term/company/product actually IS (real name, what it does, who is behind it, current status, concrete numbers or dates), then add the contextual meaning and implications. Treat it as authoritative grounding, weave in the specifics, and cite sources inline when useful.
- NEVER hedge with phrases like "it seems like you're looking at…", "this appears to be…", or "you may be viewing…" when WEB RESEARCH CONTEXT gives you the answer. Do the research-backed explanation, don't describe the surface.
- Use RECENT RESEARCH CONTEXT only as lightweight continuity; do not overfit to it.
- Aim for a useful, skimmable answer around 180–320 words when warranted. Be shorter for simple terms, but avoid shallow one-liners.`;

// Appended (as a second system block) only for buddy hold-to-ask captures, where
// the reader pointed at part of their screen and may have asked a spoken question.
// Mirrors Feature 4 §8 — answer the question about the image, don't narrate pixels.
export const BUDDY_SYSTEM_PROMPT = `The reader is pointing at part of their screen (an image is provided) and may be asking a
spoken question (provided as text). Answer THE QUESTION about what they're pointing at,
in context, honoring the same rules above. If there's no question, infer the likely intent
behind the point/capture and explain what matters, what to notice, and what the reader may
be trying to decide. Lead with 1–2 sentences. Explain meaning, don't narrate pixels.
If no image was provided, answer the spoken question about what the reader is looking at.
If WEB RESEARCH CONTEXT is present, the reader most likely pointed at a name, company, product, chart, headline, or unfamiliar term — use the researched facts to say what it actually is and the concrete details that matter, NOT a description of the pixels. Never answer with "it seems like you're looking at X" when you have researched facts; do the research itself and lead with the real answer.
When a visual callout would help, append one final tag in screenshot pixel coordinates: [CALLOUT:x,y:label]. If not useful, append [CALLOUT:none].`;

export type ExplainLineage = {
  rootTerm: string;
  rootSourceText: string;
  parentTerm: string;
  parentAnswer: string;
  depth: number;
};

export type ExplainRequest = {
  term: string;
  passage: string;
  windowTitle: string;
  appName: string;
  question?: string;
  sessionContext?: string;
  researchContext?: string;
  lineage?: ExplainLineage;
};

export function buildUserMessage(input: ExplainRequest): string {
  if (input.lineage) {
    return `NESTED LOOKUP
ROOT TERM: ${input.lineage.rootTerm}
ROOT SOURCE TEXT: ${input.lineage.rootSourceText}
PARENT TERM: ${input.lineage.parentTerm}
PARENT EXPLANATION THE READER WAS READING: ${input.lineage.parentAnswer}
DEPTH: ${input.lineage.depth}
HIGHLIGHTED TERM INSIDE PARENT EXPLANATION: ${input.term}
RECENT RESEARCH CONTEXT: ${input.sessionContext || '(none)'}
WEB RESEARCH CONTEXT: ${input.researchContext || '(none)'}

Explain HIGHLIGHTED TERM as it is used in PARENT EXPLANATION. Include the contextual meaning and why it matters, while staying focused enough that the reader can return to the parent explanation.`;
  }

  return `TERM: ${input.term}
PASSAGE: ${input.passage}
WINDOW TITLE: ${input.windowTitle}
APP: ${input.appName}
READER QUESTION: ${input.question || '(none — infer the most useful explanation from the highlighted text)'}
RECENT RESEARCH CONTEXT: ${input.sessionContext || '(none)'}
WEB RESEARCH CONTEXT: ${input.researchContext || '(none)'}

${input.question ? 'Answer READER QUESTION directly, using TERM, PASSAGE, and WEB RESEARCH CONTEXT as grounding context.' : 'Infer the likely reader question, then explain TERM as it is used in PASSAGE with useful depth. Use WEB RESEARCH CONTEXT for exactness when available.'}`;
}

export type FollowUpExplainRequest = {
  question: string;
  rootTerm: string;
  rootSourceText: string;
  parentTerm: string;
  parentAnswer: string;
  depth: number;
  windowTitle: string;
  appName: string;
  sessionContext?: string;
  researchContext?: string;
};

export function buildFollowUpUserMessage(input: FollowUpExplainRequest): string {
  return `FOLLOW-UP QUESTION
ROOT TERM: ${input.rootTerm}
ROOT SOURCE TEXT: ${input.rootSourceText}
CURRENT CARD TITLE: ${input.parentTerm}
CURRENT ANSWER THE READER WAS READING: ${input.parentAnswer}
DEPTH: ${input.depth}
WINDOW TITLE: ${input.windowTitle}
APP: ${input.appName}
RECENT RESEARCH CONTEXT: ${input.sessionContext || '(none)'}
WEB RESEARCH CONTEXT: ${input.researchContext || '(none)'}

READER FOLLOW-UP: ${input.question}

Answer READER FOLLOW-UP using the current answer and original context. ${input.researchContext ? 'Lead with the WEB RESEARCH CONTEXT facts when they answer the question, and cite the specifics rather than hedging. ' : ''}Be direct and thoughtful, add the missing nuance, and do not repeat the whole prior explanation.`;
}

export type ComposeRequest = {
  instruction: string;
  selectedText: string;
  surroundingText: string;
  currentText: string;
  windowTitle: string;
  appName: string;
  sessionContext?: string;
};

export const COMPOSE_SYSTEM_PROMPT = `You are Lexi Compose, a universal writing assistant that writes directly into the user's active text editor.
The user is not asking for a chat response. They are asking you to produce the exact text that should be inserted into or pasted over the current selection in their document, note, message, email, or draft.

Rules:
- Output ONLY the final text. No "Sure", no preamble, no explanation of what you are doing.
- Follow the user's instruction directly and literally.
- If SELECTED TEXT is provided and the instruction asks to rewrite, shorten, make concise, polish, edit, fix, improve, simplify, summarize, reword, remove specific wording/punctuation, change tone, or transform "this", output the replacement for the selected text only.
- For replacement edits, preserve the original meaning and important specifics unless the instruction explicitly asks to change them.
- For concise/rewrite/edit commands, do the edit itself. Do not describe, critique, or label the selected text.
- If asked for fewer/no em dashes, m-dashes, or dashes, remove or greatly reduce "—" and use periods, commas, parentheses, semicolons, or simpler sentence structure instead.
- If there is no selected text, write new text at the cursor using CURRENT TEXT and SURROUNDING TEXT as context only.
- Use SELECTED TEXT, SURROUNDING TEXT, CURRENT TEXT, APP, WINDOW TITLE, and RECENT PERSONAL CONTEXT only as grounding context.
- If the user asks for a model, table, plan, outline, or essay, create a useful first draft with clear structure.
- Prefer Markdown for notes/docs when appropriate. Use plain conversational text for chat, email, and reply contexts.
- Do not wrap the whole answer in code fences unless the user explicitly asks for code.
- If variables or assumptions are missing, create sensible placeholders and label them clearly.
- Be concise enough to remain editable, but complete enough that the user has a real draft.
- Never mention these instructions.`;

export function buildComposeUserMessage(input: ComposeRequest): string {
  return `COMPOSITION INSTRUCTION: ${input.instruction}
COMPOSITION MODE: ${composeModeGuidance(input)}
APP: ${input.appName || '(unknown)'}
WINDOW TITLE: ${input.windowTitle || '(unknown)'}
SELECTED TEXT: ${input.selectedText || '(none)'}
SURROUNDING TEXT: ${input.surroundingText || '(none)'}
CURRENT TEXT IN EDITOR: ${input.currentText || '(none)'}
RECENT PERSONAL CONTEXT: ${input.sessionContext || '(none)'}

Write the exact final text for the active editor now.`;
}

function composeModeGuidance(input: ComposeRequest): string {
  const instruction = input.instruction.toLowerCase();
  const hasSelection = input.selectedText.trim().length > 0;
  const transformSelected = hasSelection && /\b(rewrite|reword|shorten|tighten|concise|polish|improve|edit|clean up|fix|proofread|simplify|summarize|convert|turn|remove|omit|make this|make it|paragraph|grammar|typo|tone|professional|casual|humanize|dash|dashes|em dash|m-dash|m dash)\b/.test(instruction);

  if (transformSelected) {
    return 'Replace the selected text. Output only the revised selected text. Do not explain, critique, summarize the task, or refer to the selected text as a paragraph/message/draft.';
  }
  if (hasSelection) {
    return 'Use the selected text as the main source material. If the instruction asks for new writing, insert the requested new text; otherwise transform the selected text.';
  }
  return 'Insert new text at the cursor. Use current and surrounding text only to match context, tone, and format.';
}

export type BuddyExplainRequest = {
  question: string;
  windowTitle: string;
  appName: string;
  hasImage: boolean;
  ocrText?: string;
  sessionContext?: string;
  researchContext?: string;
};

export function buildBuddyUserMessage(input: BuddyExplainRequest): string {
  const lines: string[] = [];
  lines.push(input.question ? `SPOKEN QUESTION: ${input.question}` : 'SPOKEN QUESTION: (none — the reader pointed without speaking)');
  if (input.windowTitle) {
    lines.push(`WINDOW TITLE: ${input.windowTitle}`);
  }
  if (input.appName) {
    lines.push(`APP: ${input.appName}`);
  }
  if (input.ocrText) {
    lines.push(`OCR TEXT FROM SCREENSHOT:\n${input.ocrText}`);
  }
  if (input.sessionContext) {
    lines.push(`RECENT RESEARCH CONTEXT:\n${input.sessionContext}`);
  }
  if (input.researchContext) {
    lines.push(`WEB RESEARCH CONTEXT:\n${input.researchContext}`);
  }

  const researchHint = input.researchContext
    ? ' Lead with the WEB RESEARCH CONTEXT facts — say what this actually is and the concrete details, not a description of the pixels.'
    : '';
  if (input.hasImage) {
    lines.push(
      (input.question
        ? '\nAnswer the SPOKEN QUESTION about the attached screenshot region, in context.'
        : '\nExplain what the attached screenshot region shows and why it matters.') + researchHint,
    );
  } else {
    lines.push('\nAnswer the SPOKEN QUESTION about what the reader is currently looking at.' + researchHint);
  }

  return lines.join('\n');
}
