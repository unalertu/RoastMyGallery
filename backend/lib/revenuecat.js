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
  deep_vision: 5,
  starter: 3,
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

/** Convenience: spend `amount` (>0) credits. */
export function spendCredits(appUserId, amount) {
  return adjustCredits(appUserId, -Math.abs(amount));
}

/** Convenience: grant `amount` (>0) credits. */
export function grantCredits(appUserId, amount) {
  return adjustCredits(appUserId, Math.abs(amount));
}
