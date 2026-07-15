// POST /api/insight
// Body:    { stats: PhotoStats, persona: "roast" | "analyst", locale?: string }
// Returns: { insightText: string, generatedAt: string (ISO 8601) }
//
// The Gemini API key lives ONLY in the GEMINI_API_KEY environment variable
// (Vercel dashboard / `vercel env add`). It is never sent by the client.

import { buildPrompt, allowedCategories, GEMINI_MODEL, PERSONA_PROMPTS } from "../lib/prompts.js";
import { checkAppSecret, clientIP, allowRequest, allowDailyRequest } from "../lib/guard.js";
import { spendCredits, CREDIT_COSTS } from "../lib/revenuecat.js";

const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

/**
 * Typical PhotoStats payloads are 1–3 KB; a Pro fullHistory scan of a
 * decades-old library (one categoriesByMonth entry per month) can reach a few
 * tens of KB. Anything near this limit is not our app.
 */
const MAX_STATS_JSON_BYTES = 64_000;

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed. Use POST." });
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    console.error("GEMINI_API_KEY is not set");
    return res.status(500).json({ error: "Server is not configured." });
  }

  // Cheap gates first: none of these may consume a Gemini call.
  const secretError = checkAppSecret(req);
  if (secretError) {
    console.warn(`Rejected request without valid app secret from ${clientIP(req)}.`);
    return res.status(401).json({ error: secretError });
  }

  if (!allowRequest(clientIP(req))) {
    return res.status(429).json({
      error: "Too many requests. Try again in a minute.",
      reason: "rate_limited",
    });
  }

  const validationError = validate(req.body);
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }
  const { stats, persona, locale, appUserId } = req.body;

  if (!allowDailyRequest()) {
    return res.status(429).json({
      error: "The daily insight budget is used up. Try again tomorrow.",
      reason: "daily_cap",
    });
  }

  let geminiResponse;
  try {
    geminiResponse = await fetch(GEMINI_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [{ text: buildPrompt({ stats, persona, locale }) }],
          },
        ],
        generationConfig: {
          temperature: 0.9,
          maxOutputTokens: 1024,
          responseMimeType: "application/json",
        },
      }),
    });
  } catch (error) {
    console.error("Gemini fetch failed:", error);
    return res.status(502).json({ error: "Could not reach the AI service." });
  }

  if (geminiResponse.status === 429) {
    return res
      .status(429)
      .json({ error: "The AI service is rate-limited right now. Try again shortly." });
  }
  if (!geminiResponse.ok) {
    const detail = await geminiResponse.text().catch(() => "");
    console.error(`Gemini error ${geminiResponse.status}:`, detail.slice(0, 500));
    return res.status(502).json({ error: "The AI service returned an error." });
  }

  let rawText;
  try {
    const data = await geminiResponse.json();
    rawText = (data.candidates?.[0]?.content?.parts ?? [])
      .map((part) => part.text ?? "")
      .join("")
      .trim();
  } catch (error) {
    console.error("Failed to parse Gemini response:", error);
  }

  if (!rawText) {
    // Covers safety blocks, empty candidates, and parse failures.
    return res.status(502).json({ error: "The AI service returned no usable text." });
  }

  const parsed = parseSegmented(rawText, allowedCategories(stats));
  if (!parsed) {
    console.warn("Gemini output was not valid segmented JSON — serving legacy plain text.");
  }

  // `insightText` (title line, blank line, narrative) is kept for clients
  // that predate `segments`; `shareLine`/`segments` are additive.
  const { insightText, shareLine, segments } = parsed ?? legacyFields(rawText);

  // Deduct-after-success: the insight generated, so charge 1 credit. We do this
  // AFTER a usable result exists, and never fail the response on a deduction
  // error — we can't un-generate the insight. A failed/ skipped deduction is
  // logged for reconciliation (and is a no-op until RevenueCat env vars exist).
  if (appUserId) {
    const spend = await spendCredits(appUserId, CREDIT_COSTS.analysis);
    if (!spend.ok) {
      console.error(
        `Credit deduction failed for ${appUserId} after a successful insight (status ${spend.status}).`
      );
    }
  }

  return res.status(200).json({
    insightText,
    shareLine,
    segments,
    // Seconds precision on purpose: Swift's .iso8601 date decoding does not
    // accept fractional seconds.
    generatedAt: new Date().toISOString().split(".")[0] + "Z",
  });
}

// ---------------------------------------------------------------------------
// Model-output parsing

/**
 * Parses the segmented JSON contract from lib/prompts.js and sanitizes it:
 * bounded lengths, categories coerced to null unless in the allowed list.
 * Returns { insightText, shareLine, segments } or null when unusable.
 */
function parseSegmented(rawText, allowed) {
  let data;
  try {
    // The mime type makes fences unlikely, but strip them defensively.
    data = JSON.parse(rawText.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, ""));
  } catch {
    return null;
  }
  if (!data || typeof data !== "object") return null;

  const title = typeof data.title === "string" ? data.title.trim().slice(0, 80) : "";
  if (!title) return null;

  if (!Array.isArray(data.segments) || data.segments.length === 0) return null;
  const allowedSet = new Set(allowed);
  const segments = data.segments
    .slice(0, 8)
    .map((segment) => {
      const text = typeof segment?.text === "string" ? segment.text.trim().slice(0, 500) : "";
      const category =
        typeof segment?.category === "string" && allowedSet.has(segment.category)
          ? segment.category
          : null;
      return { text, category };
    })
    .filter((segment) => segment.text.length > 0);
  if (segments.length === 0) return null;

  const shareLine =
    typeof data.shareLine === "string" && data.shareLine.trim()
      ? data.shareLine.trim().slice(0, 140)
      : null;

  return {
    insightText: `${title}\n\n${segments.map((s) => s.text).join("\n\n")}`,
    shareLine,
    segments,
  };
}

