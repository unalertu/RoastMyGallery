# ✅ OBSOLETE — everything below is already deployed (2026-07-26)

> **Do not send this to anyone.** Every change described in this file was applied
> directly to the live site on 2026-07-26 and verified (version
> `ac446486-ce6d-4133-90e1-41fff8e5a87d`). Sending it would ask someone to redo
> finished work.
>
> **The site source now lives in [`site/`](../site/) in this repo** — it was
> previously deployed from a temp directory that no longer exists, which is why a
> courier file was needed at all. Future edits: change the files under
> `site/public/`, run `cd site && npx wrangler deploy`. No handoff required.
>
> Kept only as a record of what changed and why. Safe to delete.

---

# (Historical) Handoff: `/privacy/` and `/terms/` corrections

> Regenerated 2026-07-26. Every "find" string below was **verified against the
> live pages** on that date, not written from memory.

---

Two pages on the `roastmygallery` Cloudflare Worker need changes:
`/privacy/` (six edits) and `/terms/` (one edit). There is also an **optional**
third part for `/support/`.

**Nothing needs to be created.** `/support/` is already live and correct, the
`/privacy/` iCloud-Keychain paragraph is already correct, and all of section 6
of `/terms/` (the subscription/lifetime cleanup) is already correct. An earlier
version of this handoff asked for those — they are **done**, skip them.

The provider name (Ertuğrul Ünal), contact email, effective date and
governing-law clause on both live pages are already correct. Don't touch them.

