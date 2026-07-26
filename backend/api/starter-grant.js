// POST /api/starter-grant
// Body:    { appUserId: string }
// Returns: { ok: true, granted: true }
//          { ok: true, granted: false, reason: "already_granted" | "not_configured" }
//
// Grants one-time first-launch starter credits (+3 CRD). RevenueCat only grants
// credits from purchases, so non-purchase "welcome" credits must be issued as a
// positive adjustment through the Developer API (secret key, server-side only).
//
// IDEMPOTENCY:
// One grant per App User ID, ever, enforced server-side via a permanent
// `claimOnce` marker in the same KV store the paid endpoints use for charge
// idempotency (see lib/idempotency.js). The client's local UserDefaults flag
// is just politeness; this claim is what stops a reinstall or a crafted
// request from re-granting. Fail-open when the KV env vars are unset — until
// then the endpoint behaves like the old client-trusting scaffold.
//
// WHY `reason` EXISTS: "granted: false" alone is ambiguous, and the two cases
// need opposite handling from the client. `already_granted` is settled — this
// user has had their credits, stop asking. `not_configured` means NOTHING was
// granted and nothing was recorded (the RevenueCat env vars aren't set yet), so
// the client MUST keep retrying on later launches. Collapsing the two is how a
// first launch against a half-configured backend strands a user at zero credits
// forever: the client latches "asked once" and never asks again.

import { grantCredits, CREDIT_COSTS } from "../lib/revenuecat.js";
import { checkAppSecret, clientIP, allowRequest } from "../lib/guard.js";
import { claimOnce, releaseOnce } from "../lib/idempotency.js";

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed. Use POST." });
  }

  const secretError = checkAppSecret(req);
  if (secretError) {
    console.warn(`Rejected /api/starter-grant without valid app secret from ${clientIP(req)}.`);
    return res.status(401).json({ error: secretError });
  }

  if (!allowRequest(clientIP(req))) {
    return res.status(429).json({ error: "Too many requests. Try again in a minute." });
  }

  const { appUserId } = req.body ?? {};
  if (typeof appUserId !== "string" || appUserId.length === 0 || appUserId.length > 256) {
    return res.status(400).json({ error: 'Field "appUserId" is required.' });
  }

  // Claim BEFORE granting so concurrent duplicates can't both grant; if the
  // grant then fails, release the claim so the client's next-launch retry
  // isn't permanently locked out of its starter credits.
  const claim = await claimOnce("starter-grant", appUserId, "v1");
  if (claim === "duplicate") {
    return res.status(200).json({ ok: true, granted: false, reason: "already_granted" });
  }

  const result = await grantCredits(appUserId, CREDIT_COSTS.starter);

  // Release on ANY outcome that didn't actually move the balance — a failure
  // *and* a fail-open skip. A skip that leaves its claim behind is the worst of
  // both worlds: no credits were granted, yet every later attempt reads as
  // "already_granted" and the user can never receive them.
  if (!result.ok || result.skipped) {
    if (claim === "claimed") {
      await releaseOnce("starter-grant", appUserId, "v1");
    }
    if (!result.ok) {
      return res.status(502).json({ error: "Could not grant starter credits." });
    }
    return res.status(200).json({ ok: true, granted: false, reason: "not_configured" });
  }

  return res.status(200).json({ ok: true, granted: true });
}
