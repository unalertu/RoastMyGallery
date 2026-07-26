# roastmygallery.unlertu.workers.dev

Source for the app's public website — the privacy policy, terms, and support
page that App Store Connect links to.

It is an **assets-only Cloudflare Worker**: there is no server code, just static
files under `public/`. Every route is a file.

```
public/
  index.html                              →  /
  privacy/index.html                      →  /privacy/
  terms/index.html                        →  /terms/
  support/index.html                      →  /support/
  assets/style.css                        →  shared stylesheet for all pages
  robots.txt
  .well-known/apple-app-site-association  →  iOS universal links
  _headers                                →  forces JSON content-type on the AASA file
```

## Editing

```sh
npm install          # once
npx wrangler dev     # local preview on http://localhost:8787
npx wrangler deploy  # publish
npx wrangler rollback  # undo the last deploy
```

## Two things that will bite you

**A deploy replaces the entire asset manifest.** Anything not in `public/` is
deleted from the live site. There are currently **8 files** — if `wrangler deploy`
reports uploading a set that implies fewer, stop and check before confirming.

**`wrangler init --from-dash roastmygallery` does not work.** It silently
produces an empty "Hello World" scaffold rather than this site, because the
content lives in the assets, not in a Worker script, and `--from-dash` only
downloads scripts. Deploying that scaffold would wipe the site. This directory
exists so nobody needs `--from-dash` again — it was reconstructed from the live
pages on 2026-07-26 after the original project directory was lost.

## Keeping legal text in sync

`legal/privacy-policy.md` and `legal/terms-of-service.md` in the repo root are
the markdown counterparts of `public/privacy/` and `public/terms/`. They are
maintained by hand alongside these pages — when you change one, change the other,
or the app's in-repo record of its own policy drifts from what users actually see.
