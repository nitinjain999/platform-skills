# Awesome Docs Reference

Covers animated GitHub-safe Markdown document generation — SVG blueprints, animation math, theme system, GitHub rendering constraints, multi-platform export, and external references.

---

## GitHub SVG Animation Constraints

GitHub sanitizes SVG files embedded in Markdown. These rules are enforced by GitHub's Camo proxy — violate them and the SVG renders as a broken image.

| Allowed | Blocked |
|---------|---------|
| CSS `@keyframes` | JavaScript `<script>` |
| `animation:` property | External font `@import` |
| `filter: drop-shadow()` | External image `href` |
| `offset-path` + `offset-distance` | `foreignObject` |
| Inline `<style>` block | SMIL `<animate>` tags |
| `<marker>` arrowheads | `xlink:href` to external URL |
| `<title>` + `<desc>` + `role="img"` | `<use href="external">` |

**File size limit:** GitHub refuses to render SVG files inline if they exceed ~50KB. Run `ls -lh assets/*.svg` to check. If any file is over 50KB, optimise with `svgo --input <file> --output <file>`.

Always use `offset-path` for moving dots — not SMIL. Always use CSS `animation:` — not SMIL `<animate>`.

---

## SVG Pattern A — Architecture Flow (`arch-flow`)

Purpose: show the full system with colored animated dots flowing along arrows between component boxes.

### Canvas

- Width: 900px, Height: 520px (expand to 570px if legend overlaps boxes — move legend to `y = height - 60`)
- Background: `fill: #0d1117` (github-dark) or `fill: #ffffff` (docs-light)

### Box Template

```xml
<rect x="X" y="Y" width="W" height="H" rx="8"
      fill="#161b22" stroke="#4a9eff" stroke-width="1.5"
      class="glow-blue"/>
<text x="X+W/2" y="Y+H/2" text-anchor="middle"
      dominant-baseline="central" fill="#e6edf3" font-size="13"
      font-family="monospace">Box Label</text>
```

### Glow Animation (one per box color)

```xml
<style>
  @keyframes glow-blue {
    0%,100% { filter: drop-shadow(0 0 3px #4a9eff); }
    50%     { filter: drop-shadow(0 0 14px #4a9eff); }
  }
  .glow-blue { animation: glow-blue 3s ease-in-out infinite; }
</style>
```

Use `#4a9eff` for primary path, `#ff9900` for secondary, `#ff7b72` for alerts/errors, `#79c0ff` for config/auth sidecars.

### Animated Dot Template

Two dots per path, second with a half-period delay for continuous flow:

```xml
<style>
  .dot-main {
    fill: #4a9eff;
    offset-path: path("M 100 80 L 300 80 L 300 200");
    offset-rotate: 0deg;
    animation: flow-main 3s linear infinite 0s;
  }
  .dot-main-b {
    fill: #4a9eff;
    offset-path: path("M 100 80 L 300 80 L 300 200");
    offset-rotate: 0deg;
    animation: flow-main 3s linear infinite 1.5s;
  }
  @keyframes flow-main {
    0%   { opacity: 0; offset-distance: 0%;   }
    5%   { opacity: 1; }
    95%  { opacity: 1; }
    100% { opacity: 0; offset-distance: 100%; }
  }
</style>
<circle class="dot-main"   r="5"/>
<circle class="dot-main-b" r="5"/>
```

Replace the `path("M ... L ...")` with the actual waypoints between boxes.

### Arrowhead Marker

```xml
<defs>
  <marker id="arrow" markerWidth="8" markerHeight="8"
          refX="6" refY="3" orient="auto">
    <path d="M0,0 L0,6 L8,3 z" fill="#4a9eff"/>
  </marker>
</defs>
<line x1="100" y1="80" x2="290" y2="80"
      stroke="#4a9eff" stroke-width="1.5" marker-end="url(#arrow)"/>
```

### Legend

Single row at `y = canvas_height - 45`, items evenly spaced, never overlapping component boxes:

```xml
<circle cx="50"  cy="475" r="5" fill="#4a9eff"/>
<text   x="60"  y="479" fill="#8b949e" font-size="11">Primary flow</text>
<circle cx="180" cy="475" r="5" fill="#ff9900"/>
<text   x="190" y="479" fill="#8b949e" font-size="11">Config/auth</text>
```

---

## SVG Pattern B — Decision/Lifecycle Loop (`lifecycle-loop`)

Purpose: animate the repeating control loop (poll → evaluate → gate → act → wait → repeat).

### Canvas

- Width: 900px, Height: 310px

### Layout (left to right)

```
[Source] →→→ [Operator] →→→ ◇Gate◇ → [Formula] → [HPA] → [Pods]
                                ↓ NO
                           [Inactive]
```

### Diamond Gate

```xml
<polygon points="X,Y-20 X+25,Y X,Y+20 X-25,Y"
         fill="#161b22" stroke="#ff9900" stroke-width="1.5"/>
<text x="X" y="Y" text-anchor="middle" dominant-baseline="central"
      fill="#ff9900" font-size="11">threshold?</text>
```

### 3-State CSS Cycling (12s loop)

