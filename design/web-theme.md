# Roast My Gallery — Web Theme Brief

This is the design system for the **Roast My Gallery** iOS app, translated for
the **website** (privacy policy, terms, landing page). Give this to the model
building the site so the web matches the app.

The source of truth in the app is `RoastMyGallery/App/DesignSystem.swift`
(`Theme`). Everything below is derived directly from it.

---

## 1. Design philosophy

- **Minimal & pastel.** Warm cream backgrounds, soft terracotta accent, dusty
  pastel supporting colors. Nothing loud.
- **Calm, no dark patterns.** No urgency, no aggressive CTAs, no flashing, no
  countdowns. Gentle motion only.
- **Light mode only.** The app forces light mode; the site should be a warm,
  light design too (no dark theme needed — but if you add one, keep it soft).
- **Rounded, friendly type.** Apple's rounded system font. On the web, use a
  rounded/geometric system stack (see Typography).
- **One soft shadow, generous spacing, large rounded corners (20px cards).**

---

## 2. Color tokens

| Token | Hex | Role |
|---|---|---|
| `background` | `#FAF6F0` | Warm cream — every page background |
| `surface` | `#FFFFFF` | Cards / elevated surfaces |
| `accent` | `#C97B63` | Muted terracotta — the single primary-action accent |
| `accent-soft` | `#F3DED7` | Terracotta wash — soft fills, track backgrounds, secondary buttons |
| `text-primary` | `#3A3532` | Soft charcoal — headings and body |
| `text-secondary` | `#8A817C` | Warm grey — captions, secondary text |
| `dusty-rose` | `#E8C4BC` | Supporting pastel (Roast persona tint) |
| `sage` | `#C3D1BA` | Supporting pastel |
| `powder-blue` | `#C0D2DE` | Supporting pastel (Analyst persona tint) |
| `cream` | `#F4EDE3` | Slightly deeper cream — quiet cards / fills |
| `sage-soft` | `#E2EBDA` | Sage wash (chips) |
| `sage-deep` | `#5E7C49` | Deep sage — text on sage wash |
| `danger` | `#B3564F` | Muted brick — errors (visible, not alarming) |

**Chart / data colors** (fixed order — never reassign by rank; always label
each mark directly):

| Token | Hex |
|---|---|
| `chart-rose` | `#C96F52` |
| `chart-blue` | `#3D7FB8` |
| `chart-sage` | `#6B9C4A` |

**Card cycle** (rotate fills for stat cards, in this order): `dusty-rose` →
`sage` → `powder-blue` → `cream`.

---

## 3. Typography

- **Family:** Apple rounded system font. Web stack:
  `ui-rounded, "SF Pro Rounded", "Nunito", "Quicksand", system-ui, -apple-system, sans-serif`.
  (If you want a hosted rounded font for non-Apple devices, **Nunito** or
  **Quicksand** are close, friendly matches.)
