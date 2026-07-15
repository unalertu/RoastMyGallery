// POST /api/spend
// Body:    { appUserId: string, amount: number, reason: string }
// Returns: { ok: true } on success, or an error with the right status.
//
// Deducts credits (a negative CRD adjustment) from a customer's RevenueCat
// Virtual Currency balance. The RevenueCat SECRET key lives only in this
// server's env (REVENUECAT_SECRET_KEY) — never in the app.
//
// CONTRACT: callers must only spend AFTER the paid action has already
// succeeded (deduct-after-success). This endpoint is used for client-
// orchestrated actions like Deep Vision. The analysis spend is folded directly
// into /api/insight instead, so it never routes here.

import { spendCredits, CREDIT_COSTS } from "../lib/revenuecat.js";
import { checkAppSecret, clientIP, allowRequest } from "../lib/guard.js";

/** Allowed spend reasons → the credit amount each one costs. */
const SPEND_REASONS = {
  deep_vision: CREDIT_COSTS.deep_vision,
  analysis: CREDIT_COSTS.analysis,
};

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed. Use POST." });
  }

  const secretError = checkAppSecret(req);
  if (secretError) {
    console.warn(`Rejected /api/spend without valid app secret from ${clientIP(req)}.`);
    return res.status(401).json({ error: secretError });
  }

  if (!allowRequest(clientIP(req))) {
    return res.status(429).json({ error: "Too many requests. Try again in a minute." });
  }

  const { appUserId, amount, reason } = req.body ?? {};

  if (typeof appUserId !== "string" || appUserId.length === 0 || appUserId.length > 256) {
    return res.status(400).json({ error: 'Field "appUserId" is required.' });
  }
  if (typeof reason !== "string" || !Object.hasOwn(SPEND_REASONS, reason)) {
    return res
      .status(400)
      .json({ error: `Field "reason" must be one of: ${Object.keys(SPEND_REASONS).join(", ")}.` });
  }
  // The amount is authoritative on the server: it must match the reason's cost,
  // so a client can't ask to spend an arbitrary number.
  const expected = SPEND_REASONS[reason];
  if (!Number.isInteger(amount) || amount !== expected) {
    return res.status(400).json({ error: `Field "amount" must equal ${expected} for reason "${reason}".` });
  }

  const result = await spendCredits(appUserId, expected);
  if (!result.ok) {
    // RevenueCat rejects an over-spend (insufficient balance) with a 4xx — this
    // is the authoritative gate the client's UX check only approximates.
    const status = result.status && result.status < 500 ? 402 : 502;
    return res.status(status).json({
      error: status === 402 ? "Insufficient credits." : "Could not process the spend.",
      reason: status === 402 ? "insufficient_credits" : "upstream_error",
    });
  }

  return res.status(200).json({ ok: true, skipped: result.skipped ?? false });
}
