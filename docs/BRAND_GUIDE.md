# Lexi Brand Guide

Lexi's visual identity and design system. This is the **foundation** that every
Lexi surface adopts — the menu-bar item, first-run onboarding, Settings, and the
floating answer panel. It exists as new, self-contained files so it can be
adopted incrementally without rewriting existing screens:

- **Theme / tokens** — [`Sources/Lexi/DesignSystem/LexiTheme.swift`](../Sources/Lexi/DesignSystem/LexiTheme.swift)
- **Wordmark & brand mark** — [`Sources/Lexi/DesignSystem/LexiWordmark.swift`](../Sources/Lexi/DesignSystem/LexiWordmark.swift)
- **App icon generator** — [`scripts/generate_app_icon.py`](../scripts/generate_app_icon.py) → `assets/AppIcon.iconset/*` → `assets/Lexi.icns`

> **Status colors are unchanged.** The semantic system colors used across the app
> (green / blue / orange / purple / red) keep working exactly as before. The
> brand accent is *additive* — for selection, emphasis, links and glow — and is
> never a substitute for status meaning. `LexiTheme.Status` provides friendly
> aliases (`.success`, `.info`, `.warning`, `.error`, `.special`) that map onto
> those same system colors.

---

## 1. Research & rationale

We studied two reference products and translated what makes each feel like a
finished, human product (rather than a developer settings panel) into native
macOS design decisions.

### Poke — https://poke.com/
- **Warmth via "paper."** Soft cream, paper-textured backgrounds; sky→sand
  gradients. The page feels analog and inviting, not clinical.
- **Literary serif headlines.** Display copy is set in an elegant serif
  ("Meet Poke," "Poke fits into your life, not the other way around"),
  giving a human, editorial voice.
- **Conversational microcopy.** "a personality who keeps things as real as a
  friend," "as it becomes part of your day." Warm, first-person, a little
  cheeky.
- **Restrained accents.** Dark-ink pill buttons; blue reserved for links. Color
  comes from imagery, not loud UI chrome.
- **A friendly mark.** A simple palm-tree glyph in a dark badge — memorable,
  not corporate.

### Devin — https://app.devin.ai and https://devin.ai
- **Calm and confident.** Near-white canvas, generous whitespace, a clean
  geometric sans, near-black ink.
- **One restrained accent.** A single blue (~`#317CFF`) for emphasis and links;
  greys do the structural work. Status greens/reds appear only in product data.
- **Quiet structure.** Thin hairlines, soft shadows, calm rhythm — the product
  feels premium because it is *restrained*.

### Synthesis → Lexi
Lexi is a **friendly, magical reading companion**. It should feel *warm and
human* (Poke) while staying *calm and native* (Devin). We take:
- Poke's **warm paper surfaces**, **serif voice** for the wordmark, and
  **conversational tone**;
- Devin's **restraint, whitespace, and single confident accent**;
- and keep everything **native macOS** — SF fonts (including SF Serif, which is
  built in), vibrancy materials, continuous-corner squircles, SF Symbols.

### Mockups of both directions

| A — Aurora (chosen) | B — Clarity |
| --- | --- |
| ![Aurora](brand/direction_a_aurora.png) | ![Clarity](brand/direction_b_clarity.png) |

---

## 2. The two directions considered

### Direction A — **Aurora** *(chosen)*
Warm, characterful, Poke-leaning. Cream "paper" surfaces, warm ink text, a
signature **marigold → coral** *spark* accent with a soft **violet** glow, and a
**SF Serif** wordmark. Personality: warm, witty, encouraging — a clever friend
who loves explaining things.

- **Pros:** Distinctive and memorable; feels like a product with a soul; the
  serif wordmark + warm gradient give instant brand recognition; directly
  satisfies the mission's call for "warmth and personality over sterile
  enterprise styling."
- **Cons / risk:** Amber is low-contrast on white, so accent *text/links* need a
  deepened tone (handled via `Color.lexiAccentText`). Warmth must be applied
  tastefully so it stays native, not skeuomorphic.

### Direction B — **Clarity**
Calm, minimal, Devin-leaning. Near-white/graphite surfaces, a single restrained
**indigo** accent, a geometric lowercase **SF** wordmark, lots of whitespace.
Personality: precise, quiet, premium.

- **Pros:** Very safe and clean; trivially accessible contrast; minimal risk.
- **Cons:** Closer to the "settings-panel" energy we're trying to escape; less
  distinctive; doesn't differentiate Lexi from any other tasteful AI tool.

### Decision
**We chose A — Aurora.** The mission explicitly asks Lexi to feel "warm,
friendly, productized, effortless" and to "prefer warmth and personality over
sterile enterprise styling." Aurora delivers a memorable identity while the
implementation stays disciplined and native (SF type, system materials,
continuous corners). Clarity's restraint is folded into Aurora as *spacing and
hierarchy* discipline, so we get warmth **and** calm.

