# Roast My Gallery

iOS app that analyzes your photo library **on-device** and generates an
AI-written roast or psychological read of your photo habits, with a shareable
story card.

## Getting started

```sh
brew install xcodegen   # once
xcodegen generate       # creates RoastMyGallery.xcodeproj from project.yml
open RoastMyGallery.xcodeproj
```

Run `xcodegen generate` again whenever a Swift file is **added or removed** —
editing an existing file never needs it.

The scheme already points Run at `RoastMyGallery.storekit`, so the paywall
populates from local StoreKit products without App Store Connect. Note that a
local StoreKit purchase does **not** trigger RevenueCat's server-side Virtual
Currency grant — the gem balance won't rise from a simulated buy. Verifying a
real grant needs App Store sandbox.

The insight step calls a real backend: `backend/` holds Vercel serverless
functions wrapping the Gemini API (see `backend/README.md`).
`AppConfig.backendBaseURL` points at the deployed production URL.

## Architecture

MVVM + a protocol-based pipeline. Every stage is swappable in one place,
`AppEnvironment.live()` (`App/AppEnvironment.swift`):

```
PhotoLibraryService (PhotoKit auth + enumeration)
        │
        ▼
PhotoAnalyzing            OnDeviceAnalyzer — Vision requests on 512px
        │                 thumbnails, TaskGroup capped at 4 concurrent,
        │                 progress callbacks, cancellable. No pixels leave
        │                 the device.
        ▼
StatsAggregating          StatsAggregator — pure function folding
        │                 [PhotoObservation] → PhotoStats (compact JSON).
        ▼
InsightGenerating         BackendInsightGenerator — Vercel + Gemini; sends
        │                 ONLY the PhotoStats JSON, persona, locale, depth.
        ▼
ShareCardRendering        ShareCardRenderer — SwiftUI ImageRenderer,
                          1080×1920 story card.
```

Deep analysis adds a stage 3.5: `PhotoCaptionService` uploads the handful of
photos the results screen will show, for one short AI caption each. That and
the hand-picked Deep Vision batch are the only code paths that upload images,
and both require explicit per-run consent.

### Analysis flows

Three flows, priced in gems, all sharing the pipeline above:

| Flow | Cost | What it does |
|---|---|---|
| Standard | 1 gem | One month or album → 5–7 beat story |
| Deep | 5 gems | Any date range up to a year → 12–16 beats + an AI caption per shown photo |
| Hand-Picked | 5 gems | Up to 30 user-picked photos read individually |

**Hand-Picked is built but not shipped.** It's gated off by omission from
`AnalysisKind.launchable` (`Models/AnalysisRecord.swift`) — read the note there
before turning it on. Standard and Deep both run in the background behind a
status banner, so closing the flow mid-run doesn't lose it.

### Navigation & persistence

`RootView` is a three-tab shell — **Home** (product cards, latest analysis,
stat teaser), **History** (all past analyses, sort + filter), **Settings**
(gems, preferences, data, about, privacy). Both analysis flows are full-screen
modals presented by `RootView` off their view models' `isFlowPresented`, so a
minimized run can be reopened from any tab or from a completion notification.

Completed runs persist as `AnalysisRecord` (persona + insight + stats +
timestamp + device-only photo index) via `AnalysisHistoryStore` — Codable JSON
in Application Support, chosen over SwiftData because the models are already
Codable payloads and the volume is tiny. History is never gated.

### Design system

All visual tokens live in `App/DesignSystem.swift` (`Theme`): pastel palette
(cream background, muted-terracotta accent, dusty rose / sage / powder blue),
rounded system typography, 4–48pt spacing scale, 12/16/20pt radii, one soft
shadow, one `easeInOut(0.3)` motion curve. Views never hardcode visual values.
Light Mode is forced at the root — the palette has no tuned dark variant yet.

## Privacy contract

- Standard runs: nothing leaves the device except the aggregated `PhotoStats`
  JSON — no images, no asset IDs, no precise locations (coordinates are rounded
  to ~11 km cells on extraction and reduced to anonymous shares during
  aggregation), no PII. Enforced by the `PhotoStats` type: keep every field
  aggregate-level.
- Image uploads (deep-analysis captions, Deep Vision) are opt-in **per run**,
  unchecked by default, and cover only the photos in question. Uploaded images
  are processed in memory and never stored server-side.
- LLM API keys and the RevenueCat secret key live server-side only. The client
  talks to *our* backend, never to a provider directly.
- Settings → Privacy → "Review what data was sent" shows a plain-language
  breakdown of the exact payload from the latest scan.

## Monetization

Gems are a RevenueCat **Virtual Currency** (code `CRD`); RevenueCat holds the
authoritative balance. Three consumable packs grant gems via dashboard
associated-product grants. The client can only ever *read* the balance — every
deduction is a server-side adjustment issued by the backend inside the paid
endpoints themselves (`deduct-after-success`, idempotent per `runId`). New users
get 3 starter gems from `api/starter-grant`.

See the CONFIG block in `Services/Purchases/PurchaseManager.swift` for the four
values that must agree between the app, App Store Connect, RevenueCat, and the
backend env vars.

## Testing

`cd backend && npm test` — charge-idempotency and starter-grant tests
(`node --test`, no dependencies; upstreams are faked via `globalThis.fetch`).
The iOS side has no test target yet; `StatsAggregator` and
`AnalysisHistoryStore` are pure/isolated and are the place to start.

## Known gaps

- [ ] Dark Mode: `Theme.Colors` needs tuned dark pastel variants (Light Mode is
      forced at the root until then).
- [ ] Share card visual redesign (`ShareCardView`).
- [ ] App↔backend auth is a shared-secret tripwire, not real auth
      (`AppConfig.appSharedSecret`) — replace with App Attest if the app gets
      traction.
- [ ] Rate limiting and the daily Gemini cap are in-memory per warm Vercel
      instance (`backend/lib/guard.js`) — move to Upstash if traffic grows.
- [ ] Cross-device gem continuity relies on iCloud Keychain
      (`KeychainAppUserID`); a real login would be needed to cover users who
      have it turned off.
- [ ] Hand-Picked Deep Vision: see the note on `AnalysisKind.launchable`.
- [ ] No iOS unit test target.
