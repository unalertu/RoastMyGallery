// Charge-idempotency tests. Run from backend/: `npm test` (node --test).
//
// No dependencies: `globalThis.fetch` is replaced with a router that fakes
// the three upstreams (Upstash KV, RevenueCat, Gemini), so the real handlers
// in api/ run end-to-end and the assertions are about the only thing that
// matters — how many times a runId ends up deducting credits.
//
// The policy under test (see backend/lib/idempotency.js): a retry carrying
// the same runId as an earlier attempt may regenerate the result, but only
// the first attempt to reach the atomic SET NX claim ever deducts. There is
// no "pending → reject" state on purpose: charging happens after generation,
// so concurrent duplicates are safe — both return a result, one pays.

import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";

// Fake upstream endpoints, intercepted by the fetch router below.
const KV_URL = "https://fake-kv.test";
process.env.KV_REST_API_URL = KV_URL;
process.env.KV_REST_API_TOKEN = "test-kv-token";
process.env.GEMINI_API_KEY = "test-gemini-key";
process.env.REVENUECAT_SECRET_KEY = "test-rc-secret";
process.env.REVENUECAT_PROJECT_ID = "test-project";

const { claimCharge } = await import("../lib/idempotency.js");
const insightHandler = (await import("../api/insight.js")).default;
const deepVisionHandler = (await import("../api/deep-vision.js")).default;

// ---------------------------------------------------------------------------
// Fake upstreams

/** In-memory stand-in for Upstash's `SET key value NX EX ttl`. */
const kvStore = new Map();

/** appUserId → number of RevenueCat spend transactions. THE metric. */
const spends = new Map();

/** Resolved before Gemini "responds" — lets a test hold requests in flight. */
let geminiGate = null;

/** Body Gemini returns; per-endpoint valid JSON contracts. */
const geminiText = {
  insight: JSON.stringify({
    title: "A Test Story",
    segments: [{ text: "One test segment.", category: null }],
    shareLine: "Share me",
  }),
  vision: JSON.stringify({
    summary: "A test summary.",
    segments: [{ photoIndexes: [0], text: "One vision segment." }],
  }),
};

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

