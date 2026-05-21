---
name: awesome-docs
description: Generate, convert, and maintain animated GitHub-safe Markdown documents with animated SVG diagrams. Covers four SVG patterns (architecture flow, lifecycle loop, field carousel, timeline phases), guided interview for any doc type (README, architecture guide, runbook, API reference, tutorial, RFC, post-mortem, how-it-works, or custom), converting existing plain Markdown, diffing for stale diagrams, quality auditing, local preview, and multi-platform export. Use when asked to "create a README for X", "write an architecture doc", "animate this guide", "convert my doc to animated", "check if my diagrams are stale", or "export my doc for Confluence".
argument-hint: "[generate|convert|update|diff|audit|preview|export] [doc type or file path]"
---

Generate, convert, and maintain animated Markdown documents with GitHub-safe SVG animations.

---

## Mode: generate

Create a new animated Markdown document from scratch. Adapts structure and SVGs to the document type — not limited to demo docs.

Steps:
1. Ask one at a time:
   - **Document type** — what kind of document? Choose from: `readme`, `architecture-guide`, `runbook`, `tutorial`, `api-reference`, `how-it-works`, `rfc`, `post-mortem`, or `custom` (user defines sections)
   - **Topic / subject** — what is the document about? (e.g. "KEDA autoscaling", "orders-service API", "Kubernetes upgrade runbook")
   - **Output path** — where should the file be written? (e.g. `README.md`, `docs/architecture.md`, `runbooks/keda.md`)
   - **Key components** — the main moving parts, concepts, or resources covered (3–6 items)
2. Show the user an outline of the proposed document structure and which SVG patterns will apply:
   - List the sections from the doc-type section map (see below) in order
   - Next to each section that will get an SVG, note the pattern name: e.g. `Architecture → arch-flow`
   - Ask: "Does this structure look right? Confirm to continue or describe what to change."
   - Only proceed after explicit confirmation; adjust sections or pattern choices on request
3. Classify which SVG patterns are relevant to this doc type and topic:
   - `arch-flow` — any doc that describes a system with multiple components or a data flow
   - `lifecycle-loop` — docs covering a repeating control loop, approval cycle, or state machine
   - `sequence-diagram` — docs covering request/response chains, API call sequences, or auth flows
   - `state-machine` — docs covering distinct states and transitions (deployment lifecycle, approval workflow, error/retry paths)
   - `field-carousel` — docs covering a configurable resource (YAML, HCL, JSON, or TOML); ask the user to paste their config at this point and identify the format before generating
   - `timeline-phases` — docs covering distinct phases, stages, or a lifecycle with durations
   - For `rfc`, `post-mortem`, `runbook`: SVGs are optional — ask "Would diagrams help here?" before generating
4. For each applicable SVG pattern (incremental):
   - Generate the SVG using the blueprint in `references/awesome-docs.md`
   - Write to `assets/<topic-slug>-<pattern>.svg`
   - Show to the user and ask: "Does this look right? Confirm to continue or describe what to adjust."
   - Only proceed to the next SVG after explicit confirmation
5. Build the document structure from the **doc type section map** below
6. Write the file to the output path with all confirmed SVGs embedded using `<img>` tags, each followed by a `>` blockquote caption
7. Commit: `git add <output-path> assets/ && git commit -m "docs(<scope>): add <doc-type> for <topic>"`

**Doc type section map** — use these as the default structure, adapt to user needs:

| Doc type | Default sections |
|----------|-----------------|
| `readme` | Header (title + badges), Overview, Architecture diagram (arch-flow), How it works, Getting started, Configuration (field-carousel if applicable), Examples, Troubleshooting |
| `architecture-guide` | Overview, System diagram (arch-flow), Component responsibilities, Data flow, Scaling/state behavior (lifecycle-loop or state-machine), Configuration reference (field-carousel), Deployment phases (timeline-phases), Decisions & trade-offs |
| `runbook` | Prerequisites, Health check commands, Architecture diagram, State/failure paths (state-machine if applicable), Step-by-step procedure, Validation, Rollback |
| `tutorial` | Introduction, Prerequisites, Architecture overview (arch-flow), Request flow (sequence-diagram if API-heavy), Step-by-step walkthrough, What you built, Next steps |
| `api-reference` | Overview, Authentication, Request flow (sequence-diagram), Endpoints, Request/response fields (field-carousel), Error codes, Examples |
| `how-it-works` | Overview, Architecture diagram (arch-flow), Lifecycle/control loop (lifecycle-loop or state-machine), Request flow (sequence-diagram if applicable), Configuration fields (field-carousel), Load phases (timeline-phases if applicable) |
| `rfc` | Context and problem, Proposal, Architecture diagram, Alternatives considered, Decision criteria, Open questions |
| `post-mortem` | Incident summary, Timeline, Root cause analysis, Impact (state-machine of failure path if helpful), Action items, Lessons learned |
| `custom` | Ask the user to list the sections they want, then generate them in order |

