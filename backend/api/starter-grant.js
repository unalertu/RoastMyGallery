// POST /api/starter-grant
// Body:    { appUserId: string }
// Returns: { ok: true, granted: boolean }
//
// Grants one-time first-launch starter credits (+3 CRD). RevenueCat only grants
// credits from purchases, so non-purchase "welcome" credits must be issued as a
// positive adjustment through the Developer API (secret key, server-side only).
//
// IDEMPOTENCY — IMPORTANT:
// This scaffold trusts the client to call at most once (it sets a local
// UserDefaults flag). That is NOT sufficient for production: a reinstall or a
// crafted request could re-grant. Before shipping, make this definitive
// server-side — e.g. GET the customer's virtual-currency transactions and skip
// if a prior starter grant exists, or record granted App User IDs in a small
// KV store (Upstash/Vercel KV). Marked as a hardening TODO.

import { grantCredits, CREDIT_COSTS } from "../lib/revenuecat.js";
import { checkAppSecret, clientIP, allowRequest } from "../lib/guard.js";

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

  // TODO (hardening): dedupe server-side before granting — see file header.
  const result = await grantCredits(appUserId, CREDIT_COSTS.starter);
  if (!result.ok) {
    return res.status(502).json({ error: "Could not grant starter credits." });
  }

  return res.status(200).json({ ok: true, granted: !result.skipped });
}
