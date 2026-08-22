# AI Boxing Coach — marketing website

A fast, dependency-free static marketing site for the AI Boxing Coach app.
Dark sports-tech aesthetic, one electric-red brand accent, mobile-first, built
to the design brief.

## Run it

No build step. Open `index.html`, or serve the folder:

```bash
cd website
python3 -m http.server 8080     # then visit http://localhost:8080
```

## Files

| File | What |
| --- | --- |
| `index.html` | All content and sections (single page). |
| `styles.css` | The whole design system + responsive layout. |
| `main.js` | Demo loop, scroll reveals, count-ups, before/after slider, forms, analytics bus. |
| `assets/og.svg` | Social share image (see note below). |

## Design choices

- **Accent: electric red** (`--accent: #FF3B30`) — the closest fit to boxing.
  Change one CSS variable in `styles.css` `:root` to re-skin (e.g. acid green
  `#B4FF39` for a more technical feel, or electric blue `#2E7DFF` for AI/data).
  The site is otherwise monochrome by design.
- **Type:** Anton (heavy condensed display) + Inter (body), via Google Fonts
  with a system-font fallback if offline.
- **Sections** follow the brief's homepage order: hero → sequence → what it sees
  → how it works → mistake→correction → train anywhere → full-round → progress →
  free/pro → hardware → coaches → FAQ → final CTA → footer.

## ⚠️ Placeholders — replace before launch

The brief is emphatic that **real product footage does most of the selling**.
This build ships credible *stand-ins* so the layout and motion are real, with
obvious slots to drop footage into:

1. **Hero demo** (`.demo` block in `index.html`) — an animated
   record → track → detect → fix loop. Swap the whole `.demo` div for a vertical
   (9:19.5) autoplay/muted/looping `<video>` of the real product. Keep a poster
   image for performance.
2. **Before/after** (`.compare__viewer`) — replace the two `.compare__scene`
   panels with matched before/after clips of the same combination.
3. **Train anywhere** (`.place__media--home/bag/park`) — each shows a "Real
   footage slot" label; drop in living-room / heavy-bag / park clips or stills.
4. **Full-round & Progress** charts are labelled *Illustrative*. Wire to real
   data before removing that label — the brief says not to fake metrics.
5. **Social proof** was intentionally omitted (no fabricated testimonials).
   Add real "it caught X" quotes and a genuine beta count when you have them.

### Adding a hero video (example)

```html
<figure class="hero__demo" id="demo">
  <video class="demo" autoplay muted loop playsinline
         poster="assets/hero-poster.jpg" width="300">
    <source src="assets/hero.webm" type="video/webm">
    <source src="assets/hero.mp4"  type="video/mp4">
  </video>
</figure>
```

Provide mobile-specific, compressed encodes (WebM + MP4), a static poster, and
`loading="lazy"` on anything below the fold.

## Analytics

`main.js` has a provider-agnostic `track()` that pushes to `window.dataLayer`
and calls `gtag()` if present. Every `data-analytics="…"` element auto-fires a
`cta_click`; form submits fire `signup`. To connect a provider, add its snippet
to `index.html` and (if not GA) extend `track()` in one place.

Events already wired: hero/nav/plan/hardware/coach CTA clicks, demo-view (via
IntersectionObserver start), and beta/coach signups (with email domain only).

## SEO

Title, meta description, canonical, Open Graph/Twitter tags and
`SoftwareApplication` JSON-LD are in `<head>`. The structure leaves room for a
later `/blog` content section (common technique mistakes, how to improve guard,
shadowboxing drills, etc.) without reworking the homepage.

`assets/og.svg` is a share-card design — **export it to a 1200×630 PNG/JPG** and
point `og:image`/`twitter:image` at that, since some platforms don't render SVG
share images.

## Performance notes

- No JS framework; ~6 KB of vanilla JS, deferred.
- All motion respects `prefers-reduced-motion`.
- Fonts use `display=swap` + preconnect.
- Keep any added video small and mobile-encoded; lazy-load below-the-fold media.
