# Privacy Policy — Roast My Gallery

**Effective date:** [EFFECTIVE DATE]
**Last updated:** [EFFECTIVE DATE]

This Privacy Policy explains how **[PROVIDER NAME]** ("we," "us," or "our"),
the developer of the **Roast My Gallery** mobile application (the "App"),
handles information in connection with your use of the App.

We built Roast My Gallery to be **privacy-first**. The App analyzes your photo
library **on your device** and, by default, only ever sends anonymous,
aggregated statistics off your device to generate your results. We do not
require an account, we do not ask for your name or email, and we do not use
advertising or third‑party analytics/tracking SDKs.

If you have any questions, contact us at **roastmygallery@gmail.com**.

---

## 1. Summary

- **Your photos stay on your device.** The App scans your photo library
  locally using Apple's on‑device frameworks. Your photos and videos are
  **not** uploaded as part of the standard experience.
- **Only anonymous statistics leave your device by default.** To write your
  "insight," the App sends a small, aggregated statistics summary (for example,
  how many selfies or screenshots you have, category counts, and time‑of‑day
  patterns) to our backend, which uses a third‑party AI provider (Google
  Gemini) to generate text. This summary contains no images, no file
  identifiers, no precise location, and no names.
- **Images are uploaded only when you explicitly opt in.** Two optional,
  paid features — **Deep Analysis** (AI photo captions) and **Deep Vision**
  (photo‑by‑photo commentary) — upload a **downscaled copy** of the specific
  photos you hand‑pick and approve, batch by batch. Those images are processed
  in memory to generate your result and then discarded. They are **not stored**
  on our servers and are **never logged**.
- **No account, no tracking, no ads, no data sales.** We do not sell or share
  your personal information for advertising, and we do not use third‑party
  analytics or ad SDKs.

---

## 2. Who we are

The App is published by **[PROVIDER NAME]** ("we"). You can reach us at
**roastmygallery@gmail.com** for any privacy request or question.

---

## 3. Information we process

### 3.1 Your photo library (processed on your device)

When you grant photo access, the App reads photos from your library to analyze
them **locally on your device**. This on‑device analysis produces the anonymous
statistics described below. The App requests:

- **Photo Library access (read):** to scan and analyze your photos on device.
- **Add‑only Photo Library access:** used only if you choose to **save a share
  card** you created back to your photo library.

Your photos themselves are **not collected by us** and, in the standard
experience, do not leave your device.

### 3.2 Aggregated, anonymous statistics ("PhotoStats")

To generate your insight, the App sends a compact statistics summary to our
backend. This summary is aggregate‑level only and is designed to contain **no
personally identifying information**. It may include:

- Counts such as total photos analyzed, selfies, screenshots, and favorites;
- Category/scene counts (e.g., "food," "pets") and how they trend by month;
- Photo counts by month and by hour of day;
- Coarse "clusters" of where photos were taken expressed **only as relative
  shares** (e.g., "most photos fall in one area") — **no place names, no map
  coordinates, no addresses**;
- Your selected "voice" (persona) and your device language/locale.

The summary **never** contains your images, photo/file identifiers, precise
GPS coordinates, contact names, or other identifying data.

### 3.3 Optional image uploads (Deep Analysis and Deep Vision)

If you use the optional paid **Deep Analysis** or **Deep Vision** features, the
App will, **only after you give explicit consent for that specific batch**:

- Resize the photos you selected into smaller copies **on your device**
  (originals are never uploaded);
- Upload those downscaled copies once to our backend, which forwards them to
  our AI provider (Google Gemini) to generate captions or commentary;
- Return the result to your device.

These uploaded images are processed **in memory** and then **discarded**. They
are **not written to disk, not stored, and never logged** on our servers.

### 3.4 Purchase and app‑user identifier

The App uses **RevenueCat** to manage in‑app purchases and a virtual currency
("gems"). For this, the App creates a **random identifier** (for example,
`rmg_` followed by a random value) stored in your device Keychain. This
identifier is **not linked to your real‑world identity** — we do not know your
name, email, or Apple ID from it.

When you make a purchase or spend/earn gems, this identifier and the relevant
purchase/transaction information are processed by Apple and RevenueCat so that
your entitlements and gem balance can be tracked. See **Section 5** for these
providers.

### 3.5 Technical/server information

When your device contacts our backend, our hosting provider (**Vercel**) and
we process limited technical data needed to operate and protect the service,
such as your **IP address** and standard request metadata, used for security
and rate‑limiting (to prevent abuse). We do not use this to build advertising
or behavioral profiles.

### 3.6 Information stored locally on your device

- **Analysis history and settings** are stored **locally on your device**. We
  do not receive a copy. You can remove this data by deleting your history in
  the App or by deleting the App.
- **Notifications:** If you enable the optional reminder, the App schedules a
  **local** notification on your device (a periodic nudge to re‑scan). This is
  handled entirely on‑device; we do not run a push‑notification server and do
  not receive notification data.