```xml
<style>
  .s-idle { animation: show-idle 12s ease-in-out infinite both; }
  .s-act  { animation: show-act  12s ease-in-out infinite both; }
  .s-cool { animation: show-cool 12s ease-in-out infinite both; }

  @keyframes show-idle { 0%,22%{opacity:1} 27%,100%{opacity:0} }
  @keyframes show-act  { 0%,27%{opacity:0} 32%,68%{opacity:1} 73%,100%{opacity:0} }
  @keyframes show-cool { 0%,72%{opacity:0} 77%,95%{opacity:1} 100%{opacity:0} }
</style>

<!-- Show different label/color for each state on the relevant box -->
<g class="s-idle"><rect ... fill="#1a2233"/><text fill="#8b949e">Idle</text></g>
<g class="s-act" ><rect ... fill="#0d2a1a"/><text fill="#3fb950">Active</text></g>
<g class="s-cool"><rect ... fill="#2a1a0d"/><text fill="#ff9900">Cooldown</text></g>
```

### Status Bar

Full-width rect at `y = height - 52` (rect), text at `y = height - 32`:

```xml
<rect x="0" y="258" width="900" height="30" fill="#161b22"/>
<g class="s-idle"><text x="450" y="278" text-anchor="middle"
   fill="#8b949e" font-size="12">Metric below threshold — no scaling action</text></g>
<g class="s-act" ><text x="450" y="278" text-anchor="middle"
   fill="#3fb950" font-size="12">Metric above threshold — scaling up</text></g>
<g class="s-cool"><text x="450" y="278" text-anchor="middle"
   fill="#ff9900" font-size="12">Cooldown period — holding replica count</text></g>
```

---

## SVG Pattern C — Field Explainer Carousel (`field-carousel`)

Purpose: highlight each config field one-by-one with a tooltip explanation.

### Canvas

- Width: 900px, Height: 560px

### Layout

- Left panel `x=20..440`: YAML block with syntax coloring
- Right panel `x=455..880`: single tooltip box visible at a time

### YAML Syntax Colors

| Element | Color |
|---------|-------|
| Field names | `#4a9eff` |
| String values | `#79c0ff` |
| Numeric values | `#ff9900` |
| Special keys (`apiVersion`, `kind`) | `#ff9900` |
| Comments | `#8b949e` |

### Timing Formula

For N fields cycling over T seconds total:
```
slot  = T / N          (seconds per field)
delay[i] = i * slot    (start delay for field i, 0-indexed)
```

Each field visible for the first 12% of T (= 0.12 × T seconds), fade 12–15% of T, hidden for the remainder. With N=6, T=9s this means each field shows for 1.08s (72% of its 1.5s slot):

```xml
<style>
  /* N=6, T=9s → slot=1.5s */
  @keyframes hl  { 0%,12%{opacity:1} 15%,100%{opacity:0} }
  @keyframes tip { 0%,12%{opacity:1} 15%,100%{opacity:0} }

  .hl0  { animation: hl  9s ease-in-out infinite 0s;    fill: #ffffff10; }
  .hl1  { animation: hl  9s ease-in-out infinite 1.5s;  fill: #ffffff10; }
  .hl2  { animation: hl  9s ease-in-out infinite 3.0s;  fill: #ffffff10; }
  .hl3  { animation: hl  9s ease-in-out infinite 4.5s;  fill: #ffffff10; }
  .hl4  { animation: hl  9s ease-in-out infinite 6.0s;  fill: #ffffff10; }
  .hl5  { animation: hl  9s ease-in-out infinite 7.5s;  fill: #ffffff10; }

  .tip0 { animation: tip 9s ease-in-out infinite 0s;    }
  .tip1 { animation: tip 9s ease-in-out infinite 1.5s;  }
  .tip2 { animation: tip 9s ease-in-out infinite 3.0s;  }
  .tip3 { animation: tip 9s ease-in-out infinite 4.5s;  }
  .tip4 { animation: tip 9s ease-in-out infinite 6.0s;  }
  .tip5 { animation: tip 9s ease-in-out infinite 7.5s;  }
</style>
```

**Invariant:** `N × slot = T` must hold exactly. No gap between last field and loop restart.

### Tooltip Structure (one per field)

```xml
<g class="tip0">
  <rect x="455" y="Y" width="420" height="100" rx="6"
        fill="#161b22" stroke="#4a9eff" stroke-width="1.5"/>
  <text x="475" y="Y+22" fill="#4a9eff" font-size="13" font-weight="bold">fieldName</text>
  <text x="475" y="Y+42" fill="#8b949e" font-size="12">Description line 1</text>
  <text x="475" y="Y+58" fill="#8b949e" font-size="12">Description line 2</text>
  <rect x="455" y="Y+72" width="420" height="22" rx="3" fill="#0d2233"/>
  <text x="475" y="Y+87" fill="#79c0ff" font-size="11" font-family="monospace">Example: value</text>
</g>
```

---

## SVG Pattern D — Timeline Phases (`timeline-phases`)

Purpose: show load phases on a horizontal timeline with trigger activation bars and replica count chart.

