# Connectible Logo Generation Prompt

## For AI Image Generators (Midjourney, DALL-E 3, Stable Diffusion, Flux, etc.)

---

### Primary Prompt (Copy-Paste Ready)

> **Minimalist monochrome app icon for "Connectible" — a cross-device synchronization tool (phone ↔ computer) over LAN, TLS 1.3 encrypted, no cloud. Design language: strict black/grey/white only, zero color accents. Symbol: two abstract devices (one desktop monitor silhouette, one smartphone silhouette) connected by a single centered encrypted link — represented as a subtle lock shackle forming the negative space between them, or a clean bidirectional arrow/pipe with a tiny lock glyph. Style: geometric, precise, 45° construction grid, consistent stroke weight (2px equivalent at 1024px). Background: pure black (#000000) for OLED-friendly mobile, also works on charcoal (#08080A) and graphite (#0F0F13). No gradients, no shadows, no glows, no 3D, no perspective. Vector-flat, iconographic clarity at 32×32px (notification badge) and 1024×1024px (store). Aspect ratio 1:1. Safe area 85% centered. Export: SVG + PNG set (32, 48, 64, 96, 128, 256, 512, 1024).**

---

### Variations to Try

#### Variant A: "Link Lock" (Recommended)
> Two minimal device outlines (monitor rect + phone rect) facing each other, gap between them forms a **lock shackle** — the negative space *is* the lock. Single continuous stroke weight. Extreme reduction.

#### Variant B: "Encrypted Pipe"
> Devices on left/right, center = **horizontal pill capsule** with a **tiny lock** inside (3×3px at 1024). Capsule ends touch device edges. Represents SyncStream gRPC tunnel.

#### Variant C: "Radar Ping" (Brand-mark only, no devices)
> Three concentric circles (sonar rings) centered, **single dot** at 45° radius (the "device found" blip). One clean gap in the outer ring at 135° = "secure gap". Works as favicon / notification icon alone.

#### Variant D: "Monogram Mark"
> Stylized **"C"** built from two mirrored **brackets** `⟨ ⟩` interlocking like chain links. The negative space between brackets forms a **keyhole**. Pure typography-based symbol.

---

### Negative Prompt (What to Avoid)
> color, blue, purple, green, gradient, shadow, glow, 3d, perspective, photorealistic, sketch, hand-drawn, watercolor, illustration, texture, noise, grain, drop shadow, outer glow, bevel, emboss, chrome, metal, glassmorphism, neumorphism, intricate detail, thin lines that vanish at 32px, complex shapes, text, letters, wordmark, badge, border, frame, rounded square container, apple/ios/android chrome, decorative, ornamental, organic curves, asymmetric, busy, cluttered

---

### Technical Specs for Delivery

| Asset | Size | Use Case |
|-------|------|----------|
| `logo.svg` | Vector | Source of truth, all scaling |
| `icon-32.png` | 32×32 | Favicon, notification badge |
| `icon-48.png` | 48×48 | Windows taskbar |
| `icon-64.png` | 64×64 | macOS dock (small) |
| `icon-96.png` | 96×96 | Android launcher (mdpi) |
| `icon-128.png` | 128×128 | Chrome Web Store |
| `icon-256.png` | 256×256 | macOS dock, Windows tile |
| `icon-512.png` | 512×512 | Play Store / App Store |
| `icon-1024.png` | 1024×1024 | Marketing, GitHub repo |

**Safe zone:** Keep all critical geometry inside 85% circle (15% padding). No content touches edges.

**Color tokens (for reference):**
- Canvas (Onyx): `#000000`
- Canvas (Charcoal): `#08080A`
- Surface: `#101012`
- Ink (primary): `#F2F2F3`
- Paper (accent): `#FAFAFA`

The logo must work **reversed** (white on black) and **single-color** (ink on surface) without modification.

---

### Prompt for Recraft / Vectorizer.ai (if you get raster first)

> "Vectorize this icon to clean SVG. Single stroke weight. No fills — only strokes and compound paths. Merge overlapping shapes. Simplify to < 50 nodes total. Output: pure black paths on transparent background."

---

### Quick Test Checklist (after generation)

- [ ] Recognizable at **32×32** (blurry eyes test)
- [ ] Works on **pure black** (#000) background
- [ ] Works on **Charcoal** (#08080A) background
- [ ] Works **white-on-black** (inverted)
- [ ] Works **single-color** (e.g., `--ink-muted` #A2A2AB)
- [ ] No thin lines < 2px at 1024px (disappear at 32px)
- [ ] Balanced optical weight (not leaning left/right)
- [ ] No hidden rastor artifacts (check SVG in Figma/Illustrator)
- [ ] Exports clean from Figma → SVG → pngcrush / svgo optimized

---

### Brand Rationale (for the designer/AI)

> **Connectible** = "Connect" + "able" (capability). The mark should feel like **permission granted** — a secure handshake that *enables* capabilities (clipboard, files, input, notifications). The lock isn't a barrier; it's the *enabler*. Visual metaphor: **the connection itself is the security**.