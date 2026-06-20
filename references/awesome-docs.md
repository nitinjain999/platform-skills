---
title: Awesome Docs
custom_edit_url: null
---

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

Purpose: highlight each config field one-by-one with a tooltip explanation. Supports YAML, HCL, JSON, and TOML.

### Canvas

- Width: 900px, Height: 560px

### Layout

- Left panel `x=20..440`: config block with syntax coloring (YAML, HCL, JSON, or TOML — see Config Format Syntax Colors)
- Right panel `x=455..880`: single tooltip box visible at a time

### Config Format Syntax Colors

Choose the color scheme matching the config format in the left panel.

**YAML** (Kubernetes manifests, Helm values, CI configs):

| Element | Color |
|---------|-------|
| Field names | `#4a9eff` |
| String values | `#79c0ff` |
| Numeric values | `#ff9900` |
| Special keys (`apiVersion`, `kind`) | `#ff9900` |
| Comments (`# ...`) | `#8b949e` |

**HCL / Terraform** (`.tf`, `.tfvars`):

| Element | Color |
|---------|-------|
| Block type / resource label | `#ff9900` |
| Attribute names | `#4a9eff` |
| String values | `#79c0ff` |
| Numeric / bool values | `#ff9900` |
| Comments (`# ...` or `//`) | `#8b949e` |

**JSON** (API bodies, config files):

| Element | Color |
|---------|-------|
| Keys (quoted strings on left of `:`) | `#4a9eff` |
| String values | `#79c0ff` |
| Numeric / bool / null values | `#ff9900` |
| Structural punctuation (`{`, `}`, `[`, `]`, `,`) | `#e6edf3` |

**TOML** (application configs, Cargo.toml, pyproject.toml):

| Element | Color |
|---------|-------|
| Section headers (`[table]`) | `#ff9900` |
| Keys | `#4a9eff` |
| String values | `#79c0ff` |
| Numeric / bool values | `#ff9900` |
| Comments (`# ...`) | `#8b949e` |

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

## SVG Pattern E — Sequence Diagram (`sequence-diagram`)

Purpose: show request/response chains, API call sequences, and auth flows between actors.

### Canvas

- Width: 900px, Height: 400px
- Actors spaced evenly across x-axis; lifelines run vertically from actor box to bottom of canvas

### Actor and Lifeline Template

```xml
<!-- Actor box -->
<rect x="X" y="20" width="100" height="36" rx="6"
      fill="#161b22" stroke="#4a9eff" stroke-width="1.5"/>
<text x="X+50" y="38" text-anchor="middle" dominant-baseline="central"
      fill="#e6edf3" font-size="12" font-family="monospace">Actor</text>

<!-- Lifeline (dashed vertical line) -->
<line x1="X+50" y1="56" x2="X+50" y2="380"
      stroke="#4a9eff" stroke-width="1" stroke-dasharray="4 4" opacity="0.4"/>
```

### Message Arrow Template

Synchronous call (solid line, filled arrowhead) — animate with CSS `opacity` cycling:

```xml
<defs>
  <marker id="arrow-seq" markerWidth="8" markerHeight="8"
          refX="6" refY="3" orient="auto">
    <path d="M0,0 L0,6 L8,3 z" fill="#4a9eff"/>
  </marker>
  <marker id="arrow-ret" markerWidth="8" markerHeight="8"
          refX="6" refY="3" orient="auto">
    <path d="M0,0 L0,6 L8,3 z" fill="#8b949e"/>
  </marker>
</defs>

<!-- Request arrow (left to right) -->
<line x1="SRC_X" y1="MSG_Y" x2="DST_X" y2="MSG_Y"
      stroke="#4a9eff" stroke-width="1.5" marker-end="url(#arrow-seq)"
      class="msg0"/>
<text x="MID_X" y="MSG_Y-6" text-anchor="middle"
      fill="#8b949e" font-size="11">message label</text>

<!-- Return arrow (right to left, dashed) -->
<line x1="DST_X" y1="RET_Y" x2="SRC_X" y2="RET_Y"
      stroke="#8b949e" stroke-width="1.5" stroke-dasharray="4 3"
      marker-end="url(#arrow-ret)" class="msg0-ret"/>
```

### Message Sequencing (CSS step animation)

Reveal each message in turn — N messages cycling over T seconds:

```xml
<style>
  /* N=4 messages, T=8s → slot=2s */
  @keyframes seq-show { 0%,90%{opacity:1} 95%,100%{opacity:0} }

  .msg0     { animation: seq-show 8s linear infinite 0s;   }
  .msg0-ret { animation: seq-show 8s linear infinite 0.4s; }
  .msg1     { animation: seq-show 8s linear infinite 2s;   }
  .msg1-ret { animation: seq-show 8s linear infinite 2.4s; }
  .msg2     { animation: seq-show 8s linear infinite 4s;   }
  .msg2-ret { animation: seq-show 8s linear infinite 4.4s; }
  .msg3     { animation: seq-show 8s linear infinite 6s;   }
  .msg3-ret { animation: seq-show 8s linear infinite 6.4s; }
</style>
```

**Invariant:** Each message's return arrow delay = message delay + 0.4s. Last message ends at T.

### Activation Box (optional)

Show that an actor is processing with a narrow rect on its lifeline:

```xml
<rect x="X+44" y="MSG_Y" width="12" height="RET_Y-MSG_Y"
      fill="#4a9eff" opacity="0.25" class="msg0"/>
```

