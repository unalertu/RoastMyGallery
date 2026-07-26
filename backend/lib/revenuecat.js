// RevenueCat Virtual Currency adjustments.
//
// Credits live in RevenueCat as a Virtual Currency (code CRD). The balance can
// only be *adjusted* with the RevenueCat SECRET key — which lives here, on the
// server, never in the app. The client asks us to spend/grant; we call
// RevenueCat's Developer API v2 transactions endpoint.
//
// Docs: https://www.revenuecat.com/docs/offerings/virtual-currency
//   POST /v2/projects/{project_id}/customers/{app_user_id}/virtual_currencies/transactions
//   body: { "adjustments": { "CRD": <signed integer> } }
//
// Fail-open by design when the env vars are unset: this mirrors the app-secret
// gate in guard.js, so deploying this code before the RevenueCat dashboard is
// configured doesn't 500 the app. Enforcement starts the moment
// REVENUECAT_SECRET_KEY + REVENUECAT_PROJECT_ID are set in Vercel.

export const CREDIT_CURRENCY_CODE = "CRD";

// Canonical credit amounts — keep in sync with PurchaseManager.swift and the
// Virtual Currency associated-product grants in the RevenueCat dashboard.
export const CREDIT_COSTS = {
  analysis: 1,
  deep_analysis: 5,
  deep_vision: 5,
  // Deliberately >= deep_analysis + analysis, so a brand-new user can run one
  // Deep AND one Standard without paying. At 3 the premium tier was literally
  // unreachable on the free grant: a first-time buyer — and an App Review
  // tester — had to purchase Deep blind, without ever seeing the consent
  // screen the privacy contract leans on.
  starter: 6,
};

const RC_API_BASE = "https://api.revenuecat.com/v2";

/**
 * Applies a signed CRD adjustment to a customer's balance.
 *
 * @param {string} appUserId  RevenueCat App User ID (from the client).
 * @param {number} delta      Signed integer: negative to spend, positive to grant.
 * @returns {Promise<{ ok: boolean, skipped?: boolean, status?: number, error?: string }>}
 *   - { ok: true }                     adjustment applied
 *   - { ok: true, skipped: true }      env not configured — no-op (fail-open)
 *   - { ok: false, status, error }     RevenueCat rejected it (e.g. insufficient balance)
 */
export async function adjustCredits(appUserId, delta) {
  const secret = process.env.REVENUECAT_SECRET_KEY;
  const projectId = process.env.REVENUECAT_PROJECT_ID;

  if (!secret || !projectId) {
    console.warn(
      "REVENUECAT_SECRET_KEY / REVENUECAT_PROJECT_ID not set — credit adjustment SKIPPED (fail-open)."
    );
    return { ok: true, skipped: true };
  }

  if (typeof appUserId !== "string" || appUserId.length === 0) {
    return { ok: false, status: 400, error: "Missing appUserId." };
  }
  if (!Number.isInteger(delta) || delta === 0) {
    return { ok: false, status: 400, error: "Adjustment must be a non-zero integer." };
  }

  const url =
    `${RC_API_BASE}/projects/${encodeURIComponent(projectId)}` +
    `/customers/${encodeURIComponent(appUserId)}/virtual_currencies/transactions`;

  let response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${secret}`,
      },
      body: JSON.stringify({ adjustments: { [CREDIT_CURRENCY_CODE]: delta } }),
    });
  } catch (error) {
    console.error("RevenueCat fetch failed:", error);
    return { ok: false, status: 502, error: "Could not reach RevenueCat." };
  }

  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    console.error(`RevenueCat adjustment error ${response.status}:`, detail.slice(0, 500));
    // A 4xx here typically means insufficient balance (over-spend) — the real
    // spend gate. Surface the status so the caller can translate it.
    return { ok: false, status: response.status, error: "RevenueCat rejected the adjustment." };
  }

  return { ok: true };
}

/**
 * Reads a customer's current CRD balance.
 *
 * Used as a pre-flight gate by paid endpoints that deduct AFTER success
 * (e.g. api/deep-vision.js): checking the balance before the expensive LLM
 * call means an unaffordable request never burns a Gemini call — while the
 * actual deduction still only happens once a result exists.
 *
 * Returns the integer balance, or null when it can't be determined (env not
 * configured, RevenueCat unreachable, unknown customer). Callers should treat
 * null as "don't block" — fail-open, consistent with the rest of this module;
 * the post-success deduction remains the authoritative gate.
 */
export async function getCreditBalance(appUserId) {
  const secret = process.env.REVENUECAT_SECRET_KEY;
  const projectId = process.env.REVENUECAT_PROJECT_ID;
  if (!secret || !projectId) return null;
  if (typeof appUserId !== "string" || appUserId.length === 0) return null;

  const url =
    `${RC_API_BASE}/projects/${encodeURIComponent(projectId)}` +
    `/customers/${encodeURIComponent(appUserId)}/virtual_currencies`;

  let response;
  try {
    response = await fetch(url, {
      headers: { Authorization: `Bearer ${secret}` },
    });
  } catch (error) {
    console.error("RevenueCat balance fetch failed:", error);
    return null;
  }
  if (!response.ok) return null;

  try {
    const data = await response.json();
    // v2 list shape: { items: [{ ..., balance }] } where each item identifies
    // its currency by code. Parse defensively across minor shape variations.
    const items = Array.isArray(data.items) ? data.items : [];
    const entry = items.find(
      (item) =>
        item?.virtual_currency?.code === CREDIT_CURRENCY_CODE ||
        item?.code === CREDIT_CURRENCY_CODE
    );
    return Number.isInteger(entry?.balance) ? entry.balance : null;
  } catch {
    return null;
  }
}

/** Convenience: spend `amount` (>0) credits. */
export function spendCredits(appUserId, amount) {
  return adjustCredits(appUserId, -Math.abs(amount));
}

/** Convenience: grant `amount` (>0) credits. */
export function grantCredits(appUserId, amount) {
  return adjustCredits(appUserId, Math.abs(amount));
}
