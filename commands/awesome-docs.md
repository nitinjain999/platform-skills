---
name: awesome-docs
description: Generate, convert, and maintain animated GitHub-safe Markdown documents with animated SVG diagrams. Covers four SVG patterns (architecture flow, lifecycle loop, field carousel, timeline phases), guided interview for new docs, converting existing plain Markdown, diffing for stale diagrams, quality auditing, local preview, and multi-platform export. Use when asked to "create a demo doc for X", "animate this README", "convert my doc to animated", "check if my diagrams are stale", or "export my doc for Confluence".
argument-hint: "[generate|convert|update|diff|audit|preview|export] [topic or file path]"
---

Generate, convert, and maintain animated Markdown documents with GitHub-safe SVG animations.

---

## Mode: generate

Create a full animated demo document from scratch via guided interview.

Steps:
1. Ask one at a time:
   - Technology topic (e.g. "KEDA autoscaling", "Falco runtime security")
   - Target: local repo path (preferred) or remote GitHub URL to clone if no local path given
   - Key components — the 3–6 main moving parts (e.g. "ScaledObject, KEDA Operator, HPA, Deployment")
   - End-to-end flow direction (e.g. "metric source → KEDA → HPA → pods")
2. Classify which SVG patterns apply based on the topic:
   - `arch-flow` — always included
   - `lifecycle-loop` — if the topic has a repeating control loop (e.g. KEDA poll cycle, Flux reconcile loop)
   - `field-carousel` — only if the topic has a configurable resource (YAML/CRD); ask the user to paste their YAML/config at this point; validate syntax before generating
   - `timeline-phases` — if the topic has distinct load or lifecycle phases (e.g. idle → ramp → peak → cooldown)
3. For each applicable SVG pattern (incremental generation):
   - Generate the SVG using the blueprint in `references/awesome-docs.md`
   - Write to `assets/<topic-slug>-<pattern>.svg` (e.g. `assets/keda-arch-flow.svg`)
   - Show to the user and ask: "Does this look right? Confirm to continue or describe what to adjust."
   - Only proceed to the next SVG after explicit confirmation
4. Write `<TOPIC>-DEMO.md` at the repo root with all confirmed SVGs embedded using `<img>` tags, each followed by a `>` blockquote caption explaining what to watch in the animation
5. Include all standard doc sections (see Standard Sections below)
6. Prompt: "What real bugs or gotchas did you hit with this technology?" → auto-populate the Lessons Learned table from the answers
7. Commit and push: `git add <TOPIC>-DEMO.md assets/ && git commit -m "feat(<topic>-demo): animated demo doc with architecture, lifecycle, and field explainer SVGs" && git push`

**Standard doc sections (in order):**
1. `<div align="center">` header — title + shields.io static badges
2. Live Architecture — arch-flow SVG
3. Scaling/Flow Phases — lifecycle-loop or timeline-phases SVG (if generated)
4. What Problem Does X Solve? — ❌ without / ✅ with contrast block
5. How It Works (The Basics) — core formula or concept with concrete numbers
6. Core Resource — Every Field Explained — field-carousel SVG + full annotated YAML (if generated)
7. The Decision Formula — Step by Step — idle / active / cooldown states with real numbers (if applicable)
8. Demo Flow — ASCII phase walkthrough with exact timing
9. Lessons Learned — table: Bug | Why | Fix

**Theme parameter:** append `--theme github-dark` (default), `--theme docs-light`, or `--theme custom:#bg,#primary,#accent` to override colors. See `references/awesome-docs.md` → Theme System.

Reference: `references/awesome-docs.md` → SVG Patterns, Standard Doc Sections, Theme System

---

## Mode: convert

Animate an existing plain Markdown document by injecting SVGs in-place.

Steps:
1. Ask: path to the existing Markdown file (e.g. `docs/keda-guide.md`)
2. Read the file — extract all `##` headings and classify the doc structure:
   - Tutorial → arch-flow + field-carousel (if YAML present)
   - Architecture guide → arch-flow + lifecycle-loop
   - API reference → field-carousel
   - Troubleshooting → lifecycle-loop (failure paths)
3. Map each major section to the most appropriate SVG pattern
4. For each SVG to inject (incremental):
   - Check if `assets/<filename>.svg` already exists → if yes, ask: "An SVG with this name exists. Skip / Replace / Update?"
   - Generate SVG per blueprint in `references/awesome-docs.md`
   - Show to user — confirm before inserting
   - Insert `<img src="assets/<filename>.svg" />` + `>` blockquote caption immediately after the matching section heading
