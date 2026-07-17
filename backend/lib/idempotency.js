// Charge idempotency for the paid endpoints (insight, deep-vision).
//
// THE PROBLEM: both endpoints charge deduct-after-success. If the generated
// response never reaches the client (app suspended mid-request, connection
// died on the way back), the user was charged for a story they never saw —
// and their retry generates AND CHARGES again.
//
// THE FIX: the client sends a stable `runId` per user intent (it reuses the
// same ID when retrying the same run — see ScanViewModel/DeepVisionRunner).
// Before deducting, the endpoint atomically claims the charge for
// `{endpoint}:{appUserId}:{runId}` via Redis `SET NX`. First claim wins and
// deducts; a retry of the same run generates a fresh result but finds the
// claim already taken and skips the deduction. The user pays exactly once
// per intent.
//
// DELIBERATELY NOT a response cache: deep-vision's privacy contract promises
// that nothing derived from photos is ever written to a store, so we only
// persist the tiny claim marker (IDs, no content). The cost is that a replay
// burns a second Gemini call — rare enough to be the right trade.
//
// Storage: any Upstash-compatible Redis REST endpoint. Vercel's KV /
// Marketplace Redis integrations inject KV_REST_API_URL + KV_REST_API_TOKEN;
// a hand-configured Upstash database uses UPSTASH_REDIS_REST_URL/_TOKEN.
// Fail-open by design when unset (consistent with guard.js/revenuecat.js):
// without the env vars every claim returns "unknown" and endpoints behave
// exactly as before this module existed.

/** How long a claim lives. Retries of a lost run happen within minutes; 48h
 * comfortably covers "phone died overnight" while keeping keys ephemeral. */
const CLAIM_TTL_SECONDS = 48 * 60 * 60;

/** runId is client-generated (a UUID); bound it tightly before keying on it. */
export const RUN_ID_PATTERN = /^[A-Za-z0-9-]{1,64}$/;

function restConfig() {
  const url = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) return null;
  return { url, token };
}

/**
 * Atomically claims the charge for one run.
 *
 * @param {string} endpoint   Short endpoint tag, e.g. "insight".
 * @param {string} appUserId  RevenueCat App User ID.
 * @param {string} runId      Client-generated run ID (validated by caller).
 * @returns {Promise<"claimed" | "duplicate" | "unknown">}
 *   - "claimed":   first time this run is seen → deduct credits.
 *   - "duplicate": a previous request already claimed (and deducted) this
 *                  run → skip the deduction.
 *   - "unknown":   store unavailable/not configured → fail-open, deduct as
 *                  if idempotency didn't exist.
 */
export async function claimCharge(endpoint, appUserId, runId) {
  const config = restConfig();
  if (!config) return "unknown";

  const key = `charge:${endpoint}:${appUserId}:${runId}`;
  let response;
  try {
    // Upstash REST single-command form: POST / with the command as a JSON
    // array. SET ... NX EX <ttl> → { result: "OK" } when the key was set,
    // { result: null } when it already existed.
    response = await fetch(config.url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${config.token}`,
      },
      body: JSON.stringify(["SET", key, "1", "NX", "EX", String(CLAIM_TTL_SECONDS)]),
    });
  } catch (error) {
    console.error("Idempotency store unreachable:", error);
    return "unknown";
  }

  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    console.error(`Idempotency store error ${response.status}:`, detail.slice(0, 200));
    return "unknown";
  }

  try {
    const data = await response.json();
    return data.result === "OK" ? "claimed" : "duplicate";
  } catch {
    return "unknown";
  }
}
