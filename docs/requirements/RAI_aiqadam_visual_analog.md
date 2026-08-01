# RAI — AI-Qadam Visual Analog (iterative build)

> **Reference site:** https://aiqadam.org — Multi-tenant community platform for AI
> engineers across Central Asia. Astro/Next.js frontend, Node.js backend. This R-file
> describes a **visual desktop analog** built with zig-gui, NOT a port of the backend.
> Backend integration (Telegram lead capture, real country subdomain redirect,
> Directus CMS, Auth.js) is explicitly **out of scope** for this milestone.

---

## 1. Goal

Build a desktop GUI screen that visually mirrors the AI-Qadam website, built
iteratively: each iteration produces a screenshot, which is compared against the
original, and the next iteration refines until the analog is acceptable.

The screen lives in the Showcase demo app (`src/demo/screens/aiqadam.zig`) and is
selected from the sidebar like every other Showcase screen. It runs in the same
binary — no separate executable, no extra dependencies.

**Visual reference (homepage):** https://aiqadam.org — see section 4 for the
full component breakdown and the screenshot baseline.

---

## 2. Non-goals

- **No backend integration.** No HTTP calls, no Telegram bot, no Directus CMS
  reads, no Auth.js. All "live" data is hard-coded in the screen (e.g. the 3
  countries, "uz · kz · tj", the partner list, the recording list).
- **No i18n.** English-only text for v1. The country/language switcher in the
  header is visual only (no real switching).
- **No subdomain routing.** The site shows one country (uz) for v1.
- **No working forms.** The "Get events in your city" form is rendered
  structurally but the "Send me a confirmation" button does NOT submit anywhere.
- **No mobile / responsive design.** Desktop is the target.
- **No asset fetching.** No logos, no icons from the network. Use Unicode/emoji
  substitutes for the footstep logo (e.g. "🌱" or stylized "⚡") and any icons
  (e.g. "🌐" for globe, arrow chars for chevrons).

---

## 3. Architecture / scope

- New screen file: `src/demo/screens/aiqadam.zig`
- New sidebar entry: append `"aiqadam"` / `"AI-Qadam"` to the `SCREEN_NAMES` /
  `SCREEN_LABELS` arrays in `src/demo/shared/sidebar.zig` and to `SidebarCbs` /
  `ctxForScreen` in `src/demo/shared/types.zig` and to the wiring block in
  `src/demo/main.zig`.
- No new module, no new types, no `acceptance_test.zig`. The R-file itself is
  the done-marker; visual parity is verified by the Visual Validation Loop
  (§10 of `docs/agents/AGENT_WORKFLOWS.md`).
- Theme: dark palette throughout. The original site uses a near-black background
  (`#000` / `#0a0a0a`), white text, and a single teal accent (~`#5eead4` /
  `#2dd4bf`). Use `Theme.dark` with `Theme.palette` overridden where necessary —
  **never** hard-code hex literals on a widget (INV-4.3). If the default dark
  palette is close enough, prefer it; if a teal accent is missing, add it as a
  semantic token in `src/05/types.zig` under the AAP (§8).
- Window size: 1180 × 1100 (matches the original's max-width 1180 px and gives
  room for the entire scroll, same as the demo default).

---

## 4. Visual reference — full component breakdown

Source: live screenshot of https://aiqadam.org captured 2026-08-01.

### 4.1 Header (sticky top)
- Left: small footstep icon + "AI Qadam" text in monospace teal.
- Center: nav links — "Events", "Leaderboard" (text, not buttons; no hover state
  required for v1).
- Right: country selector pill (🇺🇿 Uzbekistan), language selector pill (English),
  "Register" outlined button, "Sign in" filled teal button.
- Full-width, ~64 px tall, bottom border.

### 4.2 Hero
- Centered.
- Top eyebrow: "AI QADAM — COMMUNITY PLATFORM" in monospace, letter-spaced,
  small caps, muted color.
- Heading: `"AI engineers, building together across Central Asia."` — large,
  bold, white.
- Subtitle: `"Multi-tenant community platform for AI engineers across Central
  Asia."` — muted, body size.
- Two CTAs side-by-side, centered: "Browse events" (filled teal), "Join on
  Telegram" (outlined / dark surface).

