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
- If WEB RESEARCH CONTEXT is provided, treat it as source-grounded evidence for exact definitions, names, organizations, products, current facts, niche terms, and ambiguity checks. Prefer it over guessing.
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

READER FOLLOW-UP: ${input.question}

Answer READER FOLLOW-UP using the current answer and original context. Be direct and thoughtful, add the missing nuance, and do not repeat the whole prior explanation.`;
}

export type BuddyExplainRequest = {
  question: string;
  windowTitle: string;
  appName: string;
  hasImage: boolean;
  ocrText?: string;
  sessionContext?: string;
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

  if (input.hasImage) {
    lines.push(
      input.question
        ? '\nAnswer the SPOKEN QUESTION about the attached screenshot region, in context.'
        : '\nExplain what the attached screenshot region shows and why it matters.',
    );
  } else {
    lines.push('\nAnswer the SPOKEN QUESTION about what the reader is currently looking at.');
  }

  return lines.join('\n');
}