---

## 3. Palette

All colors resolve in light & dark via dynamic `NSColor` providers. Hex values
are sRGB.

### Brand accent (the "spark")
| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `Color.lexiAccent` | `#F2A03D` | `#FFB45C` | Selection, emphasis, focus, glow, fills |
| `Color.lexiAccentText` | `#B5650C` | `#FFC988` | **Accent text & links** (AA-compliant) |
| `Color.lexiCoral` | `#FF6B6B` | `#FF7E7E` | Warm end of gradients, playful highlights |
| `Color.lexiViolet` | `#7C5CFF` | `#9B82FF` | Grounding glow; gradient tail |
| `Color.lexiAccentWash` | `#F2A03D` @12% | `#FFB45C` @12% | Selected rows, hover fills, accent chips |

> Use `lexiAccent` for **fills/tints/glows**; use `lexiAccentText` whenever the
> accent carries **text** on a light surface (amber fails contrast as text).

### Surfaces (warm paper)
| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `Color.lexiPaper` | `#F7F2E9` | `#1A1714` | Primary window/background |
| `Color.lexiPaperElevated` | `#FFFDF8` | `#241F1A` | Cards, rows, fields |
| `Color.lexiPaperSunken` | `#EFE8D9` | `#141110` | Wells, code blocks, tracks |

### Ink (text) & lines
| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `Color.lexiInk` | `#1F1B16` | `#F3EEE6` | Primary text |
| `Color.lexiInkSecondary` | `#6B6258` | `#B8AE9F` | Secondary / supporting text |
| `Color.lexiInkTertiary` | `#9A9082` | `#847A6C` | Placeholders, footnote numerals |
| `Color.lexiHairline` | `#E7DECB` | `#3A332B` | Borders, separators |

### Gradients
- `LinearGradient.lexiAurora` — marigold → coral → violet (icon, hero washes).
- `LinearGradient.lexiWarm` — marigold → coral (buttons, small accents).

### Status (unchanged semantics)
`LexiTheme.Status.success/info/warning/error/special` → system
`green/blue/orange/red/purple`. Adopt the names for clarity; the look is
identical to today.

---

## 4. Typography

Native SF throughout. The **display** face is **SF Serif** — this is Lexi's
literary voice and is reserved for the wordmark and large hero titles.

| Token | Spec | Use |
| --- | --- | --- |
| `Font.lexiDisplay(_:)` | SF **Serif**, bold | Wordmark, hero titles |
| `Font.lexiTitle` | 22 semibold rounded | Largest UI title |
| `Font.lexiTitle2` | 17 semibold rounded | Section title |
| `Font.lexiHeadline` | 15 semibold | Row title / emphasis |
| `Font.lexiBody` | 13 regular | Body copy |
| `Font.lexiCallout` | 13 regular | Supporting body |
| `Font.lexiSubheadline` | 12 regular | Small label |
| `Font.lexiCaption` | 11 regular | Metadata, hints |
| `Font.lexiFootnote` | 10 regular | Source attributions |

Body and labels use SF Pro (default) and SF Rounded for titles to feel friendly;
serif is **only** for brand moments.

---

## 5. Spacing, radius, materials, motion

- **Spacing** (`LexiTheme.Spacing`): `xxs 2 · xs 4 · sm 8 · md 12 · lg 16 ·
  xl 24 · xxl 32 · xxxl 48` (8pt-based).
- **Radius** (`LexiTheme.Radius`): `xs 6 · sm 10 · md 14 · lg 20 · xl 28 ·
  pill`. Always `.continuous` style.
- **Materials** (`LexiTheme.Material`): `panel` (`.ultraThinMaterial`),
  `popover` (`.regularMaterial`), `card` (`.thinMaterial`).
- **Motion** (`LexiTheme.Motion`): `spring` (pill→panel, expansion),
  `quick` (hover), `reveal` (content/opacity).

Helpers: `.lexiCard()`, `.lexiAccented()`, `.lexiGlow()`, and the
`.lexiPrimary` button style.

---

## 6. Logo usage

- **`LexiBrandMark(size:glow:)`** — the gradient squircle badge with the white
  "L + spark" monogram. Use in headers, onboarding, and About.
- **`LexiWordmark(size:layout:)`** — "Lexi" in SF Serif with the marigold spark;
  `layout: .badgeAndWordmark` for the full lockup.
- **`LexiMonogram(size:color:)`** — flat single-color glyph for compact/tinted
  contexts.
- **`LexiBrand.statusItemImage(pointSize:)`** — a **template** `NSImage` of the
  monogram for the menu-bar status item (auto-tinted by macOS).

**Do:** keep clear space ≥ the spark diameter around the mark; place on calm
paper or solid surfaces. **Don't:** recolor the gradient, stretch the mark,
add drop shadows other than `lexiGlow`, or set the wordmark over busy imagery.

