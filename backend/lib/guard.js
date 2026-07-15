// Abuse-protection helpers for api/insight.js: app-secret check, per-IP rate
// limiting, and a daily request ceiling.
//
// The rate limiter and daily counter are IN-MEMORY. On Vercel that means:
// per warm function instance, reset on every cold start, not shared across
// concurrent instances or regions. For a single-region, low-traffic hobby
// function this is fine — a warm instance handles the common case, and the
// worst case is limits being more permissive than configured, never stricter.
// If traffic grows, swap these for Upstash Redis (@upstash/ratelimit) without
// touching the handler; the function signatures are designed for that.

import { timingSafeEqual } from "node:crypto";

// ---------------------------------------------------------------------------
// App-secret gate

/**
 * Compares the client's X-App-Secret header against APP_SHARED_SECRET.
 *
 * Fail-open by design when the env var is not set: deploying this code before
 * the env var exists must not break the live app. Enforcement starts the
 * moment APP_SHARED_SECRET is configured in Vercel.
 *
 * Returns null when the request may proceed, or an error string when it must
 * be rejected with 401.
 */
export function checkAppSecret(req) {
  const expected = process.env.APP_SHARED_SECRET;
  if (!expected) {
    console.warn("APP_SHARED_SECRET is not set — app-secret check is DISABLED.");
    return null;
  }

  const provided = req.headers["x-app-secret"];
  if (typeof provided !== "string" || provided.length === 0) {
    return "Missing app credentials.";
  }

  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  // timingSafeEqual throws on length mismatch; unequal length = unequal secret.
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    return "Invalid app credentials.";
  }
  return null;
}

// ---------------------------------------------------------------------------
// Per-IP rate limiting (fixed one-minute window)

const RATE_LIMIT_PER_MINUTE = 10;
const WINDOW_MS = 60_000;

/** ip → { windowStart: number, count: number } */
const ipWindows = new Map();

/** Best-effort client IP behind Vercel's proxy. */
export function clientIP(req) {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.length > 0) {
    return forwarded.split(",")[0].trim();
  }
  return req.socket?.remoteAddress ?? "unknown";
}

/**
 * Returns true when this request is within the per-IP limit, false when it
 * should be rejected with 429.
 */
export function allowRequest(ip, now = Date.now()) {
  // Opportunistic cleanup so the map can't grow unboundedly in a long-lived
  // warm instance.
  if (ipWindows.size > 10_000) {
    for (const [key, entry] of ipWindows) {
      if (now - entry.windowStart >= WINDOW_MS) ipWindows.delete(key);
    }
  }

  const entry = ipWindows.get(ip);
  if (!entry || now - entry.windowStart >= WINDOW_MS) {
    ipWindows.set(ip, { windowStart: now, count: 1 });
    return true;
  }
  entry.count += 1;
  if (entry.count > RATE_LIMIT_PER_MINUTE) {
    if (entry.count === RATE_LIMIT_PER_MINUTE + 1) {
      console.warn(`Rate limit hit for IP ${ip} (${RATE_LIMIT_PER_MINUTE}/min).`);
    }
    return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Daily ceiling (protects the Gemini free-tier quota)

/**
 * Hard stop well under the Gemini free tier's requests-per-day limit
 * (~1,000/day for flash-lite class models; 800 ≈ 80%). Override with the
 * DAILY_REQUEST_CAP env var.
 */
const DEFAULT_DAILY_CAP = 800;

let dailyKey = "";
let dailyCount = 0;

/**
 * Counts one prospective Gemini call against today's (UTC) budget.
 * Returns true when the call may proceed, false once the ceiling is hit.
 */
export function allowDailyRequest(now = new Date()) {
  const cap = Number(process.env.DAILY_REQUEST_CAP) || DEFAULT_DAILY_CAP;
  const key = now.toISOString().slice(0, 10); // UTC yyyy-mm-dd

  if (key !== dailyKey) {
    dailyKey = key;
    dailyCount = 0;
  }
  dailyCount += 1;
  if (dailyCount > cap) {
    if (dailyCount === cap + 1) {
      console.warn(`Daily request cap hit (${cap}) for ${key} — serving 429 until UTC midnight.`);
    }
    return false;
  }
  return true;
}