### 4.3 Stats row (3 columns, equal width)
- Column 1: eyebrow "COUNTRIES SERVED", value "3".
- Column 2: eyebrow "OPERATOR TENANTS", value "uz · kz · tj".
- Column 3: eyebrow "CHANNEL", value "Open community".
- All center-aligned. Values are large monospace bold; eyebrows are small
  letter-spaced muted.

### 4.4 Newsletter card
- Full-width card with surface bg + border.
- Heading: "Get events in your city".
- Sub: "Monthly digest. No spam. Unsubscribe in one click."
- Form fields stacked vertically:
  - "Email" label + wide text input (placeholder "you@domain.com").
  - "City (optional)" label + wide text input (placeholder "Tashkent, Almaty,
    Dushanbe…").
  - "Topics you care about (optional)" label + row of pill buttons:
    AI/ML, LLMs, fintech, robotics, devtools, infra, data, computer-vision,
    nlp, mlops, hands-on-builder. (Pills are static; toggling is post-v1.)
  - "Send me a confirmation" filled teal button (disabled by default per
    original — text input is empty so disabled is correct for v1).

### 4.5 Footer
- 3-column grid.
- Column 1: "AI Qadam" (large bold) + tagline + "3 countries served" small
  mono.
- Column 2: "FOLLOW" eyebrow + "Telegram ↗" link.
- Column 3: "CONTACT" eyebrow + "Partners" link + "Press" link.
- Bottom strip: "© 2026 AI Qadam · Community-as-platform for Central Asian AI
  engineers" small mono muted, full-width.

---

## 5. Acceptance criteria

- [ ] Sidebar entry "AI-Qadam" navigates to the new screen.
- [ ] Header renders with logo, nav, country/lang selectors, Register and
      Sign in buttons.
- [ ] Hero renders with eyebrow, heading, subtitle, two CTAs.
- [ ] Stats row renders 3 columns with eyebrow + value pattern.
- [ ] Newsletter card renders heading, sub, email input, city input, topic
      pills, submit button.
- [ ] Footer renders brand block, Follow column, Contact column, copyright.
- [ ] `zig build` exits 0.
- [ ] `zig build run-demo --initial-screen aiqadam --screenshot-out <path>`
      produces a screenshot that visually approximates the original.
- [ ] Visual Validation Loop (§10) reports VISUAL_PASS or all diffs are
      documented in `docs/.agent-context/<run-id>/visual/` with Implementer
      having acted on them.

---

## 6. Iterative plan

Each iteration is a discrete build → screenshot → compare → refine cycle. The
first iteration that produces a structurally-correct layout (all sections
present, in the right vertical order, with the right typography hierarchy) is
considered v1. Subsequent iterations refine spacing, colors, and details.

| Iter | Goal | Stop condition |
|---|---|---|
| 1 | Layout + hierarchy: every section present, right order, correct text. | Header / hero / stats / newsletter / footer all render in the right order with the right text content. Typography hierarchy is correct (eyebrow small + muted, heading large + bold, body medium + muted). |
| 2 | Dark palette + teal accent applied to CTAs and logo. | Teal accent visible on logo text, "Sign in" button, "Browse events" button, "Send me a confirmation" button. Background is near-black. Borders are subtle dark grey. |
| 3 | Spacing + alignment polish: padding, gaps, centering. | All sections have comfortable breathing room. Hero is centered. Stats row aligns in 3 equal columns. Newsletter card spans the content area with consistent internal padding. |
| 4 | Detail fidelity: footer 3-col grid, bottom copyright strip, pill buttons, hover/disabled states. | Footer matches 3-column + bottom strip layout. Pills render in a single wrapped row. Disabled button is visually dim. Country/lang pills have a subtle border. |

Iterations after v4 are ad-hoc (whatever the diff report calls for).

---

## 7. How to verify

```bash
cd c:\Users\tvolo\dev\ai-dala\zig-gui
zig build
zig build run-demo -- --initial-screen aiqadam --screenshot-frames 4 --screenshot-out testdata/aiqadam_v1.png
```

Compare `testdata/aiqadam_v1.png` to the reference (browser screenshot of
`https://aiqadam.org`). Each iteration's screenshot is checked into
`testdata/aiqadam_v<n>.png` for diff history.

---

## 8. Documentation impact

- `docs/requirements/DEMO_APP.md` gains a "Screen 14 — AI-Qadam visual analog"
  section that points back to this R-file for the canonical spec.
- This R-file is referenced from the new sidebar entry's tooltip in the
  Showcase demo (post-v1; not blocking).