---

## 7. Per-surface adoption checklist

> These surfaces are owned by sibling sessions (A: `AppDelegate` & onboarding,
> B: `Settings`, C: answer panel). The snippets below are **copy-paste ready**
> for the coordinator to wire in during integration. Nothing here edits those
> files.

### Session A — Menu bar (`AppDelegate.swift`) & Onboarding

Replace the generic `textformat` status-item symbol:
```swift
// Before:
// item.button?.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Lexi")
// After:
item.button?.image = LexiBrand.statusItemImage()   // template image, auto-tinted
```

Welcome / onboarding header:
```swift
VStack(spacing: LexiTheme.Spacing.md) {
    LexiBrandMark(size: 72)
    LexiWordmark(size: 34)
    Text("Your friendly reading companion.")
        .font(.lexiBody)
        .foregroundStyle(Color.lexiInkSecondary)
}
.padding(LexiTheme.Spacing.xl)
.background(Color.lexiPaper)
```

Primary action button:
```swift
Button("Get started") { … }
    .buttonStyle(.lexiPrimary)
```

### Session B — Settings (`SettingsWindowController.swift`)

Header (replaces the `Image(systemName: "textformat")` + title block):
```swift
HStack(spacing: LexiTheme.Spacing.md) {
    LexiBrandMark(size: 44)
    VStack(alignment: .leading, spacing: LexiTheme.Spacing.xs) {
        LexiWordmark(size: 24)
        Text("Tune how Lexi reads alongside you.")
            .font(.lexiSubheadline)
            .foregroundStyle(Color.lexiInkSecondary)
    }
}
```

Section card + accent-tinted controls:
```swift
VStack(alignment: .leading, spacing: LexiTheme.Spacing.md) {
    Text("Shortcuts").font(.lexiHeadline)
    // …rows…
}
.lexiCard()

Toggle("Read answers aloud", isOn: $isReadAloudEnabled)
    .lexiAccented()
```

Status row colors stay semantic:
```swift
Image(systemName: status.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
    .foregroundStyle(status.isGranted ? LexiTheme.Status.success : LexiTheme.Status.warning)
```

### Session C — Answer panel (`RawCapturePanelController.swift`)

Panel surface + title:
```swift
VStack(alignment: .leading, spacing: LexiTheme.Spacing.md) {
    Text(term)
        .font(.lexiDisplay(20))          // serif brand voice for the headline
        .foregroundStyle(Color.lexiInk)
    Text(answer)
        .font(.lexiBody)
        .foregroundStyle(Color.lexiInk)
}
.padding(LexiTheme.Spacing.lg)
.background(LexiTheme.Material.panel, in: RoundedRectangle(cornerRadius: LexiTheme.Radius.xl, style: .continuous))
.overlay(
    RoundedRectangle(cornerRadius: LexiTheme.Radius.xl, style: .continuous)
        .strokeBorder(Color.lexiHairline, lineWidth: LexiTheme.hairline)
)
```

Selection / nested-lookup highlight (replace ad-hoc `Color.accentColor`):
```swift
.background(Color.lexiAccentWash, in: RoundedRectangle(cornerRadius: LexiTheme.Radius.sm, style: .continuous))
.overlay(
    RoundedRectangle(cornerRadius: LexiTheme.Radius.sm, style: .continuous)
        .strokeBorder(Color.lexiAccent.opacity(0.5), lineWidth: 1)
)
```

Keep the existing status dots semantic (green = ready, blue = streaming, orange
= warning, purple = nested) — optionally route them through
`LexiTheme.Status.*` for readability.

---

## 8. Regenerating the app icon

The PNG step is platform-independent; the `.icns` bundling is macOS-only.

```bash
# 1. Render every iconset PNG (any OS with Python 3.9+):
python3 scripts/generate_app_icon.py

# 2. Bundle the .icns (macOS only — part of the Xcode command line tools):
iconutil -c icns assets/AppIcon.iconset -o assets/Lexi.icns
```

> This session runs on Linux and cannot run `iconutil`, so
> `assets/AppIcon.iconset/*.png` are refreshed here, but **`assets/Lexi.icns`
> must be regenerated on macOS** with the command above before release.

---

## 9. Voice & tone

Warm, encouraging, plain-spoken — a knowledgeable friend, never a config panel.

- **Do:** "Your friendly reading companion." · "Highlight anything and I'll
  explain it." · "All set — try it anywhere."
- **Don't:** expose plumbing in user-facing copy ("proxy URL," "token,"
  "Railway," "AX/Accessibility API," byte/char counts, raw diagnostics). Keep
  that language in developer/advanced surfaces only.
- Prefer first person and second person ("I'll explain…", "you're all set").
- Short, confident sentences. A little delight is welcome; jargon is not.