/** Pre-segments behavior for non-JSON model output: extract "SHARE: …". */
function legacyFields(rawText) {
  let insightText = rawText;
  let shareLine = null;
  const shareMatch = insightText.match(/^SHARE:\s*(.+)$/im);
  if (shareMatch) {
    shareLine = shareMatch[1].trim();
    insightText = insightText.replace(/^SHARE:.*$/im, "").trim();
  }
  return { insightText, shareLine, segments: null };
}

// ---------------------------------------------------------------------------
// Validation. Strict on purpose: `stats` is serialized verbatim into the LLM
// prompt, so anything not matching the PhotoStats schema (see
// RoastMyGallery/Models/PhotoStats.swift) is rejected before it can waste a
// Gemini call or stuff junk into the prompt.

/** A count no photo library can plausibly exceed. */
const MAX_COUNT = 10_000_000;

const isCount = (v) => Number.isInteger(v) && v >= 0 && v <= MAX_COUNT;
const isShortString = (v, max) => typeof v === "string" && v.length > 0 && v.length <= max;

/** Object whose every value passes `check`, with bounded size and key length. */
function isBoundedRecord(v, maxKeys, check) {
  if (!v || typeof v !== "object" || Array.isArray(v)) return false;
  const keys = Object.keys(v);
  if (keys.length > maxKeys) return false;
  return keys.every((k) => k.length <= 40 && check(v[k]));
}

const isCategoryCount = (v) =>
  v && typeof v === "object" && !Array.isArray(v) &&
  Object.keys(v).length === 2 &&
  isShortString(v.category, 100) && isCount(v.count);

/** field name → predicate. Every field is required; unknown fields rejected. */
const STATS_SCHEMA = {
  generatedAt: (v) => isShortString(v, 40),
  scope: (v) => v === "lastThreeMonths" || v === "fullHistory",
  totalPhotos: isCount,
  analyzedPhotos: isCount,
  selfieCount: isCount,
  screenshotCount: isCount,
  favoriteCount: isCount,
  faceCountBuckets: (v) => isBoundedRecord(v, 10, isCount),
  topCategories: (v) => Array.isArray(v) && v.length <= 50 && v.every(isCategoryCount),
  // One key per month of library history — 600 ≈ 50 years, ample for
  // fullHistory scans while still bounding abuse.
  categoriesByMonth: (v) =>
    isBoundedRecord(v, 600, (m) => Array.isArray(m) && m.length <= 50 && m.every(isCategoryCount)),
  photosByMonth: (v) => isBoundedRecord(v, 600, isCount),
  photosByHourOfDay: (v) => Array.isArray(v) && v.length === 24 && v.every(isCount),
  topLocationClusters: (v) =>
    Array.isArray(v) && v.length <= 20 &&
    v.every(
      (c) =>
        c && typeof c === "object" && !Array.isArray(c) &&
        Object.keys(c).length === 2 &&
        typeof c.share === "number" && c.share >= 0 && c.share <= 1 &&
        isShortString(c.label, 40)
    ),
  animalCounts: (v) => isBoundedRecord(v, 100, isCount),
};

const BODY_FIELDS = new Set(["stats", "persona", "locale", "schemaVersion", "appUserId"]);

/** Returns an error message for invalid input, or null if valid. */
function validate(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return "Request body must be a JSON object.";
  }
  for (const key of Object.keys(body)) {
    if (!BODY_FIELDS.has(key)) return `Unknown field "${key}".`;
  }
  const { stats, persona, locale, schemaVersion, appUserId } = body;

  // Optional: RevenueCat App User ID for the post-success credit deduction.
  if (appUserId !== undefined && !(typeof appUserId === "string" && appUserId.length > 0 && appUserId.length <= 256)) {
    return 'Field "appUserId" must be a non-empty string of at most 256 characters when present.';
  }

  if (!persona || !Object.hasOwn(PERSONA_PROMPTS, persona)) {
    return `Field "persona" must be one of: ${Object.keys(PERSONA_PROMPTS).join(", ")}.`;
  }
  if (locale !== undefined && !(typeof locale === "string" && locale.length <= 32)) {
    return 'Field "locale" must be a string of at most 32 characters when present.';
  }
  if (schemaVersion !== undefined && schemaVersion !== 1) {
    return 'Field "schemaVersion" must be 1 when present.';
  }
  if (!stats || typeof stats !== "object" || Array.isArray(stats)) {
    return 'Field "stats" must be an object.';
  }
  if (JSON.stringify(stats).length > MAX_STATS_JSON_BYTES) {
    return 'Field "stats" is too large.';
  }
  for (const key of Object.keys(stats)) {
    if (!Object.hasOwn(STATS_SCHEMA, key)) return `Unknown field "stats.${key}".`;
  }
  for (const [key, check] of Object.entries(STATS_SCHEMA)) {
    if (!check(stats[key])) return `Field "stats.${key}" is missing or invalid.`;
  }
  return null;
}
