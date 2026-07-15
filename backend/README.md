# Roast My Gallery — backend

One Vercel serverless function that turns the app's anonymous `PhotoStats`
JSON into an LLM-written insight via the Google Gemini API
(`gemini-3.1-flash-lite`, free tier — note `gemini-2.5-flash-lite` is
retired for new API projects and returns 404).

```
backend/
├── api/insight.js    # POST /api/insight — gates, validation, Gemini call
├── lib/prompts.js    # persona prompts + model ID — edit here to tune tone
├── lib/guard.js      # abuse gates: app secret, per-IP limit, daily cap
├── package.json      # zero dependencies (built-in fetch)
└── .env.example      # GEMINI_API_KEY template
```

No `vercel.json` needed — Vercel auto-detects `api/*.js` as serverless
functions with zero config.

## API

`POST /api/insight` — requires header `X-App-Secret` once `APP_SHARED_SECRET`
is set (see below).

```jsonc
// request
{ "stats": { /* PhotoStats JSON */ }, "persona": "roast" | "analyst",
  "locale": "en_US", "schemaVersion": 1 }
// 200 response
{
  "insightText": "Title line\n\nSegment one.\n\nSegment two.",  // legacy clients
  "shareLine": "One quotable line.",                            // or null
  "segments": [                                                 // or null
    { "text": "Segment one.", "category": "food" },  // category from the
    { "text": "Segment two.", "category": null }     // user's own stats, or null
  ],
  "generatedAt": "2026-07-14T20:00:00Z"
}
// errors: 400 invalid input · 401 bad/missing app secret · 405 wrong method ·
//         429 rate limited (reason: "rate_limited" | "daily_cap", or Gemini) ·
//         500 missing API key · 502 Gemini unreachable/unusable response
{ "error": "human-readable message" }
```

The first line of `insightText` is the headline; the iOS client splits it off.
`segments` is the same narrative split into beats, each optionally tagged with
a category **from that user's own submitted stats** (enforced server-side via
`allowedCategories()`), so the app can show a matching photo from the user's
library — the photo lookup happens entirely on-device. `segments` is `null`
when the model ignored the JSON contract and the server fell back to plain
text parsing.

## Abuse protection

The endpoint burns a free-tier Gemini key, so several cheap gates run before
any Gemini call (all in `lib/guard.js` / `api/insight.js`):

1. **App secret** — requests must carry `X-App-Secret` matching the
   `APP_SHARED_SECRET` env var (compared timing-safe). *Fail-open by design*:
   if the env var is unset the check is skipped (with a console warning), so
   deploying code before setting the var can't break the live app.
2. **Per-IP rate limit** — 10 requests/min/IP, in-memory, → 429
   `reason: "rate_limited"`.
3. **Strict validation** — body limited to known fields; `stats` must match
   the PhotoStats schema exactly (types, ranges, bounded sizes, ≤64 KB);
   persona restricted to known values. Fails 400 *before* spending budget.
4. **Daily cap** — 800 requests/day by default (~80% of the free tier's
   ~1,000/day), override with `DAILY_REQUEST_CAP`. → 429 `reason: "daily_cap"`
   until UTC midnight. The iOS app treats any failure as a cue to fall back
   to its on-device preview insight, so users never see a hard error.

**What this does and doesn't protect against:** it stops casual abuse —
someone who finds the URL and curls it, a buggy device stuck in a retry loop,
oversized/junk payloads. It does **not** stop a determined attacker who
extracts the shared secret from the app binary; that's what App Attest would
be for, later. The counters are in-memory per warm serverless instance: they
reset on cold starts and aren't shared across instances, so real-world limits
are only ever *more permissive* than configured — good enough as a budget
tripwire, not a hard guarantee. (Upgrade path: swap `guard.js` internals for
Upstash Redis; the handler doesn't change.)

Rotating the secret: generate a new value, set it in both
`RoastMyGallery/App/AppConfig.swift` (`appSharedSecret`) and the Vercel env
var, ship the app update first — fail-open ordering doesn't help here, so
update the env var only after users are on the new build (or accept that old
builds fall back to preview insights).

## Deploy (one-time setup)

1. **Get a Gemini API key**: https://aistudio.google.com/apikey (free tier
   covers this; keys are issued in `AQ.…` format). If Gemini returns
   403 "project has been denied access", create the key in a *new* project
   from the same page.

2. **Install the Vercel CLI and log in:**

   ```sh
   npm install -g vercel
   vercel login
   ```

3. **Deploy from this folder:**

   ```sh
   cd backend
   vercel deploy          # first run: accept defaults to create the project
   ```

4. **Set the environment variables** (once; the API key is required, the
   others enable/tune the abuse gates):

   ```sh
   vercel env add GEMINI_API_KEY production      # paste your key when prompted
   vercel env add APP_SHARED_SECRET production   # paste AppConfig.appSharedSecret
   vercel env add DAILY_REQUEST_CAP production   # optional, default 800
   ```

   (Or: Vercel dashboard → your project → Settings → Environment Variables.)
   `APP_SHARED_SECRET` must equal `appSharedSecret` in
   `RoastMyGallery/App/AppConfig.swift`; until it's set the secret check is
   skipped (fail-open), so ordering is safe.

5. **Deploy to production and get the URL:**

   ```sh
   vercel deploy --prod
   ```

   The command prints the production URL, e.g.
   `https://roast-my-gallery-backend.vercel.app` — that's the value for
   `AppConfig.backendBaseURL` in the iOS app. You can always find it later in
   the Vercel dashboard under the project's **Domains**.

## Local development

```sh
cd backend
cp .env.example .env    # put your real key in .env (gitignored)
vercel dev              # serves http://localhost:3000
```

Smoke test:

```sh
curl -s http://localhost:3000/api/insight \
  -H 'Content-Type: application/json' \
  -H "X-App-Secret: $APP_SHARED_SECRET" \
  -d '{"persona":"roast","locale":"en_US","stats":{"analyzedPhotos":812,"totalPhotos":812,"selfieCount":214,"screenshotCount":301,"favoriteCount":12,"faceCountBuckets":{"0":400,"1":300,"2+":112},"topCategories":[{"category":"food","count":190}],"categoriesByMonth":{},"photosByMonth":{"2026-06":300},"photosByHourOfDay":[0,0,0,40,0,0,0,0,10,20,30,40,50,60,70,80,90,100,90,60,40,20,10,2],"topLocationClusters":[{"share":0.87,"label":"cluster-1"}],"animalCounts":{"cat":44},"generatedAt":"2026-07-14T12:00:00Z","scope":"lastThreeMonths"}}'
```

## Tuning the personas

Edit `lib/prompts.js`. Keep the JSON output contract
(`{ title, segments: [{ text, category }], shareLine }`) — `api/insight.js`
parses and sanitizes it (and falls back to plain-text parsing if the model
drifts). Model can be changed via `GEMINI_MODEL` in the same file.
