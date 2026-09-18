# Landing Page Design Principles for Consumer SaaS Products

Reference patterns for building landing pages. Read this ONLY when your task involves building a landing page or homepage.

## Navigation

- Logo left, nav links center, auth top-right. Sign-in/sign-up should be ambient — a small button in the corner, not the focus of the page. The page sells the product; auth is just the door.

## Hero Section

- Never centered-text-only. Use a split or asymmetric layout — headline on one side, a strong visual on the other. Centered text with two buttons underneath is the default template look.
- The headline is the star. Large display font, one line that captures the outcome (not the technology). The subtitle is one sentence max.
- The CTA is small and confident. A single warm button, not two competing buttons. "Get Started Free" is enough. If the page does its job, they'll click it.
- Visual depth in the background. Layered gradients, subtle textures, decorative elements (SVG patterns, domain-appropriate motifs). The hero should feel rich, not flat.

## Product Preview

- Show the product. Below or beside the hero, render a styled mockup of the actual UI. This is the single most persuasive element on the page — users need to see what they're getting before they sign up. CSS-rendered mockups are crisper than screenshots and scale to any resolution. Frame it in a browser/device frame with a subtle tilt and shadow.

## Social Proof

- Subtle trust strip below the hero. "Trusted by X users" with overlapping avatar circles or a star rating. Not attention-grabbing — just quietly builds confidence. Even placeholder numbers work early on; replace with real data later.

## Features

- Not flat cards in a grid. Use alternating left/right sections — text on one side, a visual illustration on the other. Each feature gets its own mini-visual showing that feature in action. Shift the background color slightly between sections so they feel distinct.
- Headlines describe outcomes, not capabilities. "Drag, Drop, Done" not "Drag-and-Drop Functionality." The user cares about what it feels like, not what it does technically.

## How It Works

- 3 steps, visually connected. Large step numbers in an elegant font, connected by a flowing line or curve — not straight dots. Stagger the steps vertically to create visual rhythm. Each step: number, title, one-sentence description.

## Testimonials

- Genuine-sounding quotes with names and locations. First name + last initial, city + state. 2-3 sentences each. Each testimonial should highlight a different pain point the product solves. Use placeholder testimonials early (clearly marked internally) and replace with real ones as they come in. Staggered card layout or horizontal carousel — not three equal rectangles.

## Final CTA

- A warm closing section. Gradient background, emotional headline, one CTA button. This catches anyone who scrolled the whole page and is now convinced.

## Footer

- Minimal. Logo, copyright, policy links. Nothing heavy.

## Visual Language

- Match the target audience's world, not the developer's. The landing page's visual language — typography, color, texture, motifs — must come from the user's domain. Research what the target audience already considers beautiful and premium in their context. Don't default to generic SaaS blue.
- Define 1-2 signature visual elements unique to the product. These are decorative motifs that appear across sections and tie the page together — not stock icons. Derive them from the product itself (what shapes or patterns does the actual UI use?).
- Color palette and typography are project-specific inputs, not defaults. The design direction document should specify these before the landing page is built. The landing page task should reference that document, not invent its own palette.
- Generous whitespace that feels luxurious, not empty. Whitespace is intentional — it gives each section room to breathe.
- Depth through layering. Overlapping elements, subtle shadows, gradient transitions between sections. Flat pages feel cheap.
- Scroll animations. Subtle fade-in and slide-up on scroll via IntersectionObserver. Elements should reveal themselves as the user scrolls — the page should feel alive, not static.

## Copy Rules

- Lead with outcomes and emotions, not features and technology.
- If the product uses AI, don't say "AI-powered." Describe what the user experiences: "describe your venue and watch it come to life" not "AI generates your layout."
- Short punchy headlines. Explanatory text is secondary and smaller.
- Speak to the user's identity, not their task. "For couples who want effortless elegance" not "A tool for planning seating charts."

## Anti-Patterns to Avoid

- Centered hero with two equal-weight CTA buttons
- Flat card grid for features (three boxes in a row)
- Three equal-width testimonial rectangles
- Sign-up form as the hero's main element
- Stock photography as the visual hook
- Generic icon + headline + paragraph feature cards
- No product preview anywhere on the page
- "Powered by AI" as a selling point instead of describing the experience