---

## SVG Pattern F — State Machine (`state-machine`)

Purpose: show states, transitions between them, and animate the "current state" highlight cycling through a typical path.

### Canvas

- Width: 900px, Height: 360px

### State Node Template

```xml
<!-- Idle state (initial — double border) -->
<circle cx="X" cy="Y" r="34" fill="#161b22" stroke="#4a9eff" stroke-width="3"/>
<circle cx="X" cy="Y" r="28" fill="none"    stroke="#4a9eff" stroke-width="1" opacity="0.4"/>
<text x="X" y="Y" text-anchor="middle" dominant-baseline="central"
      fill="#e6edf3" font-size="12" font-family="monospace">Idle</text>

<!-- Regular state -->
<circle cx="X" cy="Y" r="34" fill="#161b22" stroke="#8b949e" stroke-width="1.5"/>
<text x="X" y="Y" text-anchor="middle" dominant-baseline="central"
      fill="#e6edf3" font-size="12" font-family="monospace">Active</text>

<!-- Terminal state (filled inner circle) -->
<circle cx="X" cy="Y" r="34" fill="#161b22" stroke="#8b949e" stroke-width="1.5"/>
<circle cx="X" cy="Y" r="20" fill="#3fb950" opacity="0.7"/>
<text x="X" y="Y" text-anchor="middle" dominant-baseline="central"
      fill="#0d1117" font-size="11" font-family="monospace">Done</text>
```

### Transition Arrow

```xml
<defs>
  <marker id="arrow-sm" markerWidth="8" markerHeight="8"
          refX="6" refY="3" orient="auto">
    <path d="M0,0 L0,6 L8,3 z" fill="#8b949e"/>
  </marker>
</defs>
<!-- Straight transition -->
<line x1="SRC_X+34" y1="SRC_Y" x2="DST_X-34" y2="DST_Y"
      stroke="#8b949e" stroke-width="1.5" marker-end="url(#arrow-sm)"/>
<text x="MID_X" y="MID_Y-8" text-anchor="middle"
      fill="#8b949e" font-size="10">trigger</text>

<!-- Self-loop transition (arc above node) -->
<path d="M X-10,Y-34 A 30 30 0 1 1 X+10,Y-34"
      fill="none" stroke="#8b949e" stroke-width="1.5" marker-end="url(#arrow-sm)"/>
```

### Current-State Highlight (CSS cycling)

Animate a glowing ring on each state in sequence. N states, T seconds:

```xml
<style>
  /* N=4 states, T=12s → slot=3s */
  @keyframes cur-state {
    0%,20%  { opacity: 1; r: 38; }
    25%,100%{ opacity: 0; r: 34; }
  }

  .cur0 { animation: cur-state 12s ease-in-out infinite 0s;   }
  .cur1 { animation: cur-state 12s ease-in-out infinite 3s;   }
  .cur2 { animation: cur-state 12s ease-in-out infinite 6s;   }
  .cur3 { animation: cur-state 12s ease-in-out infinite 9s;   }
</style>

<!-- Overlay pulsing ring on each state (same cx/cy as state node) -->
<circle cx="X" cy="Y" r="34" fill="none" stroke="#4a9eff" stroke-width="2"
        class="cur0" opacity="0"/>
```

**Note:** CSS `r` attribute animation requires SVG 2 support. For broad compatibility, use `transform: scale()` on a `<g>` wrapper or animate `stroke-width` instead:

```xml
<style>
  @keyframes cur-ring { 0%,20%{opacity:1;stroke-width:4} 25%,100%{opacity:0;stroke-width:1.5} }
  .cur0 { animation: cur-ring 12s ease-in-out infinite 0s; }
</style>
<circle cx="X" cy="Y" r="38" fill="none" stroke="#4a9eff" class="cur0" opacity="0"/>
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

## Doc Type Section Maps

`generate` mode adapts structure to the document type. Default section sets by type:

| Doc type | Default sections |
|----------|-----------------|
| `readme` | Header (title + badges), Overview, Architecture (arch-flow), How it works, Getting started, Configuration (field-carousel), Examples, Troubleshooting |
| `architecture-guide` | Overview, System diagram (arch-flow), Component responsibilities, Data flow, State/scaling behavior (lifecycle-loop), Configuration reference (field-carousel), Deployment phases (timeline-phases), Decisions & trade-offs |
| `runbook` | Prerequisites, Health check commands, Architecture diagram, Step-by-step procedure, Validation, Rollback |
| `tutorial` | Introduction, Prerequisites, Architecture overview (arch-flow), Step-by-step walkthrough, What you built, Next steps |
| `api-reference` | Overview, Authentication, Endpoints, Request/response fields (field-carousel), Error codes, Examples |
| `how-it-works` | Overview, Architecture (arch-flow), Lifecycle/control loop (lifecycle-loop), Configuration fields (field-carousel), Load phases (timeline-phases) |
| `rfc` | Context and problem, Proposal, Architecture diagram, Alternatives considered, Decision criteria, Open questions |
| `post-mortem` | Incident summary, Timeline, Root cause analysis, Impact, Action items, Lessons learned |
| `custom` | User-defined sections in user-specified order |

Captions must be placed **immediately after** each `<img>` tag.

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
- [ ] Every SVG `<img>` tag has a `>` blockquote caption immediately after it
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
