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
- 5 to 7 segments, total under 260 words. Plain text only — no markdown, no emoji.
- Even for a small or single-month library, write the full 5-7 beats: slow down and
  find several distinct things to say rather than stopping after two or three.
- Together they must read as one flowing piece in the persona's voice.
- Set "category" ONLY to a value from the ALLOWED CATEGORIES list below, and only when
  that segment is clearly about that one subject. Otherwise use null. Never invent categories.
Ground every observation in the numbers provided. Never invent stats that aren't in the data.
The stats are anonymous aggregates; you know nothing else about this person.`;

/**
 * Beats don't have to be about a subject/category. The stats carry several
 * behavioral signals that make great, distinct narrative beats and keep a
 * short (e.g. single-month) library from sounding thin. These beats use
 * `category: null` (they have no matching photo). Kept as one constant so it's
 * easy to tune the voice without touching prompt assembly.
 */
const SIGNALS_GUIDE = `Don't only talk about subjects. The stats also describe HOW this person shoots — mine these for beats too, and use "category": null for any beat built from them:
- WHEN: photosByHourOfDay (24 buckets, index = hour of day). Night owl, dawn shooter, lunchtime-only?
- WHO's in frame: faceCountBuckets ("0"/"1"/"2+"). Solo self-portraits, group-photo person, or faceless scenes?
- WHAT THEY KEEP: favoriteCount vs analyzedPhotos, and screenshotCount. Ruthless curator or favorites everything? Screenshot hoarder?
- WHERE: topLocationClusters shares. Homebody orbiting one area vs scattered wanderer.
- OVER TIME: photosByMonth and categoriesByMonth. Phases that flared up and faded.
Aim to spread the beats across several of these lenses instead of stacking them all on the top one or two categories.`;

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

/**
 * Narrative "lenses" — which angle to lead with. Rotated by variationSeed so
 * that regenerating the SAME stats opens on a different facet each time
 * instead of always leading with the biggest category.
 */
const LENSES = [
  "Lead with the SUBJECTS they shoot most — what they keep pointing the camera at.",
  "Lead with TIMING — when in the day (photosByHourOfDay) and across months they shoot, and what that rhythm says.",
  "Lead with WHERE — how their locations cluster (topLocationClusters): rooted in one place vs roaming.",
  "Lead with WHAT THEY KEEP — favorites vs everything, and the screenshot pile: choosy curator or hoarder?",
  "Lead with WHO's in frame (faceCountBuckets) — solo self-portraits, group-photo person, or faceless scenes.",
];

/**
 * Small deterministic PRNG (mulberry32) so a given variationSeed always yields
 * the same lens + spotlight — reproducible and testable, no global state.
 */
function mulberry32(seed) {
  let a = (seed >>> 0) || 1;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Weighted sample without replacement — pick up to `count` categories favoring
 * the ones they shoot most, but not deterministically the top N, so different
 * seeds spotlight different real subjects.
 */
function weightedSample(entries, count, rand) {
  const pool = entries.map((e) => ({ ...e }));
  const picked = [];
  while (picked.length < count && pool.length) {
    const total = pool.reduce((sum, e) => sum + e.weight, 0);
    if (total <= 0) break;
    let r = rand() * total;
    let i = 0;
    while (i < pool.length - 1 && r >= pool[i].weight) {
      r -= pool[i].weight;
      i++;
    }
    picked.push(pool[i].value);
    pool.splice(i, 1);
  }
  return picked;
}

/**
 * The per-run variation block: a rotating lens plus 1–2 weight-sampled
 * spotlight subjects. `variationSeed` advances each time the same stats are
 * regenerated (0 = first analysis) — see ScanViewModel.regenerate.
 */
function variationBlock({ stats, variationSeed }) {
  const rand = mulberry32(variationSeed + 1);
  const lens = LENSES[variationSeed % LENSES.length];

  const catEntries = (stats.topCategories || [])
    .filter((c) => c && typeof c.category === "string" && c.count > 0)
    .map((c) => ({ value: c.category, weight: c.count }));
  const spotlight = weightedSample(catEntries, 2, rand);
  const spotlightLine = spotlight.length
    ? `- Make sure at least one beat is about: ${spotlight.join(", ")}. Only if the numbers honestly support it — never invent.`
    : "";

  return `VARIATION — make this run read differently from any previous take on the same library:
- ${lens}
${spotlightLine}`;
}

export function buildPrompt({ stats, persona, locale, variationSeed = 0 }) {
  const language = locale
    ? `Write in the natural language implied by the locale "${locale}" (e.g. en_US → English, tr_TR → Turkish). JSON keys and category values stay in English exactly as given.`
    : "Write in English.";

  return `${PERSONA_PROMPTS[persona]}

${variationBlock({ stats, variationSeed })}

${OUTPUT_FORMAT}

ALLOWED CATEGORIES: ${JSON.stringify(allowedCategories(stats))}

${SIGNALS_GUIDE}

${language}

Here is the photo library summary (aggregated, anonymous statistics):
${JSON.stringify(stats, null, 2)}`;
}
