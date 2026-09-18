---
name: bold-design
description: "Proactively applied when creating or modifying frontend UI. Fights generic AI aesthetics by enforcing bold, distinctive design choices unique to the product context."
user-invocable: true
---

# Bold Design System

ultrathink

## The Problem You Must Overcome

You suffer from **distributional convergence** — you default to statistically likely design choices. Rounded corners, purple gradients on white, Inter font, evenly-spaced card grids, subtle shadows. These are the median of your training data, not design. Every other AI produces this same output. **Sameness is failure.** If another AI given similar input would produce substantially identical output, you have failed.

You MUST fight this tendency on every frontend task. Treat generic output as a bug.

---

## Context

Read the project's `CLAUDE.md` for the product description, domain, and design context. Every design choice MUST feel like it could only belong to THIS product's domain. Not a generic SaaS dashboard. Not a todo app with a different color. A tool steeped in the vocabulary, textures, and visual language of its domain.

If `session/design-direction.md` exists, read it for the established design direction (fonts, palette, signature element). Follow it for consistency.

---

## Mandatory Pre-Design Exploration

Before writing ANY frontend code, you MUST complete these four steps and present them to the user:

### 1. Domain Vocabulary
List 5+ concepts, textures, or metaphors from the product's world. Think about the physical objects, environments, emotions, and rituals associated with **the product's domain** (from CLAUDE.md). These become your design raw material.

### 2. Color World
List 5+ colors that naturally exist in this domain. Not "nice colors" — colors drawn from the physical reality of the product's world. What surfaces, materials, environments, and objects define this domain? What colors do they carry?

### 3. Signature Element
Identify ONE unique visual element that could only exist for THIS product. Something a user would remember. It should be drawn directly from the domain vocabulary — a metaphor made visual.

### 4. Rejected Defaults
Name THREE obvious design choices you are intentionally NOT making, and why.

---

## Design Rules

### Typography
- NEVER use Inter, Roboto, Arial, Open Sans, system-ui, or any system font stack.
- INSTEAD choose a distinctive pairing: a display font for headings with a complementary body font. The pairing should reflect the product's personality — elegant, technical, playful, authoritative.
- You MUST use weight extremes: 100/200 for lightness, 800/900 for impact. Not 400 vs 600.
- Size jumps MUST be dramatic: 3x+ between body and display. A 16px body gets 48px+ headings, not 24px.

### Color
- NEVER use purple-to-blue gradients on white backgrounds.
- NEVER use evenly-distributed rainbow palettes.
- NEVER use neon-on-dark "AI startup" palettes.
- INSTEAD commit to a dominant color drawn from the domain color world. One color owns 60%+ of the palette. Sharp accents provide contrast, not variety.
- You MUST define all colors as CSS custom properties on `:root`.
- You MUST ensure WCAG AA contrast ratios (4.5:1 for text, 3:1 for large text/UI).

### Layout
- NEVER use predictable three-card grids with equal spacing.
- NEVER nest cards inside cards inside cards.
- NEVER use cookie-cutter symmetric layouts where every section mirrors the last.
- INSTEAD use asymmetry, overlap, diagonal flow, grid-breaking hero elements, or generous negative space.
- You MUST use CSS Grid or intentional layout — not just flexbox-with-gap for everything.
- Controlled density and open breathing room are both valid — but uniformity is not.

### Backgrounds and Atmosphere
- NEVER default to flat solid-color backgrounds (#fff, #f5f5f5, #1a1a2e).
- INSTEAD create atmosphere: gradient meshes, subtle noise textures, geometric patterns, layered transparencies, or contextual effects that match the product's aesthetic.
- Texture MUST feel intentional and domain-appropriate — not decorative noise.

### Motion and Interaction
- NEVER scatter random hover effects, bouncing icons, or gratuitous micro-interactions everywhere.
- INSTEAD invest in ONE well-orchestrated moment: a staggered page load sequence, a single delightful transition on the primary action, or a meaningful state change animation.
- That one moment MUST be polished. Everything else stays calm.

### Components
- NEVER use default browser form controls unstyled.
- NEVER use generic icon libraries without curation (no FontAwesome dumps).
- INSTEAD style every interactive element to belong to the design system. Buttons, inputs, selects — all MUST share the typographic and color DNA of the page.

---

## Quality Gates

Before finishing ANY frontend work, you MUST run these four checks:

### The AI Slop Test
"If you showed this to someone and said 'AI made this,' would they immediately believe you?"
If yes — redesign. Identify which elements triggered that reaction and replace them.

### The Swap Test
Could you swap the typeface, color palette, or layout structure onto a different product without anyone noticing?
If yes — it is too generic. The design MUST be inseparable from the product context.

### The Squint Test
Blur the page (or squint). Is the visual hierarchy still clear? Can you tell what is primary, secondary, and tertiary?
If not — the hierarchy is too flat. Increase contrast in size, weight, or color.

### The Signature Test
Can you point to the product-specific signature element from the pre-design exploration?
If it is missing — add it. Every page MUST carry at least one element that anchors it to this product's world.

---

## Accessibility Requirements

Bold design does NOT mean inaccessible design. You MUST maintain:

- WCAG AA contrast ratios on all text and interactive elements
- Proper `aria-label` attributes on non-text interactive elements
- Full keyboard navigation (visible focus states that match the design system, not browser defaults)
- Semantic HTML structure (headings, landmarks, lists)
- Respect for `prefers-reduced-motion` — your signature animation MUST have a reduced-motion fallback

---

## Complexity Matching

Match code complexity to the design vision:

- **Maximalist design** demands elaborate, layered CSS — multiple gradients, pseudo-elements for texture, complex grid layouts. Write the code the design requires.
- **Minimalist design** demands surgical precision — every pixel intentional, every spacing value deliberate, every color earned. Less code, more restraint.
- In both cases, the output MUST feel authored, not generated.

---

## Landing Pages

If your task involves building a landing page or homepage, read `.claude/skills/bold-design/landing-page-patterns.md` before writing any code. It contains structural and visual patterns for consumer SaaS landing pages — hero layout, product preview, features sections, testimonials, CTAs, and anti-patterns to avoid.

Not every project needs a landing page — only read this if your task requires one.