- **Weights:** semibold = 600, medium = 500, regular = 400, light = 300.
- Sizes below are in px (1:1 from the app's points).

| Style | Size | Weight | Use |
|---|---|---|---|
| Display | 34px | 600 | Hero / page title |
| Title | 24px | 600 | Section headings |
| Headline | 17px | 600 | Card titles, buttons |
| Body | 17px | 300 (light) | Paragraph text |
| Caption | 13px | 400 | Secondary / fine print |
| Label | 12px | 500 | Small UPPERCASE labels above values (add `letter-spacing: 1.5px; text-transform: uppercase`) |

- **Body line-height:** ~1.35 (the app uses 6px line spacing on 17px body).
- Body text color is `text-secondary` for supporting copy, `text-primary` for
  primary reading text and headings.

---

## 4. Spacing scale

Use these steps only (px): `xs 4` · `s 8` · `m 16` · `l 24` · `xl 32` ·
`xxl 48`. Default page/card padding is `m` (16) to `l` (24).

## 5. Corner radii

`small 12` · `button 16` · `card 20` (px).

## 6. Elevation (the one shadow)

Exactly one shadow across the whole design:
`box-shadow: 0 4px 12px rgba(0, 0, 0, 0.06);`

## 7. Motion

Gentle, never bouncy: `transition: all 0.3s ease-in-out;`
Press feedback = drop opacity to `0.85`. Disabled = opacity `0.35`.

---

## 8. Components

**Primary button** — terracotta fill, cream text:
- background `accent` (#C97B63), text color `background` (#FAF6F0)
- radius `button` (16px), vertical padding `m` (16px), full width in narrow layouts
- disabled: background opacity 0.35 · pressed/hover: opacity 0.85

**Secondary ("soft") button** — soft wash, accent text:
- background `accent-soft` (#F3DED7), text `accent` (#C97B63), same radius/padding

**Quiet button** — plain text link:
- text `text-secondary`, caption size (13px), no background; pressed opacity 0.6

**Card:**
- background `surface` (#FFFFFF), radius `card` (20px), padding `m` (16px),
  the one soft shadow. A quieter card variant uses `cream` (#F4EDE3) as fill.

---

## 9. Ready-to-paste CSS

```css
:root {
  /* Colors */
  --color-background: #FAF6F0;
  --color-surface: #FFFFFF;
  --color-accent: #C97B63;
  --color-accent-soft: #F3DED7;
  --color-text-primary: #3A3532;
  --color-text-secondary: #8A817C;
  --color-dusty-rose: #E8C4BC;
  --color-sage: #C3D1BA;
  --color-powder-blue: #C0D2DE;
  --color-cream: #F4EDE3;
  --color-sage-soft: #E2EBDA;
  --color-sage-deep: #5E7C49;
  --color-danger: #B3564F;
  --color-chart-rose: #C96F52;
  --color-chart-blue: #3D7FB8;
  --color-chart-sage: #6B9C4A;

  /* Typography */
  --font-family: ui-rounded, "SF Pro Rounded", "Nunito", "Quicksand",
                 system-ui, -apple-system, sans-serif;
  --font-weight-semibold: 600;
  --font-weight-medium: 500;
  --font-weight-regular: 400;
  --font-weight-light: 300;
  --text-display: 34px;
  --text-title: 24px;
  --text-headline: 17px;
  --text-body: 17px;
  --text-caption: 13px;
  --text-label: 12px;
  --line-height-body: 1.35;

  /* Spacing */
  --space-xs: 4px;
  --space-s: 8px;
  --space-m: 16px;
  --space-l: 24px;
  --space-xl: 32px;
  --space-xxl: 48px;

  /* Radius */
  --radius-small: 12px;
  --radius-button: 16px;
  --radius-card: 20px;

  /* Elevation & motion */
  --shadow-soft: 0 4px 12px rgba(0, 0, 0, 0.06);
  --motion: 0.3s ease-in-out;
}

body {
  background: var(--color-background);
  color: var(--color-text-primary);
  font-family: var(--font-family);
  font-size: var(--text-body);
  font-weight: var(--font-weight-light);
  line-height: var(--line-height-body);
}

h1 { font-size: var(--text-display); font-weight: var(--font-weight-semibold); }
h2 { font-size: var(--text-title);   font-weight: var(--font-weight-semibold); }
h3 { font-size: var(--text-headline); font-weight: var(--font-weight-semibold); }

.card {
  background: var(--color-surface);
  border-radius: var(--radius-card);
  padding: var(--space-m);
  box-shadow: var(--shadow-soft);
}

.btn-primary {
  background: var(--color-accent);
  color: var(--color-background);
  border: none;
  border-radius: var(--radius-button);
  padding: var(--space-m) var(--space-l);
  font: var(--font-weight-semibold) var(--text-headline) var(--font-family);
  transition: opacity var(--motion);
}
.btn-primary:hover  { opacity: 0.85; }
.btn-primary:disabled { opacity: 0.35; }

.btn-soft {
  background: var(--color-accent-soft);
  color: var(--color-accent);
  border: none;
  border-radius: var(--radius-button);
  padding: var(--space-m) var(--space-l);
  font: var(--font-weight-semibold) var(--text-headline) var(--font-family);
  transition: opacity var(--motion);
}

.text-secondary { color: var(--color-text-secondary); }

.label {
  font-size: var(--text-label);
  font-weight: var(--font-weight-medium);
  letter-spacing: 1.5px;
  text-transform: uppercase;
  color: var(--color-text-secondary);
}
```

---

## 10. Quick brief for the site builder

> Warm, calm, pastel. Cream (#FAF6F0) background everywhere, white cards with
> 20px corners and one soft shadow. Single terracotta accent (#C97B63) for
> primary buttons (cream text). Rounded, friendly font (SF Pro Rounded /
> Nunito). Generous spacing, gentle 0.3s ease-in-out transitions, no dark
> patterns, light mode. Supporting pastels — dusty rose, sage, powder blue —
> for accents and illustrations. Keep it soft and unhurried.