---

## 4. How we use information

We use the information described above to:

- Analyze your photos on your device and generate your insight/results;
- Provide the optional Deep Analysis and Deep Vision features you request;
- Process in‑app purchases and manage your gem balance and entitlements;
- Operate, secure, and protect the App against abuse (e.g., rate‑limiting);
- Respond to your support requests.

We do **not** use your information for advertising, and we do **not** sell it.

---

## 5. AI processing and service providers (sub‑processors)

We rely on a small number of service providers to run the App. We do not sell
your personal information to anyone. Our providers are:

| Provider | Purpose | What they process |
|---|---|---|
| **Apple** (App Store / iOS) | App distribution and in‑app purchase billing | Your purchase/transaction data, per Apple's terms |
| **RevenueCat** | In‑app purchase and virtual‑currency management | Your random app‑user identifier and purchase/entitlement data |
| **Vercel** | Backend hosting (United States) | Requests to our backend, including IP address and request metadata |
| **Google (Gemini API)** | AI text and image understanding | The anonymous statistics summary and, for Deep Analysis/Deep Vision, the downscaled images you approve |

**AI content:** The text and captions in the App are generated by an AI model
(Google Gemini) operated by Google. The anonymous statistics — and, only with
your explicit consent, your downscaled photos — are sent to Google to generate
your result. We instruct our processing so that images are used only to produce
your result and are not retained by our backend. Google's handling of API data
is governed by Google's applicable terms and privacy commitments.

- Apple: https://www.apple.com/legal/privacy/
- RevenueCat: https://www.revenuecat.com/privacy/
- Vercel: https://vercel.com/legal/privacy-policy
- Google (Gemini API): https://ai.google.dev/gemini-api/terms and https://policies.google.com/privacy

---

## 6. What we do **not** do

- We do **not** require an account or collect your name, email, or Apple ID.
- We do **not** use advertising SDKs or show third‑party ads.
- We do **not** use third‑party analytics/tracking SDKs, the Advertising
  Identifier (IDFA), or App Tracking Transparency tracking.
- We do **not** sell or "share" (as defined under U.S. state privacy laws)
  your personal information.
- We do **not** store your photos on our servers.

---

## 7. Data retention

- **Images** sent for Deep Analysis/Deep Vision: processed in memory and
  discarded after your result is generated; not stored by our backend.
- **Anonymous statistics:** used to generate your result; not retained by our
  backend as a personal profile.
- **Technical/security logs:** retained only as long as needed for security
  and abuse prevention.
- **Purchase records:** retained by Apple and RevenueCat as required to provide
  and account for purchases.
- **Local data (history/settings):** stays on your device until you delete it
  or delete the App.

---

## 8. Your choices and rights

- **Photo access:** You can grant, limit, or revoke photo access anytime in
  iOS Settings. Limiting or revoking access will reduce or disable analysis.
- **Notifications:** You can turn the reminder off in the App or iOS Settings.
- **Local data:** You can delete your history in the App or delete the App to
  remove locally stored data.
- **Purchases/identifier:** Because we do not tie your purchase identifier to
  your real identity, we may be unable to locate personal data about you.
  For requests related to your purchase records, contact us at
  **roastmygallery@gmail.com**, and you may also contact Apple or RevenueCat.

Depending on where you live, you may have rights to access, correct, or delete
personal information, or to object to certain processing. To exercise any right,
email **roastmygallery@gmail.com**. We will respond as required by applicable
law.

**U.S. state privacy note (including California):** We do not sell your personal
information and do not "share" it for cross‑context behavioral advertising. We
do not use it for targeted advertising or profiling that produces legal or
similarly significant effects.

---

## 9. Children's privacy

The App is not directed to children under 13, and we do not knowingly collect
personal information from children under 13. If you believe a child has
provided us with personal information, contact us at
**roastmygallery@gmail.com** and we will take appropriate steps.

---

## 10. International users and data transfers

We operate the App from, and process backend data in, the **United States**.
Our AI and service providers may also process data in the United States and
other countries. If you use the App from outside the United States, you
understand that your information may be processed in the United States, which
may have different data‑protection laws than your country.

---

## 11. Security

We use reasonable technical and organizational measures to protect information,
including transport encryption (HTTPS), keeping AI provider keys and secrets on
the server (never in the App), and not persisting uploaded images. No method of
transmission or storage is 100% secure, so we cannot guarantee absolute
security.

---

## 12. Changes to this Policy

We may update this Privacy Policy from time to time. When we do, we will revise
the "Last updated" date above and, where appropriate, provide additional
notice. Your continued use of the App after an update means you accept the
revised Policy.

---

## 13. Contact us

**[PROVIDER NAME]**
Email: **roastmygallery@gmail.com**

If you have concerns we cannot resolve, you may have the right to contact your
local data‑protection authority.
