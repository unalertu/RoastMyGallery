// POST /api/deep-vision
// Body:    { appUserId: string, persona: "roast" | "analyst", locale?: string,
//            images: [base64-encoded JPEG, ...] }   (1–30 images)
// Returns: { summary: string,
//            segments: [{ photoIndexes: [int], text: string }],
//            generatedAt: string (ISO 8601) }
//
// The Pro tier: the consented photo batch is forwarded to Gemini's
// vision-capable model for photo-level commentary, then 5 CRD are deducted
// via RevenueCat — AFTER success, never before (with a read-only balance
// pre-check before the Gemini call so unaffordable requests fail fast).
//
// PRIVACY CONTRACT — images are processed and discarded:
// - Image data lives only in this invocation's memory: request body → Gemini
//   call → gone. Nothing is written to disk, a store, or any cache.
// - Image data is NEVER logged. Log sizes and counts only, never content.
// - Photo indexes (position in the uploaded array) are the only reference
//   shared with the client; the backend never sees asset identifiers.

import { buildDeepVisionPrompt, GEMINI_VISION_MODEL, PERSONA_PROMPTS } from "../lib/prompts.js";
import { checkAppSecret, clientIP, allowRequest, allowDailyRequest } from "../lib/guard.js";
import { spendCredits, getCreditBalance, CREDIT_COSTS } from "../lib/revenuecat.js";
import { claimCharge, RUN_ID_PATTERN } from "../lib/idempotency.js";