globalThis.fetch = async (url, options = {}) => {
  const href = typeof url === "string" ? url : url.href;

  if (href.startsWith(KV_URL)) {
    // Single-command form: ["SET", key, "1", "NX", "EX", ttl].
    const [command, key] = JSON.parse(options.body);
    assert.equal(command, "SET");
    if (kvStore.has(key)) return json({ result: null });
    kvStore.set(key, "1");
    return json({ result: "OK" });
  }

  if (href.includes("api.revenuecat.com")) {
    if (href.endsWith("/virtual_currencies/transactions")) {
      const appUserId = decodeURIComponent(href.match(/customers\/([^/]+)\//)[1]);
      spends.set(appUserId, (spends.get(appUserId) ?? 0) + 1);
      return json({});
    }
    // Balance read (deep-vision's affordability pre-check).
    return json({ items: [{ code: "CRD", balance: 100 }] });
  }

  if (href.includes("generativelanguage.googleapis.com")) {
    if (geminiGate) await geminiGate;
    const text = href.includes("deep-vision") || options.body?.includes("inline_data")
      ? geminiText.vision
      : geminiText.insight;
    return json({ candidates: [{ content: { parts: [{ text }] } }] });
  }

  throw new Error(`Unexpected fetch in test: ${href}`);
};

beforeEach(() => {
  kvStore.clear();
  spends.clear();
  geminiGate = null;
});

// ---------------------------------------------------------------------------
// Request/response plumbing

let nextIP = 1;

/** Unique IP per call so the per-IP rate limiter never interferes. */
function makeReq(body) {
  nextIP += 1;
  return {
    method: "POST",
    headers: { "x-forwarded-for": `10.0.${(nextIP / 250) | 0}.${nextIP % 250}` },
    socket: { remoteAddress: "127.0.0.1" },
    body,
  };
}

function makeRes() {
  return {
    statusCode: 0,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

/** Minimal PhotoStats passing api/insight.js's strict schema. */
const validStats = () => ({
  generatedAt: "2026-07-17T00:00:00Z",
  scope: { kind: "fullHistory" },
  totalPhotos: 100,
  analyzedPhotos: 100,
  selfieCount: 10,
  screenshotCount: 5,
  favoriteCount: 3,
  faceCountBuckets: {},
  topCategories: [{ category: "pets", count: 40 }],
  categoriesByMonth: {},
  photosByMonth: {},
  photosByHourOfDay: Array(24).fill(0),
  topLocationClusters: [],
  animalCounts: {},
});

const insightBody = (appUserId, runId) => ({
  stats: validStats(),
  persona: "roast",
  appUserId,
  runId,
});

// "QUJDRA==" = base64("ABCD"): a valid, tiny stand-in for a JPEG payload.
const visionBody = (appUserId, runId) => ({
  appUserId,
  persona: "roast",
  images: ["QUJDRA=="],
  runId,
});

async function call(handler, body) {
  const res = makeRes();
  await handler(makeReq(body), res);
  return res;
}

// ---------------------------------------------------------------------------
// /api/insight

test("insight: a normal single request succeeds and charges once", async () => {
  const res = await call(insightHandler, insightBody("user-a", "run-1"));
  assert.equal(res.statusCode, 200);
  assert.ok(res.body.insightText.includes("A Test Story"));
  assert.equal(spends.get("user-a"), 1);
});

test("insight: retrying a completed run does NOT charge again", async () => {
  const first = await call(insightHandler, insightBody("user-b", "run-1"));
  assert.equal(first.statusCode, 200);

  // The client never saw `first` (network drop) and retries with the SAME
  // runId: it must still get a usable result, but no second deduction.
  const retry = await call(insightHandler, insightBody("user-b", "run-1"));
  assert.equal(retry.statusCode, 200);
  assert.ok(retry.body.insightText.length > 0);
  assert.equal(spends.get("user-b"), 1);
});

test("insight: a NEW runId is a new intent and charges again", async () => {
  await call(insightHandler, insightBody("user-c", "run-1"));
  await call(insightHandler, insightBody("user-c", "run-2"));
  assert.equal(spends.get("user-c"), 2);
});

test("insight: retry while the first attempt is still pending charges exactly once", async () => {
  // Hold Gemini so both requests are simultaneously in flight, then release.
  let release;
  geminiGate = new Promise((resolve) => (release = resolve));

  const inFlight = Promise.all([
    call(insightHandler, insightBody("user-d", "run-1")),
    call(insightHandler, insightBody("user-d", "run-1")),
  ]);
  release();
  const [a, b] = await inFlight;

  // Policy: no rejection — both attempts return a result, one deducts.
  assert.equal(a.statusCode, 200);
  assert.equal(b.statusCode, 200);
  assert.equal(spends.get("user-d"), 1);
});

test("insight: runs from different users never collide on the same runId", async () => {
  await call(insightHandler, insightBody("user-e", "shared-run"));
  await call(insightHandler, insightBody("user-f", "shared-run"));
  assert.equal(spends.get("user-e"), 1);
  assert.equal(spends.get("user-f"), 1);
});

// ---------------------------------------------------------------------------
// /api/deep-vision — same protection, the 5-gem endpoint

test("deep-vision: a normal single request succeeds and charges once", async () => {
  const res = await call(deepVisionHandler, visionBody("user-g", "run-1"));
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.summary, "A test summary.");
  assert.equal(spends.get("user-g"), 1);
});

test("deep-vision: retrying a completed run does NOT charge again", async () => {
  await call(deepVisionHandler, visionBody("user-h", "run-1"));
  const retry = await call(deepVisionHandler, visionBody("user-h", "run-1"));
  assert.equal(retry.statusCode, 200);
  assert.equal(spends.get("user-h"), 1);
});

test("deep-vision: an insight run and a deep-vision run may share a runId", async () => {
  // Keys are namespaced per endpoint, so one flow's claim can never eat
  // the other's charge.
  await call(insightHandler, insightBody("user-i", "run-1"));
  await call(deepVisionHandler, visionBody("user-i", "run-1"));
  assert.equal(spends.get("user-i"), 2);
});

// ---------------------------------------------------------------------------
// claimCharge unit behavior

test("claimCharge: claimed → duplicate for the same key, and fail-open without a store", async () => {
  assert.equal(await claimCharge("insight", "user-x", "run-9"), "claimed");
  assert.equal(await claimCharge("insight", "user-x", "run-9"), "duplicate");

  const savedURL = process.env.KV_REST_API_URL;
  delete process.env.KV_REST_API_URL;
  delete process.env.UPSTASH_REDIS_REST_URL;
  assert.equal(await claimCharge("insight", "user-x", "run-10"), "unknown");
  process.env.KV_REST_API_URL = savedURL;
});
