// POST /api/starter-grant
// Body:    { appUserId: string }
// Returns: { ok: true, granted: boolean }
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
    return res.status(200).json({ ok: true, granted: false });
  }

  const result = await grantCredits(appUserId, CREDIT_COSTS.starter);
  if (!result.ok) {
    if (claim === "claimed") {
      await releaseOnce("starter-grant", appUserId, "v1");
    }
    return res.status(502).json({ error: "Could not grant starter credits." });
  }

  return res.status(200).json({ ok: true, granted: !result.skipped });
}