5. Commit: `git add <doc-path> assets/ && git commit -m "feat(awesome-docs): animate <doc-filename>"`

Reference: `references/awesome-docs.md` → SVG Patterns

---

## Mode: update

Revise a single diagram in an existing animated doc.

Steps:
1. Ask: doc path and which diagram to update (SVG filename or section name, e.g. `assets/keda-arch-flow.svg` or "Architecture section")
2. Read the existing SVG to understand current layout
3. Ask what needs to change: new component, corrected flow, different theme, timing adjustment
4. Regenerate the SVG using the same blueprint, incorporating the changes
5. Show the new SVG — confirm before writing
6. Overwrite `assets/<filename>.svg`
7. Commit: `git add assets/<filename>.svg && git commit -m "fix(awesome-docs): update <diagram-name> — <what changed>"`

Reference: `references/awesome-docs.md` → SVG Patterns

---

## Mode: diff

Detect stale diagrams by comparing the current doc against `git HEAD`.

Steps:
1. Ask: path to the doc (e.g. `KEDA-DEMO.md`)
2. Run: `git diff HEAD -- <doc-path>` to see what changed since the last commit
3. Scan for staleness signals:
   - Field count in YAML/config changed → field-carousel may be out of date
   - New component mentioned in prose but not in arch-flow SVG
   - Broken `<img>` reference (file in doc but not in `assets/`)
   - Section added/removed that would change which SVG patterns apply
4. Report a punch list: `[ ] <issue> — <file or section>` — do not auto-fix
5. Suggest: "Run `/platform-skills:awesome-docs update` for each flagged diagram."

Reference: `references/awesome-docs.md` → Quality Checklist

---

## Mode: audit

Quality-check an existing animated doc without making changes.

Steps:
1. Ask: path to the doc
2. Check each item in the Quality Checklist from `references/awesome-docs.md`:
   - Every SVG `<img>` tag has a `>` blockquote caption immediately after it
   - No environment-specific IDs, account numbers, or hostnames in the doc or SVG files
   - No SVG references a file outside `assets/` (no external `href`, no `xlink:href`)
   - At least 3 SVG diagrams present
   - All SVG files under 50KB (larger files may not render inline on GitHub)
   - Lessons Learned table present and has at least one row
3. Report findings as a numbered list: `[PASS]` or `[FAIL] — <what to fix>`
4. Print total: `X passed, Y failed`

Reference: `references/awesome-docs.md` → Quality Checklist, GitHub SVG Animation Constraints

---

## Mode: preview

Open the doc locally in a browser before committing.

Steps:
1. Ask: path to the doc
2. Check if the superpowers visual companion server is running (`$STATE_DIR/server-info` exists — `$STATE_DIR` is set by the superpowers brainstorming skill when active):
   - If running: copy the doc and `assets/` to `screen_dir` and navigate to the URL
   - If not running: start a minimal local HTTP server with `python3 -m http.server 8080 --directory .` and open the doc with `open http://localhost:8080/<doc-path>`
3. Tell the user: "Preview running at <URL>. Ctrl+C to stop."

Reference: `references/awesome-docs.md`

---

## Mode: export

Generate multi-format output from an existing animated doc.

Steps:
1. Ask: path to the doc and target format: `html` (Confluence/Notion) or `png` (email/PDF)
2. For `html`:
   - Read the doc
   - Replace all `<img src="assets/...">` references with inline SVG content (read each SVG file and embed it directly)
   - Wrap in a minimal `<!DOCTYPE html>` page with `<meta charset="utf-8">` and no external dependencies
   - Write to `<doc-basename>-embed.html`
   - Tell user: "Paste the contents of `<file>` into a Confluence HTML macro or Notion embed block."
3. For `png`:
   - Do not run the export — document the manual step instead:
     ```bash
     # Requires svgexport (npm install -g svgexport)
     for f in assets/*.svg; do svgexport "$f" "${f%.svg}.png" "svg" "2x"; done
     ```
   - Explain: "PNG export requires `svgexport` or Puppeteer. Install with `npm install -g svgexport` then run the command above."

Reference: `references/awesome-docs.md` → Multi-Platform Export
