// POST /api/insight
// Body:    { stats: PhotoStats, persona: "roast" | "analyst", locale?: string,
//            depth?: "standard" | "deep" }
// Returns: { insightText: string, generatedAt: string (ISO 8601) }
//
// depth "deep" = the 5-credit tier: stronger model, 12–16 segments, ~700-word
// budget. Absent/"standard" = the classic 1-credit run.
//
// The Gemini API key lives ONLY in the GEMINI_API_KEY environment variable
// (Vercel dashboard / `vercel env add`). It is never sent by the client.

import {
  buildPrompt,
  allowedCategories,
  GEMINI_MODEL,
  GEMINI_DEEP_MODEL,
  PERSONA_PROMPTS,
} from "../lib/prompts.js";
import { checkAppSecret, clientIP, allowRequest, allowDailyRequest } from "../lib/guard.js";
import { spendCredits, getCreditBalance, CREDIT_COSTS } from "../lib/revenuecat.js";
import { claimCharge, RUN_ID_PATTERN } from "../lib/idempotency.js";

const geminiURL = (model) =>
  `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;

/**
 * Typical PhotoStats payloads are 1–3 KB; a Pro fullHistory scan of a
 * decades-old library (one categoriesByMonth entry per month) can reach a few
 * tens of KB. Anything near this limit is not our app.
 */
const MAX_STATS_JSON_BYTES = 64_000;

// Note: this function's maxDuration (60s, for deep runs) is set in vercel.json
// alongside the other slow endpoints — not via an inline `config` export.

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
  const { stats, persona, locale, appUserId, variationSeed, runId } = req.body;
  const depth = req.body.depth === "deep" ? "deep" : "standard";

  // Deep runs cost 5 CRD: worth a read-only affordability pre-check against
  // the authoritative balance before burning the (pricier) Gemini call.
  // null = balance unknown (RC not configured / unreachable) → fail-open.
  // Deduction still happens only after success below.
  if (depth === "deep" && appUserId) {
    const balance = await getCreditBalance(appUserId);
    if (balance !== null && balance < CREDIT_COSTS.deep_analysis) {
      return res.status(402).json({
        error: "Not enough credits for a deep analysis.",
        reason: "insufficient_credits",
      });
    }
  }

  if (!allowDailyRequest()) {
    return res.status(429).json({
      error: "The daily insight budget is used up. Try again tomorrow.",
      reason: "daily_cap",
    });
  }

  const prompt = buildPrompt({ stats, persona, locale, variationSeed: variationSeed ?? 0, depth });
  // Deep needs real headroom: gemini-3.x flash is a "thinking" model that
  // spends output tokens on hidden reasoning BEFORE the JSON, and a 12–16
  // segment / ~700-word story on top of that blew past the old 3072 budget and
  // truncated the JSON mid-object. Two guards: give deep a large budget, and
  // disable thinking for this pure structured-writing task (thinkingBudget: 0)
  // so the whole budget goes to output — verified accepted by both the deep
  // and fallback models on v1beta, and it cuts latency too.
  const maxOutputTokens = depth === "deep" ? 8192 : 1024;
  const generationConfig = {
    // High so regenerations diverge in wording; the rotating lens + spotlight
    // (see buildPrompt) drive the structural variety.
    temperature: 1.0,
    maxOutputTokens,
    responseMimeType: "application/json",
  };
  if (depth === "deep") {
    generationConfig.thinkingConfig = { thinkingBudget: 0 };
  }

  // Deep prefers the stronger model, but that model (gemini-3.5-flash) is
  // frequently capacity-limited (503 "high demand"). Rather than fail a paid
  // deep run — or blow the function's time budget retrying a slow, overloaded
  // model — try it ONCE and fall straight to the fast, reliable standard model
  // on any error. The deep VALUE is mostly the longer prompt, wider category
  // set, and captions, all of which still apply. Standard has only its one
  // model, so it gets a single transient retry instead of a fallback.
  const models = depth === "deep" ? [GEMINI_DEEP_MODEL, GEMINI_MODEL] : [GEMINI_MODEL];
  const retryLast = depth !== "deep"; // no fallback available → one retry

  const callModel = async (model) => {
    try {
      return await fetch(geminiURL(model), {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: prompt }] }],
          generationConfig,
        }),
      });
    } catch (error) {
      console.error(`Gemini fetch failed (${model}):`, error);
      return null;
    }
  };

  let geminiResponse = null;
  let lastStatus = 0;
  for (let i = 0; i < models.length; i += 1) {
    const model = models[i];
    geminiResponse = await callModel(model);
    if (geminiResponse?.ok) break;
    lastStatus = geminiResponse?.status ?? 0;

    if (geminiResponse) {
      const detail = await geminiResponse.text().catch(() => "");
      console.warn(`Gemini ${geminiResponse.status} on ${model}: ${detail.slice(0, 200)}`);
    }

    // One retry on the last model only when there's no other model to try.
    const isLast = i === models.length - 1;
    if (isLast && retryLast && (lastStatus === 429 || lastStatus === 503)) {
      await new Promise((resolve) => setTimeout(resolve, 1500));
      geminiResponse = await callModel(model);
      if (geminiResponse?.ok) break;
      lastStatus = geminiResponse?.status ?? lastStatus;
    }
  }

  if (!geminiResponse) {
    return res.status(502).json({ error: "Could not reach the AI service." });
  }

  if (geminiResponse.status === 429) {
    return res
      .status(429)
      .json({ error: "The AI service is rate-limited right now. Try again shortly." });
  }
  if (!geminiResponse.ok) {
    const detail = await geminiResponse.text().catch(() => "");
    console.error(`Gemini error ${geminiResponse.status} (last status ${lastStatus}):`, detail.slice(0, 500));
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

  const parsed = parseSegmented(rawText, allowedCategories(stats, depth), depth);
  if (!parsed) {
    console.warn("Gemini output was not valid segmented JSON — serving legacy plain text.");
  }

  // `insightText` (title line, blank line, narrative) is kept for clients
  // that predate `segments`; `shareLine`/`segments` are additive.
  const { insightText, shareLine, segments } = parsed ?? legacyFields(rawText);

  // Deduct-after-success: the insight generated, so charge for it (1 CRD
  // standard, 5 CRD deep). We do this AFTER a usable result exists, and never
  // fail the response on a deduction error — we can't un-generate the insight.
  // A failed/skipped deduction is logged for reconciliation (and is a no-op
  // until RevenueCat env vars exist).
  if (appUserId) {
    // Idempotency: a retry of a run whose response was lost after we already
    // charged (suspended client, dropped connection) carries the same runId —
    // claim the charge atomically so that run can only ever deduct once. No
    // runId (older clients) or no store configured = charge as before.
    let claim = "unknown";
    if (runId) {
      claim = await claimCharge("insight", appUserId, runId);
    }
    if (claim === "duplicate") {
      console.warn(`Skipping deduction for ${appUserId}: run ${runId} was already charged.`);
    } else {
      const cost = depth === "deep" ? CREDIT_COSTS.deep_analysis : CREDIT_COSTS.analysis;
      const spend = await spendCredits(appUserId, cost);
      if (!spend.ok) {
        console.error(
          `Credit deduction failed for ${appUserId} after a successful ${depth} insight (status ${spend.status}).`
        );
      }
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
 *
 * Falls back to `salvageTruncatedJSON` when a strict parse fails, so a story
 * that got cut off mid-object (e.g. a very long library hitting the token
 * limit despite the raised budget) still yields its complete leading segments
 * instead of collapsing to raw-JSON legacy text.
 */
function parseSegmented(rawText, allowed, depth = "standard") {
  const cleaned = rawText.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
  let data;
  try {
    data = JSON.parse(cleaned);
  } catch {
    data = salvageTruncatedJSON(cleaned);
  }
  if (!data || typeof data !== "object") return null;

  const title = typeof data.title === "string" ? data.title.trim().slice(0, 80) : "";
  if (!title) return null;

  if (!Array.isArray(data.segments) || data.segments.length === 0) return null;
  const allowedSet = new Set(allowed);
  const segments = data.segments
    .slice(0, depth === "deep" ? 18 : 8)
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

/**
 * Best-effort recovery of a truncated segmented-JSON payload: pulls the title
 * and every COMPLETE `{ "text": ..., "category": ... }` object out of a string
 * whose closing braces never arrived. A half-written trailing segment simply
 * won't match the "complete object" pattern, so it's dropped. Returns a shape
 * `parseSegmented` can sanitize, or null when not even a title + one segment
 * survive. Only invoked after a strict JSON.parse fails.
 */
function salvageTruncatedJSON(text) {
  // Decode a JSON string body (with its escapes) captured without quotes.
  const decode = (inner) => {
    try {
      return JSON.parse(`"${inner}"`);
    } catch {
      return null;
    }
  };

  const titleMatch = text.match(/"title"\s*:\s*"((?:[^"\\]|\\.)*)"/);
  const title = titleMatch ? decode(titleMatch[1]) : null;
  if (!title) return null;

  const segmentRe =
    /\{\s*"text"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,\s*"category"\s*:\s*(null|"(?:[^"\\]|\\.)*")\s*\}/g;
  const segments = [];
  let match;
  while ((match = segmentRe.exec(text)) !== null) {
    const segText = decode(match[1]);
    if (!segText) continue;
    const category = match[2] === "null" ? null : decode(match[2].slice(1, -1));
    segments.push({ text: segText, category });
  }
  if (segments.length === 0) return null;

  const shareMatch = text.match(/"shareLine"\s*:\s*"((?:[^"\\]|\\.)*)"/);
  const shareLine = shareMatch ? decode(shareMatch[1]) : undefined;

  return { title, segments, shareLine };
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

/**
 * `AnalysisScope` (see RoastMyGallery/Models/AnalysisScope.swift) encodes as
 * a keyed object: `{kind:"fullHistory"}`, `{kind:"lastThreeMonths"}`,
 * `{kind:"dateRange", start, end, label}` (ISO 8601 date strings), or
 * `{kind:"album", identifier, name}`. Legacy plain strings ("fullHistory" /
 * "lastThreeMonths") are still accepted for older app builds still in the wild.
 */
const isValidScope = (v) => {
  if (v === "lastThreeMonths" || v === "fullHistory") return true;
  if (!v || typeof v !== "object" || Array.isArray(v)) return false;
  const keys = Object.keys(v);
  switch (v.kind) {
    case "fullHistory":
    case "lastThreeMonths":
      return keys.length === 1;
    case "dateRange":
      return keys.length === 4 &&
        isShortString(v.start, 40) && isShortString(v.end, 40) && isShortString(v.label, 80);
    case "album":
      return keys.length === 3 &&
        isShortString(v.identifier, 200) && isShortString(v.name, 200);
    default:
      return false;
  }
};

/** field name → predicate. Every field is required; unknown fields rejected. */
const STATS_SCHEMA = {
  generatedAt: (v) => isShortString(v, 40),
  scope: isValidScope,
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

const BODY_FIELDS = new Set([
  "stats",
  "persona",
  "locale",
  "schemaVersion",
  "appUserId",
  "variationSeed",
  "depth",
  "runId",
]);

/** Returns an error message for invalid input, or null if valid. */
function validate(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return "Request body must be a JSON object.";
  }
  for (const key of Object.keys(body)) {
    if (!BODY_FIELDS.has(key)) return `Unknown field "${key}".`;
  }
  const { stats, persona, locale, schemaVersion, appUserId, variationSeed } = body;

  // Optional: RevenueCat App User ID for the post-success credit deduction.
  if (appUserId !== undefined && !(typeof appUserId === "string" && appUserId.length > 0 && appUserId.length <= 256)) {
    return 'Field "appUserId" must be a non-empty string of at most 256 characters when present.';
  }

  // Optional: advancing per-regeneration counter (0 for a first analysis).
  // Bounded so it can't be used to smuggle a huge number into the prompt.
  if (variationSeed !== undefined &&
      !(Number.isInteger(variationSeed) && variationSeed >= 0 && variationSeed <= 100000)) {
    return 'Field "variationSeed" must be a non-negative integer when present.';
  }

  // Optional: analysis tier. Absent (older clients) means standard.
  if (body.depth !== undefined && body.depth !== "standard" && body.depth !== "deep") {
    return 'Field "depth" must be "standard" or "deep" when present.';
  }

  // Optional: client-generated run ID for charge idempotency (absent on
  // older clients). Tightly bounded — it becomes part of a storage key.
  if (body.runId !== undefined && !(typeof body.runId === "string" && RUN_ID_PATTERN.test(body.runId))) {
    return 'Field "runId" must be a short alphanumeric/dash string when present.';
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
