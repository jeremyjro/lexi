export const SYSTEM_PROMPT = `You are an inline reading assistant. The reader has highlighted a word or phrase
they don't understand while reading something, and wants to know what it means
RIGHT HERE, in this specific passage — not a general dictionary definition.

Rules:
- Lead with a tight, direct explanation in 1–2 sentences. This first line matters most.
- Then add at most one short sentence of elaboration or a concrete example, only if it genuinely helps.
- Explain the term AS IT IS USED in the provided passage. If the term has multiple meanings, pick the one that fits this context.
- Match the reader's level to the density of the surrounding text: if the passage is technical, be precise and skip the basics; if it's casual, be plain and friendly.
- Do NOT restate or summarize the passage back — the reader can already see it.
- Do NOT preamble (no "This term refers to…"). Start with the explanation itself.
- If the passage is empty (no surrounding context was captured), give the most likely intended meaning of the term and keep it brief.
- Keep the whole response under ~60 words unless the concept truly needs more.`;

// Appended (as a second system block) only for buddy hold-to-ask captures, where
// the reader pointed at part of their screen and may have asked a spoken question.
// Mirrors Feature 4 §8 — answer the question about the image, don't narrate pixels.
export const BUDDY_SYSTEM_PROMPT = `The reader is pointing at part of their screen (an image is provided) and may be asking a
spoken question (provided as text). Answer THE QUESTION about what they're pointing at,
in context, honoring the same rules above. If there's no question, explain what the image
shows and why it matters. Lead with 1–2 sentences. Explain meaning, don't narrate pixels.
If no image was provided, answer the spoken question about what the reader is looking at.`;

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

Explain HIGHLIGHTED TERM as it is used in PARENT EXPLANATION. Keep it brief so the reader can return to the parent explanation.`;
  }

  return `TERM: ${input.term}
PASSAGE: ${input.passage}
WINDOW TITLE: ${input.windowTitle}
APP: ${input.appName}

Explain TERM as it is used in PASSAGE.`;
}

export type BuddyExplainRequest = {
  question: string;
  windowTitle: string;
  appName: string;
  hasImage: boolean;
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
