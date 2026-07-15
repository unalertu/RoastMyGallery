# Roast My Gallery (working title)

iOS app that analyzes your photo library **on-device** and generates an
AI-written "wrapped"-style roast or psychological read of your photo habits,
with a shareable story card.

## Getting started

```sh
brew install xcodegen   # once
xcodegen generate       # creates RoastMyGallery.xcodeproj from project.yml
open RoastMyGallery.xcodeproj
```

Then in Xcode: **Product → Scheme → Edit Scheme → Run → Options → StoreKit
Configuration** and select `RoastMyGallery.storekit` so the paywall works in
the simulator without App Store Connect.

The insight step calls a real backend: `backend/` holds a Vercel serverless
function wrapping the Gemini API (see `backend/README.md` for deploy steps).
Point `AppConfig.backendBaseURL` at your deployment (or `vercel dev` on
localhost). If the backend is unreachable, the app degrades gracefully to
`MockInsightGenerator` — you always get a result. On-device Vision analysis
is real; deep Vision analysis (Pro) is still mocked.

## Architecture

MVVM + a protocol-based pipeline. Every stage is swappable in one place,
`AppEnvironment.live()` (App/AppEnvironment.swift):

```
PhotoLibraryService (PhotoKit auth + enumeration)
        │
        ▼
PhotoAnalyzing            OnDeviceAnalyzer — Vision requests on 512px
        │                 thumbnails, TaskGroup capped at 4 concurrent,
        │                 progress callbacks, cancellable. No pixels leave
        │                 the device. iCloud originals are not downloaded.
        ▼
StatsAggregating          StatsAggregator — pure function folding
        │                 [PhotoObservation] → PhotoStats (compact JSON).
        ▼
InsightGenerating         FallbackInsightGenerator: BackendInsightGenerator
        │                 (Vercel + Gemini; sends ONLY the PhotoStats JSON,
        │                 persona, and locale) → MockInsightGenerator when
        │                 the network/backend is down.
        ▼
ShareCardRendering        ShareCardRenderer — SwiftUI ImageRenderer,
                          1080×1920 story card.

Pro branch: DeepVisionAnalyzing (MockDeepVisionService) — explicit-consent
upload of ≤30 user-picked photos. The ONLY code path that uploads images.
```

### Navigation & persistence

`RootView` is a three-tab shell — **Home** (latest analysis card or
first-run CTA), **History** (past analyses; free tier can open only the
newest, older rows lock to the paywall), **Settings** (plan, privacy,
preferences, data, about). The analysis flow itself (`Views/ScanFlow/`,
switching on `ScanViewModel.phase`: permission → persona pick → progress →
results) is a full-screen modal launched from Home, closable at any point —
including mid-scan.

Completed runs are saved as `AnalysisRecord` (persona + insight + stats +
timestamp) by `AnalysisHistoryStore` — Codable JSON in Application Support,
chosen over SwiftData because the models are already Codable payloads and
the volume is tiny. All records are stored regardless of tier (the free-tier
view limit is UI-enforced), so upgrading unlocks old analyses retroactively.
Settings → Privacy → "Review what data was sent" shows the exact stats JSON
from the latest run.

### Design system

All visual tokens live in `App/DesignSystem.swift` (`Theme`): pastel palette
(cream background, muted-terracotta accent, dusty rose / sage / powder blue
supporting colors), rounded system typography, 4–48pt spacing scale,
12/16/20pt radii, one soft shadow, and a single `easeInOut(0.3)` motion
curve. Views never hardcode visual values. Light Mode is forced at the root
(`RoastMyGalleryApp`) — a tuned dark pastel variant is a future pass, as is
the share card's visual design (`ShareCardView` is intentionally untouched).

## Privacy contract

- Free tier: nothing leaves the device except the aggregated `PhotoStats`
  JSON — no images, no asset IDs, no precise locations (coordinates are
  rounded to ~11 km cells on extraction and reduced to anonymous shares
  during aggregation), no PII. Enforced by the `PhotoStats` type: keep every
  field aggregate-level.
- Pro deep analysis: uploads only photos the user hand-picked, behind the
  Pro entitlement AND a per-batch consent toggle (`DeepAnalysisConsentView`).
- LLM API keys live server-side only. The client talks to *your* backend
  (`BackendConfiguration`), never to the LLM provider directly.

## Monetization

All gating flows through `PurchaseManager.Entitlements` — views never derive
Pro status themselves. StoreKit 2, local testing via `RoastMyGallery.storekit`.
Pro gates on **scope only**; both personas are free — persona choice is a
stylistic preference, never a paywall lever.

| | Free | Pro |
|---|---|---|
| History | last 3 months | full |
| Personas | Roast + Analyst | Roast + Analyst |
| Deep photo analysis | — | 30 photos/batch |
| Share cards | 1 | unlimited |

## TODOs to make it real

- [ ] `PurchaseManager.ProductID` + `RoastMyGallery.storekit` + App Store
      Connect: real product IDs (currently `com.example.roastmygallery.*`).
- [ ] `project.yml`: real bundle ID prefix and `DEVELOPMENT_TEAM`.
- [ ] Deploy `backend/` to Vercel and set `AppConfig.backendBaseURL` to the
      production URL (currently `http://localhost:3000` for `vercel dev`).
- [ ] Backend: deep-analysis endpoint (vision LLM over consented photos) —
      insight endpoint (`api/insight.js`) is done.
- [ ] App↔backend auth (App Attest / anonymous token) — the endpoint is
      currently open; fine for development, not for launch.
- [ ] Remove the ATS local-networking exception (project.yml) once localhost
      isn't needed.
- [ ] Enforce the free-tier 1-card limit (`InsightView.renderShareCard`).
- [ ] Monthly re-scan reminder: schedule via UNUserNotificationCenter when
      the Settings toggle is enabled (currently a persisted stub).
- [ ] About section: real feedback address + SKStoreReviewController for
      "Rate this app".
- [ ] Replace the generated placeholder app icon with real branding.
- [ ] Inject `DeepVisionAnalyzing` into `DeepAnalysisConsentView` via
      `AppEnvironment`; downscale photos before upload; show thumbnails next
      to commentary.
- [ ] Dark Mode: design tuned dark pastel variants in `Theme.Colors`
      (Light Mode is forced at the root until then).
- [ ] Share card visual redesign (`ShareCardView`) — separate pass.
- [ ] Unit tests: `StatsAggregator` and `AnalysisHistoryStore` are pure /
      isolated — start there.