> **Two warnings before you start:**
>
> 1. **Don't rely on the section numbers I quote.** Locate each passage by
>    searching for the quoted text, in case the live pages are numbered
>    differently.
> 2. **The source text uses non-breaking hyphens (U+2011) in words like
>    "third‑party", "photo‑by‑photo", "hand‑pick", "time‑of‑day".** If a search
>    for a quoted phrase fails, that's almost certainly why — search for a
>    shorter fragment without a hyphen in it (I've suggested one for each edit).

---

# Why these changes

The app grew a **consent gate** for Deep Analysis. Photos are no longer chosen
by the user up front: the app writes the story first, then picks a small number
of photos that illustrate it, then **shows the user that exact batch** and lets
them remove any of them or decline entirely. Only approved photos upload.

Both live pages still describe the old model, and both still describe a
**Deep Vision** feature that is not in the shipping app at all. Three
consequences:

- "the specific photos you **hand-pick**" is now simply false — the app picks
  them, the user approves them.
- Describing Deep Vision means the policy documents a feature a reviewer cannot
  find, and — because an earlier edit already removed Deep Vision from two
  sections but not the rest — the page currently **contradicts itself**.
- The Gemini **paid-tier** commitment (no training on your data) is stated in
  the app's own UI but is missing from the policy.

---

# PART 1 — `/privacy/`, six edits

## 1a. The summary bullet near the top

**Find** (search for: `hand`):

> - **Images are uploaded only when you explicitly opt in.** Two optional,
>   paid features — **Deep Analysis** (AI photo captions) and **Deep Vision**
>   (photo‑by‑photo commentary) — upload a **downscaled copy** of the specific
>   photos you hand‑pick and approve, batch by batch. Those images are processed
>   in memory to generate your result and then discarded. They are **not stored**
>   on our servers and are **never logged**.

**Replace with:**

> - **Images are uploaded only when you explicitly opt in, and only after you
>   have seen them.** The optional, paid **Deep Analysis** feature (AI photo
>   captions) shows you the exact photos it proposes to caption; you can remove
>   any of them, or decline entirely, and only the photos you approve are uploaded
>   as a **downscaled copy**. Those images are processed in memory to generate
>   your result and then discarded. They are **not stored** on our servers and are
>   **never logged**.

## 1b. The optional-image-uploads section (numbered 3.3 in our source)

**Find** (search for: `Optional image uploads`). Replace the **heading and
everything under it** down to and including the "not written to disk" sentence:

> ### 3.3 Optional image uploads (Deep Analysis and Deep Vision)
>
> If you use the optional paid **Deep Analysis** or **Deep Vision** features, the
> App will, **only after you give explicit consent for that specific batch**:
>
> - Resize the photos you selected into smaller copies **on your device**
>   (originals are never uploaded);
> - Upload those downscaled copies once to our backend, which forwards them to
>   our AI provider (Google Gemini) to generate captions or commentary;
> - Return the result to your device.
>
> These uploaded images are processed **in memory** and then **discarded**. They
> are **not written to disk, not stored, and never logged** on our servers.

**Replace with** (note the new paragraph in the middle — that's the important
part of this whole handoff):

> ### 3.3 Optional image uploads (Deep Analysis)
>
> If you use the optional paid **Deep Analysis** feature, the App will, **only
> after you have seen the specific photos involved and approved that exact
> batch**:
>
> - Resize the photos you approved into smaller copies **on your device**
>   (originals are never uploaded);
> - Upload those downscaled copies once to our backend, which forwards them to
>   our AI provider (Google Gemini) to generate captions;
> - Return the result to your device.
>
> To be precise about how that batch is chosen: the App selects a small number of
> photos from your library that best illustrate the story it has written, and then
> **presents them to you before anything is uploaded**. You may remove any of them
> or decline the upload altogether, in which case no image leaves your device and
> you simply receive your story without captions.
>
> These uploaded images are processed **in memory** and then **discarded**. They
> are **not written to disk, not stored, and never logged** on our servers.

## 1c. The purposes list ("We use the information described above to:")

**Find** (search for: `features you request`):

> - Provide the optional Deep Analysis and Deep Vision features you request;

**Replace with:**

> - Provide the optional Deep Analysis captions you request;

## 1d. The third-party providers table — the Google row

**Find** (search for: `Deep Analysis/Deep Vision, the downscaled`) — this is the
**"What they process"** cell of the `Google (Gemini API)` row:

> The anonymous statistics summary and, for Deep Analysis/Deep Vision, the downscaled images you approve

**Replace with:**

> The anonymous statistics summary and, for Deep Analysis, the downscaled images you approve

Leave the other two cells of that row (`Google (Gemini API)` and
`AI text and image understanding`) alone.

## 1e. The "AI content" paragraph under that table

**Find** (search for: `AI content`):

> **AI content:** The text and captions in the App are generated by an AI model
> (Google Gemini) operated by Google. The anonymous statistics — and, only with
> your explicit consent, your downscaled photos — are sent to Google to generate
> your result. We instruct our processing so that images are used only to produce
> your result and are not retained by our backend. Google's handling of API data
> is governed by Google's applicable terms and privacy commitments.

**Replace with** (this becomes four paragraphs — keep the blank lines):

> **AI content:** The text and captions in the App are generated by an AI model
> (Google Gemini) operated by Google. The anonymous statistics — and, only with
> your explicit approval of the specific photos, your downscaled images — are sent
> to Google to generate your result.
>
> We use Google's **paid** Gemini API service. Under Google's terms for that
> service, Google does **not** use your prompts or the images we send to improve
> or train its models, and they are not subject to human review for product
> improvement. Google may retain prompts and responses for a limited period solely
> to detect and prevent abuse and to meet its legal and security obligations. Our
> own backend processes your images in memory only and does not retain them.
>
> Google's handling of API data is governed by Google's applicable terms and
> privacy commitments, linked below.

The bulleted list of provider links that follows this paragraph does not change
— "linked below" refers to it, so make sure it stays directly underneath.

## 1f. The data-retention bullet

**Find** (search for: `processed in memory and`):

> - **Images** sent for Deep Analysis/Deep Vision: processed in memory and
>   discarded after your result is generated; not stored by our backend.

**Replace with:**

> - **Images** sent for Deep Analysis: processed in memory and
>   discarded after your result is generated; not stored by our backend.

## Then

Bump the **"Last updated"** date at the top of `/privacy/` to the deploy date.
Leave the **"Effective date"** (July 18, 2026) unchanged.

---

# PART 2 — `/terms/`, one edit

**Find** (search for: `You retain all rights`) — the first paragraph of the
"Your content and photos" section (numbered 5 in our source):

> You retain all rights to your own photos. The App processes your photos as
> described in the Privacy Policy: analysis happens on your device, and images
> are only uploaded when you explicitly opt in to Deep Analysis or Deep Vision.

**Replace with:**

> You retain all rights to your own photos. The App processes your photos as
> described in the Privacy Policy: analysis happens on your device, and images
> are only uploaded when you explicitly opt in to Deep Analysis and approve the
> specific photos involved.

Keep the "Privacy Policy" link exactly as it is on the live page — only the
final clause of the sentence changes.

The two paragraphs after this one ("By using the optional upload features…" and
"You are responsible for…") **do not change**.

Bump the **"Last updated"** date on this page too; leave the **"Effective
date"** unchanged.

---

# PART 3 — `/support/`, optional

The support page is live and correct; this is a small consistency tidy, not a
fix. Do it only if it's cheap.

**Find** (search for: `uploaded anywhere`) — the answer under the FAQ heading
"Are my photos uploaded anywhere?". The middle sentence currently reads:

> Photos leave your phone only for the optional paid features you
> explicitly approve, batch by batch, and they are never stored on our
> servers.

**Replace that sentence with:**

> Photos leave your phone only for the optional paid Deep Analysis captions,
> and only after you have seen the exact photos and approved them — you can
> remove any of them or decline entirely. They are never stored on our servers.

Rationale: "features" (plural) implies a second upload feature that the shipping
app doesn't have, and the new wording matches what the app itself now says on
screen.

---

## Final check after deploying

- `/privacy/` and `/terms/` → **the words "Deep Vision" appear nowhere on
  either page.** That's the single fastest way to confirm parts 1 and 2 landed.
- `/privacy/` → **"hand-pick" appears nowhere.**
- `/privacy/` → contains the phrase **"presents them to you before anything is
  uploaded"** and the phrase **"Google's paid Gemini API service"**.
- `/privacy/` → the provider-links bullet list still sits directly under the
  "linked below" sentence.
- `/terms/` → section 6 still reads 6.1 · 6.2 · 6.3 with no subscription or
  "lifetime" language (this was already correct — just confirm nothing broke).
- All three pages still look like each other, and `/support/`, `/privacy/`,
  `/terms/` all still return HTTP 200.

---

## If Deep Vision is ever switched on

These edits deliberately remove every trace of Deep Vision (per-photo
commentary on up to 30 photos you pick yourself) from the legal pages, because
it isn't in the shipping app. If it's ever enabled, **this is the edit to
reverse** — the policy would then be under-disclosing an image upload, which is
much worse than the over-disclosure we're removing today.