const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_VISION_MODEL}:generateContent`;

// Cost/abuse safeguards, enforced server-side regardless of what the client
// promises. The client downscales to ~1024px JPEG (~100–200 KB each), so real
// batches sit far below these ceilings; anything near them is not our app.
const MAX_IMAGES = 30;
const MAX_IMAGE_BASE64_CHARS = 450_000; // ≈ 330 KB binary per image
const MAX_TOTAL_BASE64_CHARS = 3_900_000; // keeps the body under Vercel's 4.5 MB cap

// Multi-image vision calls are slower than text; allow up to 60s.
export const config = { maxDuration: 60 };

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
    console.warn(`Rejected /api/deep-vision without valid app secret from ${clientIP(req)}.`);
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
  const { appUserId, persona, locale, images, runId } = req.body;

  // Read-only affordability pre-check (authoritative balance, unlike the
  // client's UX gate). Deduction still happens only after success below.
  // null = balance unknown (RC not configured / unreachable) → fail-open.
  const balance = await getCreditBalance(appUserId);
  if (balance !== null && balance < CREDIT_COSTS.deep_vision) {
    return res.status(402).json({
      error: "Not enough credits for a Deep Vision batch.",
      reason: "insufficient_credits",
    });
  }

  if (!allowDailyRequest()) {
    return res.status(429).json({
      error: "The daily insight budget is used up. Try again tomorrow.",
      reason: "daily_cap",
    });
  }

  const geminiRequest = {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": apiKey,
    },
    body: JSON.stringify({
      contents: [
        {
          role: "user",
          parts: [
            { text: buildDeepVisionPrompt({ persona, locale, imageCount: images.length }) },
            ...images.map((data) => ({
              inline_data: { mime_type: "image/jpeg", data },
            })),
          ],
        },
      ],
      generationConfig: {
        temperature: 0.9,
        maxOutputTokens: 2048,
        responseMimeType: "application/json",
      },
    }),
  };

  // One retry on transient upstream trouble (429/503 spikes are common on the
  // vision model). Worth it here more than on /api/insight: the user is mid-
  // flow on a paid, slow action, and the images are already in memory.
  let geminiResponse;
  for (let attempt = 0; ; attempt += 1) {
    try {
      geminiResponse = await fetch(GEMINI_URL, geminiRequest);
    } catch (error) {
      console.error("Gemini fetch failed:", error);
      return res.status(502).json({ error: "Could not reach the AI service." });
    }
    const transient = geminiResponse.status === 429 || geminiResponse.status === 503;
    if (!transient || attempt >= 1) break;
    console.warn(`Gemini ${geminiResponse.status} — retrying once after 2s.`);
    await new Promise((resolve) => setTimeout(resolve, 2000));
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

  const parsed = parseDeepVision(rawText, images.length);
  if (!parsed) {
    console.warn("Gemini deep-vision output was not valid JSON — not charging.");
    return res.status(502).json({ error: "The AI service returned an unusable result." });
  }

  // Deduct-after-success: a usable result exists, so charge 5 CRD. Never fail
  // the response on a deduction error — we can't un-run the analysis. A
  // failed/skipped deduction is logged for reconciliation (and is a no-op
  // until the RevenueCat env vars exist).
  //
  // Idempotency: a retry of a run whose response was lost after we already
  // charged carries the same runId — the atomic claim ensures that run only
  // ever deducts once. Only the claim marker (IDs, never content) is stored,
  // preserving this endpoint's nothing-persisted privacy contract.
  const claim = runId ? await claimCharge("deep-vision", appUserId, runId) : "unknown";
  if (claim === "duplicate") {
    console.warn(`Skipping deduction for ${appUserId}: deep-vision run ${runId} was already charged.`);
  } else {
    const spend = await spendCredits(appUserId, CREDIT_COSTS.deep_vision);
    if (!spend.ok) {
      console.error(
        `Credit deduction failed for ${appUserId} after a successful deep-vision batch (status ${spend.status}).`
      );
    }
  }

  return res.status(200).json({
    summary: parsed.summary,
    segments: parsed.segments,
    // Seconds precision on purpose: Swift's .iso8601 date decoding does not
    // accept fractional seconds.
    generatedAt: new Date().toISOString().split(".")[0] + "Z",
  });
}

// ---------------------------------------------------------------------------
// Model-output parsing

/**
 * Parses the deep-vision JSON contract from lib/prompts.js and sanitizes it:
 * bounded lengths, photo indexes coerced to real batch positions.
 * Returns { summary, segments } or null when unusable.
 */
function parseDeepVision(rawText, imageCount) {
  let data;
  try {
    // The mime type makes fences unlikely, but strip them defensively.
    data = JSON.parse(rawText.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, ""));
  } catch {
    return null;
  }
  if (!data || typeof data !== "object") return null;

  const summary = typeof data.summary === "string" ? data.summary.trim().slice(0, 200) : "";
  if (!summary) return null;

  if (!Array.isArray(data.segments) || data.segments.length === 0) return null;
  const segments = data.segments
    .slice(0, 12)
    .map((segment) => {
      const text = typeof segment?.text === "string" ? segment.text.trim().slice(0, 500) : "";
      const photoIndexes = Array.isArray(segment?.photoIndexes)
        ? [
            ...new Set(
              segment.photoIndexes.filter((i) => Number.isInteger(i) && i >= 0 && i < imageCount)
            ),
          ].slice(0, 6)
        : [];
      return { photoIndexes, text };
    })
    .filter((segment) => segment.text.length > 0);
  if (segments.length === 0) return null;

  return { summary, segments };
}

// ---------------------------------------------------------------------------
// Validation. Strict on purpose: images go straight into a paid Gemini call,
// so malformed or oversized payloads are rejected before costing anything.

const BODY_FIELDS = new Set(["appUserId", "persona", "locale", "images", "schemaVersion", "runId"]);

// Standard base64 (the iOS client uses Data.base64EncodedString()).
const BASE64_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/;

/** Returns an error message for invalid input, or null if valid. */
function validate(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return "Request body must be a JSON object.";
  }
  for (const key of Object.keys(body)) {
    if (!BODY_FIELDS.has(key)) return `Unknown field "${key}".`;
  }
  const { appUserId, persona, locale, images, schemaVersion } = body;

  // Required here (unlike /api/insight): Deep Vision is a paid-only action,
  // so a request with nobody to charge is always a mistake.
  if (!(typeof appUserId === "string" && appUserId.length > 0 && appUserId.length <= 256)) {
    return 'Field "appUserId" must be a non-empty string of at most 256 characters.';
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

  // Optional: client-generated run ID for charge idempotency (absent on
  // older clients). Tightly bounded — it becomes part of a storage key.
  if (body.runId !== undefined && !(typeof body.runId === "string" && RUN_ID_PATTERN.test(body.runId))) {
    return 'Field "runId" must be a short alphanumeric/dash string when present.';
  }

  if (!Array.isArray(images) || images.length === 0) {
    return 'Field "images" must be a non-empty array.';
  }
  if (images.length > MAX_IMAGES) {
    return `Field "images" may contain at most ${MAX_IMAGES} images.`;
  }
  let totalChars = 0;
  for (const [index, image] of images.entries()) {
    if (typeof image !== "string" || image.length === 0) {
      return `Field "images[${index}]" must be a non-empty base64 string.`;
    }
    if (image.length > MAX_IMAGE_BASE64_CHARS) {
      return `Field "images[${index}]" exceeds the per-image size limit.`;
    }
    if (image.length % 4 !== 0 || !BASE64_PATTERN.test(image)) {
      return `Field "images[${index}]" is not valid base64.`;
    }
    totalChars += image.length;
  }
  if (totalChars > MAX_TOTAL_BASE64_CHARS) {
    return "The image batch is too large. Send smaller images.";
  }
  return null;
}
