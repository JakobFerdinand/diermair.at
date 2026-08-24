# Gallery Redesign Plan

## Goal

Turn the current CSS-only marquee in `src/components/Gallery.astro` into a
proper showcase for the company's work: a large automatic slideshow as the
visual centerpiece, a calmer scrolling thumbnail strip, and a full lightbox
for viewing images in detail and navigating between them — with zero new
dependencies.

## Current state

- `src/components/Gallery.astro` is a pure-CSS horizontal marquee: the 64
  images from `src/images/gallerie/*.jpeg` are duplicated (`[...images,
  ...images]`, 128 `<img>` nodes) and scrolled via a `translateX(-50%)`
  keyframe animation (`gallery-scroll`, 180s).
- Images are rendered with `astro:assets` `<Image>` at 280px width.
- No interactivity exists anywhere else in the project to build on except
  the bundled `<script>` pattern in `Navbar.astro`; no lightbox/dialog code
  anywhere.
- Only usage: last section on `src/pages/index.astro`. The navbar links to
  `/​#gallery` (`Navbar.astro:14`), so the `id="gallery"` anchor must be kept.

## Decisions

| Question | Decision |
| --- | --- |
| Gallery concept | Hero slideshow + thumbnail strip below it + lightbox |
| Where autoplay lives | On-page hero (lightbox has no autoplay of its own) |
| Implementation | Zero-dependency vanilla TS; native `<dialog>` lightbox |
| Hero slide count | 8 featured images |

## Target structure

```
<section id="gallery">                        <!-- anchor kept -->
  <h2>Einblicke in meine Arbeit</h2>
  ├─ Hero slideshow   ← big auto-advancing crossfade carousel (~8 slides),
  │                      arrows + clickable dots + "3 / 8" counter,
  │                      click on slide opens the lightbox at that index
  ├─ Thumbnail strip  ← slower version of today's marquee, pauses on hover,
  │                      every thumb is a <button> opening the lightbox
  └─ <dialog>         ← lightbox: full-size image, prev/next buttons,
                         swipe, keyboard (←/→/Esc), counter,
                         backdrop-click close
</section>
```

Single component, single file touched: `src/components/Gallery.astro`.

## Implementation details

### Frontmatter

- Keep the eager `import.meta.glob` over `../images/gallerie/*.jpeg`, but
  sort entries explicitly so the lightbox index matches the strip order
  deterministically.
- Featured hero images: evenly-spaced sample of the sorted list (every
  N-th image, N = ceil(total / 8)) so the hero shows variety without manual
  curation; controlled via a `FEATURED_COUNT = 8` const.

### Hero slideshow markup

- Slides absolutely stacked inside one fixed-aspect container; `.active`
  class toggles opacity for a ~0.8s crossfade.
- Slide 1: `loading="eager"` + `fetchpriority="high"`; remaining slides
  `loading="lazy" decoding="async"`.
- Prev/next buttons use `@lucide/astro` icons (`ChevronLeft`,
  `ChevronRight`) — already an existing dependency.
- Dots are `<button>`s with `aria-current="true"` on the active one; the
  counter ("3 / 8") is an `aria-live="polite"` region.
- Container gets `aria-roledescription="carousel"` and a German
  `aria-label`.

### Thumbnail strip

- Marquee kept but subtler: longer duration than today's 180s and
  `animation-play-state: paused` on hover/focus-within.
- Thumbs re-optimized smaller (~200px wide, `quality="mid"`).
- Each thumb wrapped in `<button aria-label="Bild N vergrößern">`.

### Lightbox

- Native `<dialog>` styled dark via `::backdrop`; renders a large variant
  of the current image (~1600px wide, higher quality than thumbs).
- Prev/next/close buttons (lucide icons); pointer-event swipe with a ~50px
  threshold; click on the backdrop itself closes; body scroll locked while
  open (native dialog does not lock scroll).
- Focus trap and focus restore come free from `<dialog>`; Escape closes
  natively; ArrowLeft/ArrowRight handled by our script.

### Bundled `<script>` (TypeScript, Navbar.astro pattern)

- One shared state `currentIndex` across all images; `show(i)` updates
  hero, dots, counter and (when open) lightbox together.
- Autoplay advances every ~5 s and auto-pauses when:
  - the hero is hovered or contains focus,
  - the tab is hidden (`visibilitychange`),
  - the section is scrolled out of view (`IntersectionObserver`),
  - `prefers-reduced-motion` is set (autoplay disabled entirely; the strip
    animation is also disabled via a CSS media query).

### Accessibility & polish

- German labels throughout: "Vorheriges Bild", "Nächstes Bild",
  "Schließen", "Bild N vergrößern".
- Alt texts stay generic (`Galeriebild N`) since no captions exist;
  real captions remain a future enhancement.
- Visible focus styles on all controls; reuse design tokens
  (`--green-color`, `--gray-bg`, 1rem radius, soft shadow) from
  `src/styles/global.css`.

## Verification

- [x] `npm run build` passes (includes `astro check` type checking)
- [ ] `npm run dev`: hero autoplays, pauses on hover/hidden-tab/offscreen
- [ ] Arrows, dots and counter work; clicking a slide/thumb opens the
      lightbox at the right index
- [ ] Lightbox: prev/next, swipe, backdrop-click close, Esc close,
      arrow-key navigation
- [ ] Reduced motion disables autoplay and the strip animation
- [ ] Mobile layout checked at the 639px breakpoint