### Canvas

- Width: 900px, Height: 280px

### Timeline Bar

```xml
<rect x="50" y="50" width="800" height="8" rx="4" fill="#21262d"/>
<!-- Phase markers -->
<circle cx="PHASE_X" cy="54" r="5" fill="#4a9eff"/>
<text x="PHASE_X" y="38" text-anchor="middle" fill="#8b949e" font-size="11">Phase Name</text>
```

### Replica Chart

Chart occupies `y=100..220` (chart_top=100, chart_bottom=220, chart_height=120).

Bar height formula for N replicas at maxReplicas M:
```
bar_y      = 220 - (N / M) * 120
bar_height = 220 - bar_y
```

```xml
<!-- Gridlines at each replica level -->
<line x1="50" y1="GRID_Y" x2="850" y2="GRID_Y" stroke="#21262d" stroke-width="1"/>
<text x="35" y="GRID_Y+4" text-anchor="end" fill="#8b949e" font-size="10">N</text>

<!-- Animated bar (fades in at phase start using CSS animation) -->
<rect x="PHASE_X" y="BAR_Y" width="PHASE_WIDTH" height="BAR_HEIGHT"
      rx="2" fill="#4a9eff" opacity="0.7"
      style="animation: bar-PHASE DURs ease-in 0s both"/>
```

---

## Theme System

| Preset | Background | Primary | Secondary | Alert | Comment |
|--------|-----------|---------|-----------|-------|---------|
| `github-dark` (default) | `#0d1117` | `#4a9eff` | `#79c0ff` | `#ff9900` | `#8b949e` |
| `docs-light` | `#ffffff` | `#0969da` | `#0a3069` | `#953800` | `#57606a` |
| `custom` | user `#bg` | user `#p` | user `#s` | user `#a` | user `#c` |

Apply by substituting the hex values throughout the SVG `<style>` block. The box fill color lightens by 10% relative to the background (e.g. `#0d1117` bg → `#161b22` box fill).

---

## Standard Doc Sections

All docs generated by `generate` mode follow this section order:

1. `<div align="center">` header — title + shields.io static badges
2. **Live Architecture** — arch-flow SVG + `>` blockquote caption
3. **Scaling/Flow Phases** — lifecycle-loop or timeline-phases SVG + caption (if generated)
4. **What Problem Does X Solve?** — ❌ without / ✅ with contrast block
5. **How It Works (The Basics)** — core formula or concept with concrete numbers
6. **Core Resource — Every Field Explained** — field-carousel SVG + annotated YAML (if generated)
7. **The Decision Formula** — idle / active / cooldown states with real numbers (if applicable)
8. **Demo Flow** — ASCII phase walkthrough with exact timing
9. **Lessons Learned** — table: `Bug | Why | Fix`

Captions must be placed **immediately after** each `<img>` tag — the validator checks this.

---

## Multi-Platform Export

| Target | Format | Notes |
|--------|--------|-------|
| GitHub | CSS `@keyframes` SVG via `<img>` tag | Default output — no JS, no external href, no SMIL |
| Confluence / Notion | Animated HTML with inline SVG | Embed in HTML macro or Notion embed block |
| Email / PDF | Static PNG (manual) | `svgexport <file>.svg <file>.png 2x` — requires `npm install -g svgexport` |

---

## Quality Checklist

Used by `audit` mode and verified during `generate`/`convert` before committing:

- [ ] No environment-specific IDs, account numbers, or hostnames in doc or SVG files
- [ ] Legend `y` coordinate does not overlap any content box
- [ ] Each animated bar `y + height = chart_bottom` (220) exactly
- [ ] Fields carousel: `N × slot = T` (no gap at loop restart)
- [ ] Every SVG is self-contained — no external `href`, no `<script>`, no `@import`
- [ ] At least 3 SVG diagrams present
- [ ] Every SVG `<img>` tag has a `>` blockquote caption immediately after it
- [ ] All formulas shown with concrete numbers from the real config
- [ ] Lessons Learned table present with at least one row
- [ ] All SVG files under 50KB (`ls -lh assets/*.svg`)

---

## External References

| Resource | URL | Purpose |
|----------|-----|---------|
| MDN CSS `offset-path` | https://developer.mozilla.org/en-US/docs/Web/CSS/offset-path | Moving dot animation primitive |
| MDN CSS `@keyframes` | https://developer.mozilla.org/en-US/docs/Web/CSS/@keyframes | Keyframe syntax reference |
| MDN CSS `animation` | https://developer.mozilla.org/en-US/docs/Web/CSS/animation | Animation shorthand property |
| GitHub SVG sanitization | https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/sanitizing-svg | GitHub's SVG rendering rules |
| Shields.io | https://shields.io/badges/static-badge | Static badge URL format |
| SVGO | https://github.com/svg/svgo | SVG optimiser CLI — use when SVG exceeds 50KB |
| VoltAgent awesome-agent-skills | https://github.com/VoltAgent/awesome-agent-skills | Canonical skill structure and formatting examples |
| GitHub Primer CSS | https://primer.style/foundations/color | GitHub color tokens for matching native visual style |
