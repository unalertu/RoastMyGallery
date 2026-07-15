// Persona prompt definitions — edit freely to tune tone. Nothing else in the
// backend needs to change when you rewrite these.

/**
 * Gemini model to use. `gemini-3.1-flash-lite` is the current GA flash-lite;
 * `gemini-2.5-flash-lite` is retired for new API projects (returns 404).
 * `gemini-flash-lite-latest` is an alias if you'd rather auto-track releases.
 */
export const GEMINI_MODEL = "gemini-3.1-flash-lite";

/**
 * Vision-capable model for Deep Vision (Pro) photo batches. Full flash (not
 * -lite): the premium tier pays 5 credits for richer, photo-level commentary,
 * so it gets the strongest GA flash. Verified against this API key's
 * ListModels on 2026-07-15: plain `gemini-3.1-flash` does NOT exist for this
 * key (404) — the GA options were 3.1-flash-lite and 3.5-flash.
 */
export const GEMINI_VISION_MODEL = "gemini-3.5-flash";

export const PERSONA_PROMPTS = {
  roast: `You are a razor-sharp, witty friend looking at a summary of someone's photo library.
Write a playful ROAST of their photo habits. Tease them mercilessly about their patterns —
selfie ratios, screenshot hoarding, 3 AM activity, obsessions with certain subjects.
Sharp and funny, but never actually mean, never body-shaming, never about appearance,
never cruel about mental health. Punch at habits, not at the person.`,

  analyst: `You are a warm, perceptive observer looking at a summary of someone's photo library.
Write a gentle, curious ANALYSIS of what their photo habits might say about them —
what they pay attention to, when they feel most alive, what they quietly treasure.
Thoughtful and a little playful, like a friend who notices things. Not clinical,
no fake psychology jargon, no diagnoses.`,
};

/**
 * The model must answer with pure JSON (we also set responseMimeType).
 * Output contract (parsed by api/insight.js, then by the iOS client):
 *   { title, segments: [{ text, category|null }], shareLine }
 * Each segment is one narrative beat; `category` ties it to a real detected
 * category so the app can show a matching photo from the user's own library.
 */
const OUTPUT_FORMAT = `Respond with ONLY a JSON object (no markdown fences, no commentary) in exactly this shape:
{
  "title": "short punchy title for this person's gallery persona (max 6 words, no quotes inside)",
  "segments": [
    { "text": "one narrative beat, 1-2 sentences", "category": "dog" },
    { "text": "general commentary with no single clear subject", "category": null }
  ],
  "shareLine": "your single most quotable observation as a standalone one-liner (max 12 words)"
}
Rules for segments:
- 3 to 5 segments, total under 180 words. Plain text only — no markdown, no emoji.
- Together they must read as one flowing piece in the persona's voice.
- Set "category" ONLY to a value from the ALLOWED CATEGORIES list below, and only when
  that segment is clearly about that one subject. Otherwise use null. Never invent categories.
Ground every observation in the numbers provided. Never invent stats that aren't in the data.
The stats are anonymous aggregates; you know nothing else about this person.`;

/**
 * Category tags the model may attach to a segment — only things that actually
 * appeared in this user's stats, so the app always has a matching photo.
 */
export function allowedCategories(stats) {
  const categories = [
    ...stats.topCategories.map((c) => c.category),
    ...Object.keys(stats.animalCounts),
  ];
  if (stats.selfieCount > 0) categories.push("selfie");
  if (stats.screenshotCount > 0) categories.push("screenshot");
  return [...new Set(categories)].slice(0, 25);
}

// ---------------------------------------------------------------------------
// Deep Vision (Pro) — photo-level commentary on an explicitly consented batch

/**
 * Output contract for api/deep-vision.js (and the iOS client): an overall
 * summary line plus segments, each referencing the photo(s) it is about by
 * their zero-based position in the uploaded batch. The backend never sees
 * asset IDs — index-in-batch is the only shared reference.
 */
const DEEP_VISION_OUTPUT_FORMAT = (imageCount) => `Respond with ONLY a JSON object (no markdown fences, no commentary) in exactly this shape:
{
  "summary": "one overall observation about the whole batch (max 25 words)",
  "segments": [
    { "photoIndexes": [0], "text": "commentary about photo 0, 1-2 sentences" },
    { "photoIndexes": [3, 7], "text": "a pattern you noticed across photos 3 and 7" }
  ]
}
Rules:
- The ${imageCount} photos are numbered 0 to ${imageCount - 1} in the order given.
- 4 to ${Math.min(imageCount + 2, 10)} segments. Cover standout individual photos AND recurring
  themes/patterns across the batch. Every photoIndexes value must be a real index.
- Each segment 1-2 sentences, plain text only — no markdown, no emoji.
- Ground everything in what is actually visible. Never invent details.
- Never comment on anyone's body, weight, or attractiveness; never guess at
  identity, health, or private circumstances. React to scenes, habits,
  composition, and vibes — not to people's appearance.`;

export function buildDeepVisionPrompt({ persona, locale, imageCount }) {
  const language = locale
    ? `Write in the natural language implied by the locale "${locale}" (e.g. en_US → English, tr_TR → Turkish). JSON keys stay in English exactly as given.`
    : "Write in English.";

  return `${PERSONA_PROMPTS[persona]}

This time you are looking at the ACTUAL PHOTOS — a small batch this person
hand-picked from their library for a closer look. Give photo-level commentary:
what stands out in specific photos, and what patterns repeat across the batch.

${DEEP_VISION_OUTPUT_FORMAT(imageCount)}

${language}`;
}

export function buildPrompt({ stats, persona, locale }) {
  const language = locale
    ? `Write in the natural language implied by the locale "${locale}" (e.g. en_US → English, tr_TR → Turkish). JSON keys and category values stay in English exactly as given.`
    : "Write in English.";

  return `${PERSONA_PROMPTS[persona]}

${OUTPUT_FORMAT}

ALLOWED CATEGORIES: ${JSON.stringify(allowedCategories(stats))}

${language}

Here is the photo library summary (aggregated, anonymous statistics):
${JSON.stringify(stats, null, 2)}`;
}