**Theme parameter:** append `--theme github-dark` (default), `--theme docs-light`, or `--theme custom:#bg,#primary,#accent` to override colors. See `references/awesome-docs.md` → Theme System.

Reference: `references/awesome-docs.md` → SVG Patterns, Theme System

---

## Mode: convert

Animate an existing plain Markdown document by injecting SVGs in-place.

Steps:
1. Ask: path to the existing Markdown file, or a directory path for batch mode (e.g. `docs/keda-guide.md` or `docs/`)
   - If a directory is given, discover all `.md` files recursively (`find <dir> -name "*.md"`) and process each in turn; report a summary table when all files are done
2. For each file: read it, extract all `##` headings, and classify the doc type:
   - `readme` → arch-flow + field-carousel (if config block present)
   - `architecture-guide` → arch-flow + lifecycle-loop or state-machine
   - `runbook` → arch-flow + state-machine (failure/recovery paths)
   - `tutorial` → arch-flow + sequence-diagram (if API calls shown) + field-carousel (if config present)
   - `api-reference` → sequence-diagram + field-carousel
   - `how-it-works` → arch-flow + lifecycle-loop + field-carousel
   - `rfc` → arch-flow (optional — ask user)
   - `post-mortem` → state-machine (failure path, optional — ask user)
   - `unknown` → ask: "What type of doc is this?" and map to the closest type above
3. Map each major section to the most appropriate SVG pattern based on the classified type
4. For each SVG to inject (incremental — skip in batch mode, process all automatically):
   - Check if `assets/<filename>.svg` already exists → if yes, ask: "An SVG with this name exists. Skip / Replace / Update?"
   - Generate SVG per blueprint in `references/awesome-docs.md`
   - Show to user — confirm before inserting (skip confirmation in batch mode)
   - Insert `<img src="assets/<filename>.svg" />` + `>` blockquote caption immediately after the matching section heading
5. Commit: `git add <doc-path> assets/ && git commit -m "feat(awesome-docs): animate <doc-filename>"`
   - In batch mode: single commit after all files: `git commit -m "feat(awesome-docs): animate docs in <dir>"`

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

Detect stale diagrams by comparing the current doc against a base ref.

**Syntax:** `/platform-skills:awesome-docs diff [--base <branch|tag|SHA>] <doc-path>`

If `--base` is omitted, defaults to `HEAD`.

Steps:
1. Ask: path to the doc (e.g. `docs/architecture.md`, `README.md`); optionally accept `--base <ref>` inline
2. Determine the base ref:
   - `--base` provided → use that ref directly
   - Not provided → use `HEAD`
3. Run: `git diff <base-ref> -- <doc-path>` to see what changed since the base ref
4. Scan for staleness signals:
   - Field count in YAML/config changed → field-carousel may be out of date
   - New component mentioned in prose but not in arch-flow SVG
   - Broken `<img>` reference (file in doc but not in `assets/`)
   - Section added/removed that would change which SVG patterns apply
   - New states or transitions described but not reflected in state-machine SVG
   - New actors or message steps described but not reflected in sequence-diagram SVG
5. Report a punch list: `[ ] <issue> — <file or section>` — do not auto-fix
6. Include the base ref used: `(diffed against <ref>)` at the top of the report
7. Suggest: "Run `/platform-skills:awesome-docs update` for each flagged diagram."

Reference: `references/awesome-docs.md` → Quality Checklist

---

## Mode: audit

Quality-check an existing animated doc without making changes.

Steps:
1. Ask: path to the doc
2. Check each applicable item in the Quality Checklist from `references/awesome-docs.md`:
   - Every SVG `<img>` tag has a `>` blockquote caption immediately after it
   - No environment-specific IDs, account numbers, or hostnames in the doc or SVG files
   - No SVG references a file outside `assets/` (no external `href`, no `xlink:href`)
   - All SVG files under 50KB (larger files may not render inline on GitHub)
3. Report findings as a numbered list: `[PASS]` or `[FAIL] — <what to fix>`
4. Print total: `X passed, Y failed`

Reference: `references/awesome-docs.md` → Quality Checklist, GitHub SVG Animation Constraints

---

## Mode: preview

Open the doc locally in a browser before committing.

Steps:
1. Ask: path to the doc
2. Start a minimal local HTTP server:
   ```bash
   python3 -m http.server 8080 --directory .
   ```
3. Tell the user the preview URL and how to open it:
   - macOS: `open http://localhost:8080/<doc-path>`
   - Linux: `xdg-open http://localhost:8080/<doc-path>`
   - Windows: `start http://localhost:8080/<doc-path>`
   - Or paste `http://localhost:8080/<doc-path>` directly into your browser
4. Tell the user: "Preview running at http://localhost:8080/<doc-path>. Press Ctrl+C to stop the server."

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
