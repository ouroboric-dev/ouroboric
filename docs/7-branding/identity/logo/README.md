---
title: Logo
status: accepted
date: 2026-10-12
related: [../README.md, concepts/README.md, ../../../../TRADEMARKS.md]
style: guide
---

# Logo

The Ouroboric logo is an ouroboros: a snake of carved, interlocking scales biting its own tail. The
tail is International Orange, and it carries a gate. The wordmark is `OUROBORIC.DEV` in Cinzel.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="ouroboric-logo-horizontal-dark.svg">
  <img alt="Ouroboric logo: a carved snake biting its orange tail, next to the wordmark OUROBORIC.DEV" src="ouroboric-logo-horizontal.svg" width="480">
</picture>

## Files

| File | Use |
| --- | --- |
| `ouroboric-logo-horizontal.svg`, `-dark.svg` | the full logo: icon and wordmark side by side |
| `ouroboric-icon.svg`, `-dark.svg` | the icon alone, from 48 px up |
| `ouroboric-wordmark.svg`, `-dark.svg` | the wordmark alone |
| `ouroboric-banner-dark.svg` | a 1280×320 banner, always dark: the logo on Midnight with the runic ornament, for profile pages and README headers |
| `favicon.svg` | browser tabs and bookmarks; switches to the dark version by itself |
| `favicon.ico` | older browsers: 16, 32 and 48 px, each drawn at its own size |
| `apple-touch-icon.png` | 180 px, for iOS home screens |
| `icon-192.png`, `icon-512.png` | web app manifests and avatars, such as the GitHub organisation |

The light files have a Midnight (`#0B0D12`) snake for light backgrounds. The `-dark` files have a
light (`#EDEFF3`) snake for dark backgrounds. The tail is International Orange (`#FF4F00`) in both.
The PNG icons show the full icon, light snake on Midnight, inside the central 80% so that platforms
can round or mask the corners.

To add the favicon to a page:

```html
<link rel="icon" href="/favicon.ico" sizes="48x48">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
```

## Rules

1. **Use the files as they are.** Don't recolour, rotate, stretch, outline or add effects. Don't
   rebuild the wordmark from the font; use the outlined files.
2. **Match the background.** Use the light files on light backgrounds and the `-dark` files on dark
   ones. On a photo or a busy background, put the logo on a solid `bg` panel from the tokens.
3. **The tail stays orange.** It is the one accent in the logo, like the accent in the palette.
4. **Leave clear space** around the logo of at least a quarter of the icon's height on every side.
5. **Respect minimum sizes.** The icon from 48 px; below that, use the favicon. The horizontal logo
   from 36 px tall, where the wordmark's capitals are still 10 px.
6. **The favicon is a simplified icon** for 48 px and below. It keeps the logo's head, eye and gated
   tail in the same places, with three scales and wide gaps so it reads at 16 px. Don't use it as the
   logo at larger sizes.

## How it was made

- **Icon:** the founder's artwork, traced with potrace 1.16 and recoloured to the palette. The light
  and dark files use the same shapes.
- **Wordmark:** Cinzel at weight 800 from the Google Fonts repository (commit `3dd78844`), shaped with
  HarfBuzz so the font's own kerning applies, with tracking of +40 per 1000, then converted to
  outlines. No font is needed to show it. Cinzel's SIL Open Font License allows using its letters in a
  logo; the outlines are artwork, not a font.
- **Favicon:** drawn on a 32-unit grid. The head, eye and tail positions were measured around the
  ring of the icon. The tail and its gate come from the founder's favicon drawing. Gaps are 2 units
  between scales (1 px at 16 px) and 0.8 units around the head, cut as even offsets of its outline so
  the pieces interlock.
- **Banner:** the dark horizontal logo with `ᛟᚢᚱᛟᛒᛟᚱᛁᚲ` (OUROBORIC in Elder Futhark) beneath it, set in
  Noto Sans Runic from the Google Fonts repository (commit `8b0a1d0f`) and converted to outlines. It
  carries its own Midnight background, so it looks the same on light and dark pages.
- **Raster files:** rendered by headless Chrome and packed with Pillow.

The proposals and favicon explorations that led here are in [concepts](concepts/README.md).

## Licence

The logo files are trademarks, not part of the documentation licence: they are covered by
[`TRADEMARKS.md`](../../../../TRADEMARKS.md) and `LICENSES/LicenseRef-Ouroboric-Trademark.txt`, not
CC BY 4.0. You may show them unmodified to refer to Ouroboric and its projects.
