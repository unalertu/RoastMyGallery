// POST /api/photo-captions
// Body:    { appUserId: string, persona: "roast" | "analyst", locale?: string,
//            images: [base64-encoded JPEG, ...],            (1–16 images)
//            contexts: [{ text: string, category?: string|null }, ...] }
//            (contexts is parallel to images: the story beat each photo
//             illustrates on the results screen)
// Returns: { captions: [string], generatedAt: string (ISO 8601) }
//
// The deep-analysis captioning pass: one short persona-voiced caption per
// photo shown on the results screen. NO credit deduction here — the deep
// run's 5 CRD were already charged by /api/insight (depth "deep"); this call
// is part of what they bought. It stays behind the app secret + rate limits
// so it can't be farmed as a free vision endpoint.
//
// PRIVACY CONTRACT — identical to /api/deep-vision:
// - Image data lives only in this invocation's memory: request body → Gemini
//   call → gone. Nothing is written to disk, a store, or any cache.
// - Image data is NEVER logged. Log sizes and counts only, never content.
// - Batch order is the only reference shared with the client; the backend
//   never sees asset identifiers.

import { buildPhotoCaptionsPrompt, GEMINI_VISION_MODEL, PERSONA_PROMPTS } from "../lib/prompts.js";
import { checkAppSecret, clientIP, allowRequest, allowDailyRequest } from "../lib/guard.js";

const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_VISION_MODEL}:generateContent`;

// Cost/abuse safeguards, enforced server-side regardless of what the client
// promises. Deep stories run 12–16 segments with at most one captioned photo
// each; the same per-image ceilings as deep-vision keep the body well under
// Vercel's 4.5 MB cap.
const MAX_IMAGES = 16;
const MAX_IMAGE_BASE64_CHARS = 450_000; // ≈ 330 KB binary per image
const MAX_TOTAL_BASE64_CHARS = 3_900_000;
const MAX_CONTEXT_TEXT_CHARS = 500; // segment texts are already ≤500 (insight.js)
const MAX_CAPTION_CHARS = 160;

// Multi-image vision calls are slower than text; the 60s maxDuration is set
// in vercel.json alongside the other slow endpoints.

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
    console.warn(`Rejected /api/photo-captions without valid app secret from ${clientIP(req)}.`);
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
  const { persona, locale, images, contexts } = req.body;

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
            { text: buildPhotoCaptionsPrompt({ persona, locale, contexts: sanitizedContexts(contexts) }) },
            ...images.map((data) => ({
              inline_data: { mime_type: "image/jpeg", data },
            })),
          ],
        },
      ],
      generationConfig: {
        temperature: 0.9,
        maxOutputTokens: 1024,
        responseMimeType: "application/json",
      },
    }),
  };

  // One retry on transient upstream trouble, same as deep-vision: the user is
  // mid-flow on a paid run and the images are already in memory.
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

  const captions = parseCaptions(rawText, images.length);
  if (!captions) {
    console.warn("Gemini photo-captions output was not valid JSON.");
    return res.status(502).json({ error: "The AI service returned an unusable result." });
  }

  return res.status(200).json({
    captions,
    // Seconds precision on purpose: Swift's .iso8601 date decoding does not
    // accept fractional seconds.
    generatedAt: new Date().toISOString().split(".")[0] + "Z",
  });
}

// ---------------------------------------------------------------------------
// Model-output parsing

/**
 * Parses `{ captions: [string] }` and sanitizes it: bounded lengths, trailing
 * extras dropped, order preserved. The array may come back SHORTER than the
 * batch (the client zips by index, so missing tails just mean uncaptioned
 * cards). Returns the captions array or null when unusable.
 */
function parseCaptions(rawText, imageCount) {
  let data;
  try {
    // The mime type makes fences unlikely, but strip them defensively.
    data = JSON.parse(rawText.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, ""));
  } catch {
    return null;
  }
  if (!data || typeof data !== "object" || !Array.isArray(data.captions)) return null;

  const captions = data.captions
    .slice(0, imageCount)
    .map((caption) => (typeof caption === "string" ? caption.trim().slice(0, MAX_CAPTION_CHARS) : ""));
  if (!captions.some((caption) => caption.length > 0)) return null;

  return captions;
}

// ---------------------------------------------------------------------------
// Validation. Strict on purpose: images go straight into a paid Gemini call,
// so malformed or oversized payloads are rejected before costing anything.

const BODY_FIELDS = new Set(["appUserId", "persona", "locale", "images", "contexts", "schemaVersion"]);

// Standard base64 (the iOS client uses Data.base64EncodedString()).
const BASE64_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/;

/** Bound context texts defensively before they're interpolated into the prompt. */
function sanitizedContexts(contexts) {
  return contexts.map((context) => ({
    text: context.text.slice(0, MAX_CONTEXT_TEXT_CHARS).replace(/"/g, "'"),
    category: typeof context.category === "string" ? context.category.slice(0, 60) : null,
  }));
}

/** Returns an error message for invalid input, or null if valid. */
function validate(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return "Request body must be a JSON object.";
  }
  for (const key of Object.keys(body)) {
    if (!BODY_FIELDS.has(key)) return `Unknown field "${key}".`;
  }
  const { appUserId, persona, locale, images, contexts, schemaVersion } = body;

  // Required even though nothing is charged here: caption batches only ever
  // follow a paid deep insight, so an anonymous request is always a mistake.
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

  if (!Array.isArray(contexts) || contexts.length !== images.length) {
    return 'Field "contexts" must be an array parallel to "images".';
  }
  for (const [index, context] of contexts.entries()) {
    if (!context || typeof context !== "object" || Array.isArray(context)) {
      return `Field "contexts[${index}]" must be an object.`;
    }
    for (const key of Object.keys(context)) {
      if (key !== "text" && key !== "category") return `Unknown field "contexts[${index}].${key}".`;
    }
    if (!(typeof context.text === "string" && context.text.length > 0 && context.text.length <= 1000)) {
      return `Field "contexts[${index}].text" must be a non-empty string of at most 1000 characters.`;
    }
    if (
      context.category !== undefined &&
      context.category !== null &&
      !(typeof context.category === "string" && context.category.length <= 100)
    ) {
      return `Field "contexts[${index}].category" must be a short string or null when present.`;
    }
  }
  return null;
}
