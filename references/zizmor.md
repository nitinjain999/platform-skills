---
title: Zizmor
custom_edit_url: null
---

# Zizmor Reference

Covers all `/platform-skills:zizmor` mode logic: bootstrap, input collection, operating modes, personas, the full audit catalogue, `zizmor.yml` configuration, inline suppression, exit-code gating, auto-fix, CI integration, and pre-commit.

Zizmor is a static analysis tool for GitHub Actions. It reads workflow, composite action, Dependabot, and pre-commit definitions and reports security findings — template injection, credential persistence, unpinned `uses:`, over-broad permissions, impostor commits.

**Verified against zizmor `v1.29.0`, `zizmorcore/zizmor-action` `v0.6.2`, `zizmorcore/zizmor-pre-commit` `v1.29.0`.** Version-gated features are marked inline.

---

## Tool Ownership Boundary

Zizmor owns **workflow and action definition security**. It does not own anything that requires runtime state.

| Concern | Authoritative tool |
|---|---|
| Workflow / action definition security (injection, permissions, pinning) | **Zizmor** |
| Dependabot config security (`insecure-external-code-execution`, cooldown) | **Zizmor** |
| `.pre-commit-config.yaml` security (impostor commits, insecure URL schemes) | **Zizmor** |
| Workflow *syntax* and schema validity | `actionlint` — `/platform-skills:github-actions` |
| Shell correctness inside `run:` blocks | `shellcheck` (via `actionlint`) |
| Terraform / Kubernetes / Helm IaC misconfiguration | `checkov` — `/platform-skills:checkov` |
| Container image and dependency CVEs | `trivy` — `/platform-skills:trivy` |
| Composite action design, scaffolding, and `action.yml` contract review | `/platform-skills:composite-actions` |
| Keeping `uses:` SHAs current after pinning | `renovate` / Dependabot — `/platform-skills:renovate` |
| Image signing, SBOM, SLSA provenance | `/platform-skills:supply-chain` |

**Zizmor and actionlint are complements, not alternatives.** Actionlint answers "is this workflow valid?" Zizmor answers "is this workflow safe?" A workflow can be perfectly valid and still hand an attacker a shell. Run both.

### What zizmor structurally cannot see

State these limits before promising coverage — they drive every false-negative conversation:

- **Static analysis only.** Zizmor never executes a workflow. It cannot know what a `run:` script actually does at runtime, or what a third-party action does internally.
- **Definitions only.** Zizmor audits workflow and action *definitions*. It does not audit the code those definitions invoke — a `run: ./scripts/deploy.sh` is opaque.
- **YAML anchors** and **parallel steps** have documented analysis limitations. A finding's absence in a heavily anchored workflow is not proof of safety.

---

## Bootstrap

Prefer `uv` — it is the fastest path and needs no persistent install.

### One-shot, no install (recommended for ad-hoc runs)

```bash
# uvx runs a pinned zizmor without polluting the environment
uvx zizmor@1.29.0 --version
```

### macOS

```bash
brew install zizmor
```

### Python ecosystem

```bash
# pipx keeps zizmor isolated from project virtualenvs
pipx install zizmor

# or plain pip inside an activated venv
pip install zizmor
```

### Cargo

```bash
cargo install --locked zizmor
```

### Docker

```bash
# Pin the tag. `:latest` moves under you, so a CI run that passed yesterday
# can fail today on audits that did not exist when you wrote the gate.
docker pull ghcr.io/zizmorcore/zizmor:1.29.0

# Pin the digest where reproducibility matters. A tag is a mutable pointer;
# zizmor's own `unpinned-images` audit flags tag-only image references.
docker pull ghcr.io/zizmorcore/zizmor:1.29.0@sha256:863026d54f91271b10b60b67ad8054cb37120167e162482597db102b3026a284
```

Also packaged for conda-forge, Nix, Arch (`pacman -S zizmor`), and Alpine/Chimera (`apk add zizmor`).

### Minimum version guard

Several features referenced below are version-gated. Check before relying on them:

```bash
# Dot-field integer comparison — portable across macOS and Linux
# (sort -V is GNU-only and silently absent on stock macOS)
required="1.29.0"
have="$(zizmor --version 2>/dev/null | awk '{print $2}')"
[ -z "$have" ] && { echo "zizmor not installed"; exit 1; }

IFS=. read -r rmaj rmin rpat <<EOF
$required
EOF
IFS=. read -r hmaj hmin hpat <<EOF
$have
EOF

if [ "$hmaj" -lt "$rmaj" ] \
  || { [ "$hmaj" -eq "$rmaj" ] && [ "$hmin" -lt "$rmin" ]; } \
  || { [ "$hmaj" -eq "$rmaj" ] && [ "$hmin" -eq "$rmin" ] && [ "$hpat" -lt "$rpat" ]; }; then
  echo "zizmor $have is older than $required — upgrade before relying on version-gated flags"
  exit 1
fi
echo "zizmor $have OK"
```

**Feature floors worth knowing:**

| Feature | Minimum version |
|---|---|
| `--min-confidence` | v0.6.0 |
| Inline `# zizmor: ignore[...]` comments | v0.6.0 |
| `--persona=` / `--pedantic` | v0.7.0 |
| `--color=always\|never` | v1.5.0 |
| `--format=github`, `--format=json-v1` | v1.6.0 |
| `--strict-collection` | v1.7.0 |
| `--fix=[MODE]` | v1.10.0 (stable v1.15.0) |
| `rules.<id>.disable` | v1.13.0 |
| Exit code `3` (no inputs collected) | v1.21.0 |
| stdin input (`-`) | v1.24.0 |
| `rules.<id>.remap.severity` | v1.25.0 |
| `--no-ignores` | v1.25.0 |

---

## Input collection

Zizmor knows four input sources, and they can be mixed in one run:

| Source | Example |
|---|---|
| Individual files | `zizmor ci.yml my-action/action.yml .pre-commit-config.yaml` |
| Local directory | `zizmor .` |
| Remote GitHub slug | `zizmor pypa/sampleproject`, `zizmor example/example@v1`, `zizmor example/example@abababab` |
| Standard input | `cat workflow.yml \| zizmor -` (v1.24.0+) |

```bash
# One run, three sources
zizmor ../example.yml ../other-repo/ example/example
```

**Constraints that bite:**

- `-` (stdin) **cannot** be combined with other inputs, and `--fix` is unsupported with stdin.
- Remote slugs require online mode and a GitHub token.
- `--collect=` only governs *indirect* collection from repository sources. `zizmor --collect=actions workflow.yml` still audits `workflow.yml`, because it was passed explicitly.

### `--collect=`

```bash
zizmor --collect=all example/example              # ignore .gitignore patterns
zizmor --collect=default example/example          # respect .gitignore (the default)
zizmor --collect=workflows example/example
zizmor --collect=actions example/example
zizmor --collect=dependabot example/example
zizmor --collect=pre-commit example/example
zizmor --collect=workflows,actions example/example  # comma-combinable
```

`--collect=all` is materially slower on repos with large gitignored trees (`node_modules/`, `.terraform/`, build output). Do not default to it.

### `--strict-collection` (v1.7.0+)

By default zizmor **warns but does not fail** when an input fails to parse. In CI that is a silent coverage hole: a malformed workflow is skipped and the job stays green.

```bash
# Turn parse warnings into failures
zizmor --strict-collection .
```

Recommend `--strict-collection` for any CI gate. Without it, "0 findings" can mean "0 files audited".

---

## Operating modes: online vs offline

Three modes, and the default is **inferred from the environment** — this is the single most common source of "it found something in CI but not locally":

| Precedence | Condition | Mode |
|---|---|---|
| 1 | `ZIZMOR_OFFLINE` set | Offline |
| 2 | `GH_TOKEN` / `GITHUB_TOKEN` / `ZIZMOR_GITHUB_TOKEN` set | Online with audits |
| 2a | ...plus `ZIZMOR_NO_ONLINE_AUDITS` set | Online, fetch only, online audits skipped |
| 3 | None of the above | Offline |

Make it explicit rather than relying on ambient environment:

```bash
# Force offline even if a token is present
zizmor --offline .

# Explicit online — gh CLI token is the recommended local source
zizmor --gh-token "$(gh auth token)" .

# Fetch remote inputs, but run only offline audits
zizmor --no-online-audits --gh-token "$(gh auth token)" example/example
```

**Four audits are online-only** and silently do nothing offline: `impostor-commit`, `known-vulnerable-actions`, `ref-confusion`, `stale-action-refs`. If a review claims "zizmor is clean" from an offline run, that review did not check for impostor commits or known-vulnerable action versions.

**Offline mode also changes severities on audits that do run.** Since v1.17.0 `artipacked` downgrades its finding when `actions/checkout` is v6.0.0 or newer, because v6 moved the persisted credential to `$RUNNER_TEMP`. Resolving a SHA pin to a version needs the network, so a SHA-pinned `actions/checkout@<sha>  # v7.0.1` reports **medium** offline (zizmor assumes the pre-v6 worst case) and **low** online (zizmor confirms v7). In a repo that SHA-pins every checkout, that single difference moves every `artipacked` finding between severity buckets. Do not compare a local `--offline` total against a CI total and conclude something regressed — reproduce CI's mode first:

```bash
# Reproduce what CI sees, including severity assignment
GH_TOKEN="$(gh auth token)" zizmor --persona=regular .
```

### Token permissions

Zizmor generally needs **no special scopes** — the token exists mainly to lift API rate limits. Extra permissions are needed only for private inputs:

- `contents: read` for GitHub Actions tokens
- `repo` for OAuth tokens and classic PATs
- appropriate repository access for fine-grained PATs

Locally, use `gh auth token` rather than provisioning a PAT.

### Other GitHub hosts

`--gh-hostname` / `GH_HOST` targets GitHub Enterprise Server.

---

## Personas

`--persona=regular|pedantic|auditor` (v0.7.0+). `--pedantic` is an alias for `--persona=pedantic`.

| Persona | Intent | Where to use |
|---|---|---|
| `regular` (default) | High-signal, actionable security findings | Local dev, CI gates |
| `pedantic` | Adds code smells and intentional-but-noteworthy decisions | Pre-merge hygiene sweeps, repo cleanup |
| `auditor` | Everything, including likely false positives | Human security review only |

**Never gate CI on `auditor`.** It is explicitly documented as including likely false positives. Gate on `regular`; run `pedantic`/`auditor` as advisory or manual.

Personas nest: `auditor` ⊇ `pedantic` ⊇ `regular`. Raising the persona only ever adds findings.

---

## Filtering

```bash
zizmor --min-severity=medium .    # informational | low | medium | high
zizmor --min-confidence=medium .  # low | medium | high  (v0.6.0+)
zizmor --no-ignores .             # report findings even if ignored (v1.25.0+)
```

`--min-confidence=unknown` was deprecated in v1.14.0.

`--no-ignores` is the audit-the-auditors flag: it re-surfaces everything suppressed by `zizmor.yml` and inline comments. Run it periodically — suppressions rot.

---

## Exit codes

Gating depends entirely on getting this right:

| Code | Meaning |
|---|---|
| 0 | No findings (**or** SARIF mode — see below) |
| 1 | Error during the audit |
| 2 | Argument parsing failure |
| 3 | No inputs were collected (v1.21.0+) |
| 11 | Findings; worst is informational |
| 12 | Findings; worst is low |
| 13 | Findings; worst is medium |
| 14 | Findings; worst is high |

Codes 11–14 are **suppressed** in three situations:

1. `--no-exit-codes` was passed.
2. `--format=sarif` was used — SARIF consumers expect results in the document, not the exit status.
3. `--fix` ran and every finding was auto-fixed.

Exit code `10` (worst finding "unknown") was removed in v1.14.0.

### Severity-threshold gating in CI

```bash
# Fail only on medium or high; allow informational and low through.
zizmor --strict-collection . ; rc=$?
case "$rc" in
  0)     echo "✅ no findings" ;;
  11|12) echo "⚠️  informational/low findings only — not blocking" ;;
  13|14) echo "❌ medium or high findings — blocking"; exit 1 ;;
  3)     echo "❌ no inputs collected — check paths"; exit 1 ;;
  *)     echo "❌ zizmor failed (exit $rc)"; exit 1 ;;
esac
```

Prefer this over `--min-severity=medium`, because the run still *prints* the low findings for visibility while only failing on medium and above.

---

## Audit catalogue

41 audits. `Fix` = auto-fixable. `Online` = requires network + token. `Cfg` = has a `config:` block.

### Injection and code execution

| Audit | Catches | Type | Since | Online | Fix | Cfg |
|---|---|---|---|:-:|:-:|:-:|
| `template-injection` | `${{ }}` expansion into a code context (`run:`, `script:`) that may be attacker-controlled | Workflow, Action | v0.1.0 | – | ✅ | – |
| `github-env` | Dangerous writes to `GITHUB_ENV` / `GITHUB_PATH` | Workflow, Action | v0.6.0 | – | – | – |
| `insecure-commands` | `ACTIONS_ALLOW_UNSECURE_COMMANDS` enabled | Workflow, Action | v0.5.0 | – | ✅ | – |
| `dangerous-triggers` | Fundamentally dangerous triggers (`pull_request_target`, `workflow_run`) | Workflow | v0.1.0 | – | – | – |
| `adhoc-packages` | `run:` steps installing packages outside a locked manifest | Workflow, Action | v1.26.0 | – | – | – |
| `dependabot-execution` | `insecure-external-code-execution` in `dependabot.yml` | Dependabot | v1.15.0 | – | ✅ | – |

`template-injection` under `pedantic`/`auditor` flags **all** template expansions in code contexts, including provably safe ones like `${{ github.event_name }}`. That is why the default persona is the right CI gate.

### Supply chain and pinning

| Audit | Catches | Type | Since | Online | Fix | Cfg |
|---|---|---|---|:-:|:-:|:-:|
| `unpinned-uses` | `uses:` not pinned by SHA (blanket hash-pin policy since v1.20.0) | Workflow, Action | v0.4.0 | – | ✅ | ✅ |
| `impostor-commit` | A SHA that looks like it belongs to a repo but lives on a fork | Workflow, Action, pre-commit | v0.1.0 | ✅ | ✅ | – |
| `known-vulnerable-actions` | Action versions with published advisories | Workflow, Action | v0.1.0 | ✅ | ✅ | ✅ |
| `ref-confusion` | A ref ambiguous between branch and tag | Workflow, Action | v0.1.0 | ✅ | – | – |
| `ref-version-mismatch` | SHA pin whose `# vX.Y.Z` comment disagrees with the commit | Workflow, Action | v1.14.0 | – | ✅ | – |
| `stale-action-refs` | SHA pin that is no longer any released tag | Workflow, Action | v1.7.0 | ✅ | – | – |
| `typosquat-uses` | Slug that is a near-variant of a well-known action under a different owner | Workflow, Action | v1.26.0 | opt | – | – |
| `archived-uses` | `uses:` pointing at an archived repository | Workflow, Action | v1.19.0 | – | – | – |
| `forbidden-uses` | `uses:` outside an allowlist / inside a denylist | Workflow, Action | v1.6.0 | – | – | ✅ |
| `unpinned-images` | `container.image` with no tag, or `:latest` | Workflow, Action | v1.7.0 | – | – | – |
| `unpinned-tools` | Known actions fetching an unpinned external tool at runtime | Workflow, Action | v1.25.0 | – | – | – |
| `superfluous-actions` | Actions that duplicate tooling already in the runner image | Workflow, Action | v1.23.0 | – | – | – |
| `dependabot-cooldown` | Dependabot `cooldown.default-days` below threshold (or absent) | Dependabot | v1.15.0 | – | ✅ | ✅ |
| `insecure-url-scheme` | Insecure URL schemes — currently pre-commit `repo:` fields only | pre-commit | v1.29.0 | – | – | – |

`typosquat-uses` reports **low** confidence offline; a token raises it to **high** because zizmor can confirm whether the repo actually exists. Offline typosquat results are a lead, not a verdict.

`ref-version-mismatch` reports *missing* version comments only under `pedantic`. Under the default persona it reports only *wrong* comments.

`unpinned-images` reports missing/`latest` tags as regular findings; tag-but-not-SHA256 only under `pedantic`.

### Secrets and credentials

| Audit | Catches | Type | Since | Online | Fix | Cfg |
|---|---|---|---|:-:|:-:|:-:|
| `artipacked` | Credential persistence via `actions/checkout` default `persist-credentials: true` | Workflow | v0.1.0 | – | ✅ | – |
| `overprovisioned-secrets` | Whole-`secrets`-context sharing (`${{ toJSON(secrets) }}`) | Workflow, Action | v1.3.0 | – | – | – |
| `secrets-inherit` | `secrets: inherit` on reusable workflow calls | Workflow | v1.1.0 | – | – | – |
| `unredacted-secrets` | Structured secret access (`fromJSON(secrets.X).y`) that defeats log redaction | Workflow, Action | v1.4.0 | – | – | – |
| `hardcoded-container-credentials` | Docker registry username/password inline in the workflow | Workflow | v0.1.0 | – | – | – |
| `secrets-outside-env` | Secrets used outside a GitHub Environment | Workflow | v1.23.0 | – | – | ✅ |
| `github-app` | Dangerous use of GitHub App installation tokens | Workflow, Action | v1.25.0 | – | – | – |
| `use-trusted-publishing` | Packaging workflows using API tokens where OIDC Trusted Publishing exists | Workflow | v0.1.0 | – | – | – |

`secrets-outside-env` is **auditor-persona only** — fixing it means introducing Environments, which is an organizational change, not a code change. `GITHUB_TOKEN` is never flagged.

### Permissions and runner posture

| Audit | Catches | Type | Since | Online | Fix | Cfg |
|---|---|---|---|:-:|:-:|:-:|
| `excessive-permissions` | Over-broad `permissions:` at workflow or job level | Workflow | v0.1.0 | – | – | – |
| `undocumented-permissions` | `permissions:` entries with no explanatory comment | Workflow | v1.13.0 | – | – | – |
| `self-hosted-runner` | `runs-on:` a self-hosted runner | Workflow | v0.1.0 | – | – | – |
| `cache-poisoning` | Caching in a workflow that publishes artifacts or releases | Workflow | v0.10.0 | – | ✅ | – |
| `concurrency-limits` | Missing `concurrency:` on a workflow that needs it | Workflow | v1.16.0 | – | – | – |
| `bot-conditions` | Spoofable bot-actor conditions (`github.actor == 'dependabot[bot]'`) | Workflow | v1.2.0 | – | ✅ | – |

### Correctness and code smell

| Audit | Catches | Type | Since | Online | Fix | Cfg |
|---|---|---|---|:-:|:-:|:-:|
| `unsound-condition` | `if:` conditions that are always true (usually multi-line YAML + fenced expression) | Workflow, Action | v1.12.0 | – | ✅ | – |
| `unsound-contains` | Bypassable `contains()` allowlist checks | Workflow | v1.7.0 | – | – | – |
| `unsound-ternary` | `cond && value \|\| fallback` where `value` can be falsy | Workflow, Action | v1.26.0 | – | – | – |
| `obfuscation` | Obfuscated use of Actions features | Workflow, Action | v1.7.0 | – | ✅ | – |
| `misfeature` | Features considered misfeatures (e.g. non-well-known shells) | Workflow, Action | v1.21.0 | – | ✅ | – |
| `self-repository` | In-repo actions/reusable workflows not using the self-repository syntax | Workflow, Action | v1.30.0 | – | ✅ | – |
| `anonymous-definition` | Workflow or action with no `name:` | Workflow, Action | v1.10.0 | – | – | – |

`unsound-condition` is the highest-value audit in this group. A silently always-true `if:` means a guard you believe is protecting a privileged job is not protecting anything.

`self-repository` is documented as `v1.30.0` — newer than the `v1.29.0` release this reference is verified against. Do not promise it until `zizmor --version` reports v1.30.0 or later.

### Persona gating summary

Findings **not** visible under the default persona:

| Audit | Requires |
|---|---|
| `anonymous-definition` | `pedantic` or `auditor` |
| `concurrency-limits` | `pedantic` or `auditor` |
| `self-hosted-runner` | `pedantic` or `auditor` |
| `stale-action-refs` | `pedantic` or `auditor` (plus online) |
| `undocumented-permissions` | `pedantic` or `auditor` |
| `secrets-outside-env` | `auditor` |
| `ref-version-mismatch` — *missing* version comment | `pedantic` or `auditor` |
| `template-injection` — provably-safe expansions | `pedantic` or `auditor` |
| `unpinned-images` — tag present but not SHA256 | `pedantic` or `auditor` |
| `misfeature` — non-well-known-shell findings | `auditor` |

### Auto-fixable audits

Available in the v1.29.0 baseline: `artipacked`, `bot-conditions`, `cache-poisoning`, `dependabot-cooldown`, `dependabot-execution`, `impostor-commit`, `insecure-commands`, `known-vulnerable-actions`, `misfeature`, `obfuscation`, `ref-version-mismatch`, `template-injection`, `unpinned-uses`, `unsound-condition`.

Auto-fixable but **not** in the v1.29.0 baseline: `self-repository` (v1.30.0+). `--fix` will not touch it on an older binary, so do not count it toward what a fix run will clean up.

---

## Auto-fix

`--fix[=safe|all|unsafe-only]` (v1.10.0+, stable v1.15.0). Default is `safe`.

```bash
zizmor --fix .              # equivalent to --fix=safe
zizmor --fix=safe .         # low-breakage-risk fixes only
zizmor --fix=all .          # safe + unsafe
zizmor --fix=unsafe-only .  # unsafe only
```

Auto-fixable findings carry a `= note: this finding has an auto-fix` line in plain output.

**Blast radius — read before running:**

- **In-place modification.** `--fix` rewrites your files. There is no `--dry-run`. Run it on a clean working tree so `git diff` *is* the review artifact.
- **No remote fixes.** `--fix` cannot operate on remote slugs, and is unsupported with stdin.
- **Format preservation is heuristic.** Indentation and comments are usually preserved, but not guaranteed to match house style.
- **Some fixes need the network.** `unpinned-uses` *detects* offline but needs a token to resolve the SHA it pins to. Running `--fix` offline silently fixes less than you think.
- **`--fix` masks exit codes.** If every finding is fixed, zizmor exits 0. Never use `--fix` inside a gate — a gate that repairs its own input always passes.
- **Unsafe fixes require human review** for semantic correctness. `--fix=all` in an unattended context is how a workflow quietly changes behaviour.

**Safe workflow:**

```bash
git status --porcelain | grep -q . && { echo "commit or stash first"; exit 1; }
zizmor --fix=safe --gh-token "$(gh auth token)" .
git --no-pager diff        # review every hunk
zizmor .                   # re-audit: what remains needs a human
```

---

## Configuration: `zizmor.yml`

Configuration is always optional and can always be bypassed with `--no-config`.

### Discovery

Two distinct mechanisms — behaviour changed in v1.13.0 and again in v1.29.0.

**Global discovery** — `--config <path>` or `ZIZMOR_CONFIG`. That one file applies to **all** inputs, and **no other config file is loaded**, even if a local one exists. Use it for org-wide policy; be aware it silently overrides in-repo config.

**Local discovery** (the default, and what most repos want):

| Input situation | Search order |
|---|---|
| Input inside a Git repo | Starts **and ends** at the repo root: `.github/zizmor.yml` → `.github/zizmor.yaml` → `zizmor.yml` → `zizmor.yaml` |
| File input, not in a repo | Directory discovery from the file's own directory |
| Directory input, not in a repo | `<dir>/.github/zizmor.y{a,}ml` → `<dir>/zizmor.y{a,}ml` → then each parent, up to the filesystem root or the first `.git/` |
| Remote slug | `.github/zizmor.y{a,}ml` or `zizmor.y{a,}ml` at the repo root |

Two traps:

1. **In a Git repo, discovery does not walk upward from the input.** It jumps straight to the repo root. A `zizmor.yml` in a subdirectory of a Git repo is never read.
2. **`zizmor .github/workflows/` is special-cased** to begin discovery two levels up, specifically so a `zizmor.yml` *config* is not confused with a `zizmor.yml` *workflow*.

Canonical location for a repo: **`.github/zizmor.yml`**.

A JSON Schema ships at `support/zizmor.schema.json` in the zizmor repo and is mirrored on SchemaStore, so SchemaStore-aware editors validate the file automatically.

### Schema

Exactly one top-level key: `rules`, mapping audit id → settings.

```yaml
# .github/zizmor.yml
rules:
  <audit-id>:
    disable: <bool>          # v1.13.0+
    ignore:                  # list of filename.yml[:line[:column]]
      - <rule>
    config: {...}            # per-audit; only 5 audits accept this
    remap:
      severity: <level>      # v1.25.0+
```

### `ignore` — the preferred suppression

```yaml
rules:
  template-injection:
    ignore:
      # line 100 in ci.yml, any column
      - ci.yml:100
      # every finding in tests.yml
      - tests.yml
  use-trusted-publishing:
    ignore:
      # exactly line 12, column 10
      - pypi.yml:12:10
```

Rules and gotchas:

- The filename is the **base filename only** — not a path. `release.yml` matches every `release.yml` in scope.
- `line` and `column` are **1-based**. Omitting the column widens to the whole line; omitting both widens to the whole file.
- **No wildcards.** `*.yml` is not a valid ignore rule.
- **Composite action findings cannot be ignored here.** Use an inline comment instead.
- Line-pinned ignores are fragile: inserting a step above shifts every line number and silently re-scopes the suppression. Prefer an inline comment for anything that lives in a file under active edit.

### `disable` — last resort

```yaml
rules:
  template-injection:
    disable: true
```

The docs call this a **measure of last resort**, and the reason is operational: disabled rules do not appear in ignored or suppressed counts, so new findings from that audit are invisible forever. Before disabling, try in order:

1. `ignore` the specific findings.
2. Drop back to a less sensitive persona (remove `--persona=pedantic` / `auditor`).
3. Only then `disable`.

### `remap.severity` (v1.25.0+)

```yaml
rules:
  artipacked:
    remap:
      severity: high   # informational | low | medium | high
```

Applied **blanket**: remapping to `high` re-grades that audit's `low` *and* `medium` findings to `high`. Useful to promote an audit your org treats as release-blocking above a `--min-severity` threshold. Also usable downward, to demote a noisy audit below the gate instead of disabling it — a strictly better option than `disable`, because findings still count.

### Per-audit `config`

Only five audits accept `config:`.

#### `unpinned-uses`

```yaml
rules:
  unpinned-uses:
    config:
      policies:
        actions/checkout: hash-pin
        actions/*: ref-pin
```

Policies: `hash-pin` (SHA required), `ref-pin` (tag/branch/SHA all acceptable), `any` (no pinning required — for repository `uses:` this behaves like `ref-pin`, since GitHub does not permit truly unpinned repository actions).

Most specific match wins, **regardless of definition order**. Any `uses:` matching no rule gets an implicit `"*": hash-pin`. Override that with your own `"*"` rule.

```yaml
rules:
  unpinned-uses:
    config:
      policies:
        "example/*": hash-pin
        "*": ref-pin
```

Since v1.20.0 the default is blanket hash-pinning for **all** actions, including `actions/*`. Pre-v1.20.0 behaviour (first-party actions allowed to be ref-pinned) is opt-in via config now. Expect a large finding count on the first run against a repo that predates this.

**Which policy to choose.** `hash-pin` is the recommendation, and it is also the default — so the honest reason to write a `policies:` block at all is to *relax* it for specific namespaces, or to record the decision explicitly for reviewers.

| Policy | What you are trusting | Use when |
|---|---|---|
| `hash-pin` | Nothing. A SHA is immutable, so the code that ran is provable after the fact. | Default. Every third-party action. Anything touching secrets, OIDC, or a deploy. |
| `ref-pin` | The tag owner not to move the tag. `v4` is designed to move; even `v4.2.1` can be force-updated. | Namespaces the org owns and protects tags on. Record *why* in a comment. |
| `any` | Same as `ref-pin` for repository `uses:`. | Rarely useful — prefer `ref-pin` so the intent reads correctly. |

A tag pin is a mutable pointer: the author can repoint it at different code after review, and the next workflow run executes that code with the same permissions and secrets. That is the whole attack, and it is why the default changed. Relaxing to `ref-pin` is a deliberate trust decision — not a way to clear findings.

The counter-argument to hash-pinning is legitimate and worth stating: a SHA carries no version information and never receives patches on its own. Answer it with automation, not with `ref-pin` — pin the SHA, add a `# vX.Y.Z` trailing comment (which `ref-version-mismatch` then keeps honest), and let Renovate or Dependabot bump both. Without that, hash pins rot into `stale-action-refs` and unpatched advisories, which is a worse position than a ref pin that at least tracks patch releases.

#### `forbidden-uses`

Allowlist **or** denylist, not both:

```yaml
# Allowlist: only these are permitted; everything else is a finding
rules:
  forbidden-uses:
    config:
      allow:
        - actions/*
        - github/codeql-action/*
```

```yaml
# Denylist: everything permitted except these
rules:
  forbidden-uses:
    config:
      deny:
        - actions/*
        - github/codeql-action/*
```

This audit does nothing until configured — it has no default policy.

#### `known-vulnerable-actions` (config v1.26.0+)

```yaml
rules:
  known-vulnerable-actions:
    config:
      allow:
        - GHSA-5wxr-w449-57cm
```

Suppresses by **advisory ID**. The docs are emphatic: understand the vulnerability fully before allowlisting. Default is empty — all known vulnerabilities produce findings.

#### `secrets-outside-env` (config v1.24.0+)

```yaml
rules:
  secrets-outside-env:
    config:
      allow:
        - CI_COVERAGE_TOKEN
        - NOT_VERY_SENSITIVE
```

Allowlist by secret name. `GITHUB_TOKEN` is never flagged.

#### `dependabot-cooldown`

```yaml
rules:
  dependabot-cooldown:
    config:
      days: 7   # minimum acceptable cooldown.default-days; default 7
```

### Repository patterns

Used by `unpinned-uses.policies` and `forbidden-uses`. Ordered by specificity — most specific always wins:

| Pattern | Matches |
|---|---|
| `owner/repo/subpath@ref` | Exact repo + subpath + ref. `github/codeql-action/init@v2` matches `@v2`, not `@main`. Subpath optional. |
| `owner/repo/subpath` | Exact `owner/repo/subpath`, any ref. Subpath is **not** optional here. `github/codeql-action/init` does not match `github/codeql-action@v2`. |
| `owner/repo` | Exact `owner/repo`, any ref. `actions/cache` does **not** match `actions/cache/save@v3`. |
| `owner/repo/*` | Any subpath or ref under that repo, **including** the bare repo itself. |
| `owner/*` | Any repo under that owner. |
| `*` | Everything. |

The `owner/repo` vs `owner/repo/*` distinction is the one that catches people: `actions/cache` will not cover `actions/cache/restore`.

### Worked baseline config

A realistic `.github/zizmor.yml` for a platform repo that vendors third-party actions:

```yaml
# .github/zizmor.yml
# Schema: https://raw.githubusercontent.com/woodruffw/zizmor/main/support/zizmor.schema.json
rules:
  unpinned-uses:
    config:
      policies:
        # Reusable workflows in our own org are governed by branch protection,
        # so a tag pin is an accepted risk here.
        our-org/*: ref-pin
        # Everything else, including actions/*, must be SHA-pinned.
        "*": hash-pin

  # Promoted above our CI gate: credential persistence is release-blocking
  # for us because our runners are shared across repos.
  artipacked:
    remap:
      severity: high

  template-injection:
    ignore:
      # Reviewed 2026-08-29: expansion is a workflow_dispatch input restricted
      # to maintainers by the environment protection rule on `release`.
      - release.yml:42

  # Demoted rather than disabled — findings still count and stay visible
  # under --no-ignores, but no longer block the medium-severity gate.
  undocumented-permissions:
    remap:
      severity: informational
```

---

## Inline suppression

`# zizmor: ignore[rulename]` (v0.6.0+). Comma-separate multiple audits.

```yaml
run: | # zizmor: ignore[template-injection]
  echo "${{ github.event.issue.title }}"
```

```yaml
- uses: some/action@abcdef  # zizmor: ignore[artipacked,ref-confusion]
```

With a trailing justification — always write one:

```yaml
run: | # zizmor: ignore[template-injection] input is maintainer-only via environment gate
  echo "${{ inputs.tag }}"
```

**The placement rule that costs people an hour:** the comment must sit anywhere inside the span the finding identifies **and** be parseable as a YAML comment. Inside a block literal it is just text, not a comment.

```yaml
# ❌ Not suppressed — the "comment" is part of the string
run: |
  echo "${{ github.event.issue.title }}" # zizmor: ignore[template-injection]

# ✅ Suppressed — comment is on the `run:` key, outside the literal
run: | # zizmor: ignore[template-injection]
  echo "${{ github.event.issue.title }}"
```

**Use inline comments when:** the finding is in a composite action (`zizmor.yml` cannot ignore those), the justification is location-specific, or the file changes often enough that line-pinned config ignores would drift.

**Use `zizmor.yml` when:** suppressing many findings, whole files, or applying org-wide policy.

Audit both periodically with `zizmor --no-ignores .` (v1.25.0+).

---

## Output formats

`--format=plain|json|json-v1|sarif|github`. `github` and `json-v1` require v1.6.0+.

| Format | Use for |
|---|---|
| `plain` (default) | Human reading — cargo-style annotated source |
| `json` | Ad-hoc scripting. Not schema-stable — do not build on it |
| `json-v1` | Stable JSON schema. Use this for any tooling you intend to keep |
| `sarif` | GitHub code scanning / Advanced Security upload |
| `github` | GitHub Actions workflow annotations (inline PR comments) |

Related flags: `--show-audit-urls=always|never` (v1.19.0+) controls the docs links under each finding; `--color=always|never` (v1.5.0+), plus `NO_COLOR` / `FORCE_COLOR` / `CLICOLOR_FORCE`.

`--cache-dir` (also `$XDG_CACHE_DIR`) persists online-audit data between runs — worth setting in CI to reduce API calls.

---

## CI integration

### Option A — `zizmorcore/zizmor-action` (recommended)

The action wraps install, run, and SARIF upload. It internally pins the zizmor version it installs, so it does **not** trip the `unpinned-tools` audit.

```yaml
# .github/workflows/zizmor.yml
name: zizmor

on:
  push:
    branches: [main]
  pull_request:

# Least privilege at the top; widen only where needed.
permissions: {}

jobs:
  zizmor:
    name: Audit workflows
    runs-on: ubuntu-latest
    permissions:
      # Required to publish SARIF to the Security tab.
      security-events: write
      # Private repos only — public repos do not need these.
      # contents: read
      # actions: read
    steps:
      - name: Checkout
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          # zizmor never needs the credential, and leaving it persisted is
          # exactly what the artipacked audit flags.
          persist-credentials: false

      - name: Run zizmor
        uses: zizmorcore/zizmor-action@3dc1ecc9bcb9e94e9b2c709687979e1298497054  # v0.6.2
```

Full input surface (v0.6.2):

| Input | Default | Notes |
|---|---|---|
| `inputs` | `"."` | Whitespace-separated, split with shell rules |
| `collect` | `default` | Action's own docs list `all`, `default`, `workflows`, `actions`, `dependabot`. The value is passed verbatim to `--collect=`, so `pre-commit` and comma-combined lists also work |
| `online-audits` | `"true"` | |
| `persona` | `regular` | `regular`, `pedantic`, `auditor` |
| `min-severity` | — | `unknown`, `informational`, `low`, `medium`, `high` |
| `min-confidence` | — | `unknown`, `low`, `medium`, `high` |
| `version` | `latest` | Pin this for reproducible CI |
| `token` | `${{ github.token }}` | |
| `advanced-security` | `"true"` | Uses SARIF and uploads to the Security tab |
| `color` | `"true"` | |
| `annotations` | `"false"` | **Mutually exclusive with `advanced-security: true`** |
| `config` | — | Path to a `zizmor.yml` |
| `fail-on-no-inputs` | `"true"` | Needs zizmor v1.21.0+ (exit code 3) |

Output: `output-file` — path to the generated SARIF.

**Two things to get right:**

1. **`annotations: true` requires `advanced-security: false`.** Setting both is a configuration error, not a merge. If you want inline PR annotations instead of Security-tab alerts, set both explicitly:

   ```yaml
   - uses: zizmorcore/zizmor-action@3dc1ecc9bcb9e94e9b2c709687979e1298497054  # v0.6.2
     with:
       advanced-security: false
       annotations: true
   ```

2. **`advanced-security: true` means SARIF, and SARIF means exit codes 11+ are suppressed.** The job goes green even with high-severity findings. Findings land as code-scanning alerts, and blocking merges is then a **ruleset / branch-protection** decision, not a workflow-exit decision. If you want the job itself to fail, use Option B, add a second non-SARIF run, or gate on the SARIF you already have (Option D).

3. **The action exposes no `--strict-collection` input.** So the usual guardrail — turn parse warnings into failures, so "0 findings" cannot mean "0 files audited" — is not available here. `fail-on-no-inputs: true` (the default) covers the worst case by surfacing exit code 3 when *nothing* was collected, but a single malformed workflow inside a larger set is still skipped with a warning. If that distinction matters, use Option B.

Pin `version` for reproducibility:

```yaml
      - uses: zizmorcore/zizmor-action@3dc1ecc9bcb9e94e9b2c709687979e1298497054  # v0.6.2
        with:
          version: 1.29.0
          config: .github/zizmor.yml
```

### Option B — hard-failing gate via `uvx`

Use this when you want the check itself red on findings.

```yaml
# .github/workflows/zizmor.yml
name: zizmor

on:
  push:
    branches: [main]
  pull_request:

permissions: {}

jobs:
  zizmor:
    name: Audit workflows
    runs-on: ubuntu-latest
    env:
      ZIZMOR_VERSION: 1.29.0
    steps:
      - name: Checkout
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          persist-credentials: false

      - name: Install uv
        uses: astral-sh/setup-uv@20cfd1bf945f4377ade1205e4dbc17946fc9a30d  # v10.0.1

      - name: Run zizmor
        env:
          # Enables the four online-only audits: impostor-commit,
          # known-vulnerable-actions, ref-confusion, stale-action-refs.
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          # --strict-collection turns parse warnings into failures, so a
          # malformed workflow cannot be silently skipped into a green run.
          set +e
          uvx "zizmor@${ZIZMOR_VERSION}" --strict-collection .
          rc=$?
          set -e

          case "$rc" in
            0)     echo "✅ no findings" ;;
            11|12) echo "⚠️  informational/low findings only — not blocking" ;;
            13|14) echo "❌ medium or high findings"; exit 1 ;;
            3)     echo "❌ no inputs collected — check the path"; exit 1 ;;
            *)     echo "❌ zizmor failed (exit $rc)"; exit 1 ;;
          esac
```

### Option C — both: SARIF alerts *and* a failing check

```yaml
      - name: Generate SARIF
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: uvx "zizmor@${ZIZMOR_VERSION}" --strict-collection --format=sarif . > results.sarif

      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@cdf488f595d80d6e07e03d4674febd5ab45fa938  # v4.37.9
        with:
          sarif_file: results.sarif
          category: zizmor

      # Second pass, non-SARIF, so exit codes 11+ are live and can gate.
      - name: Gate on severity
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set +e
          uvx "zizmor@${ZIZMOR_VERSION}" --strict-collection --min-severity=medium .
          rc=$?
          set -e
          [ "$rc" -eq 0 ] || { echo "❌ medium+ findings"; exit 1; }
```

This job needs `security-events: write` for the upload step.

### Option D — one run: SARIF alerts, a PR comment, and a gate you control

Options B and C run zizmor twice: once for SARIF, once with live exit codes so something can fail. That is wasteful and, worse, the two runs can disagree if anything changes between them.

The SARIF already carries the severity, so a single run is enough. Every zizmor result includes:

```json
"properties": {
  "zizmor/severity": "High",
  "zizmor/confidence": "Low",
  "zizmor/persona": "Regular"
}
```

Parse that and you own the threshold, in one place, without a second audit.

```yaml
      - name: Run zizmor
        id: zizmor
        uses: zizmorcore/zizmor-action@3dc1ecc9bcb9e94e9b2c709687979e1298497054  # v0.6.2
        with:
          version: 1.29.0
          inputs: .
          advanced-security: true   # SARIF -> Security tab, and exposes output-file
          fail-on-no-inputs: true

      - name: Gate on severity
        env:
          SARIF_FILE: ${{ steps.zizmor.outputs.output-file }}
          # none | informational | low | medium | high
          FAIL_ON: high
        run: |
          set -euo pipefail
          [ "${FAIL_ON}" = "none" ] && exit 0

          n=$(jq --arg want "${FAIL_ON}" '
            {high: 4, medium: 3, low: 2, informational: 1}[$want] as $t
            | {High: 4, Medium: 3, Low: 2, Informational: 1} as $rank
            | [ .runs[0].results[]
                | select(($rank[.properties["zizmor/severity"]] // 0) >= $t) ]
            | length
          ' "${SARIF_FILE}")

          [ "$n" -eq 0 ] || { echo "::error::${n} finding(s) at or above ${FAIL_ON}"; exit 1; }
```

The same SARIF drives a PR comment. Group by severity and by path prefix so the comment says something a reviewer can act on, cap the table, and leave the long tail in the Security tab. Use `github.paginate` when looking for your own previous comment — `listComments` returns 30 by default, so on a busy PR the marker is never found and you post a fresh comment on every push.

**Rolling this out on a repository that has never run zizmor.** Do not start blocking. A first run on an established repo typically returns tens to hundreds of findings, most of them `artipacked` and `template-injection`; a gate that fails every PR from day one gets routed around, not fixed. Ship it advisory, with one knob:

```yaml
env:
  # Raise to `high` once .github/workflows is clean, then to `medium`.
  ZIZMOR_FAIL_ON: none
```

State the mode in the PR comment itself — "advisory, does not block the merge" — so nobody reads a green check as an all-clear. Then burn the backlog down by audit, not by file: every `artipacked` finding is one `persist-credentials: false`, and `--fix=safe` handles a large share of them in a single commit.

This repository's own [`.github/workflows/zizmor.yml`](https://github.com/nitinjain999/platform-skills/blob/main/.github/workflows/zizmor.yml) is the working version of this pattern.

---

## pre-commit

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/zizmorcore/zizmor-pre-commit
    rev: v1.29.0
    hooks:
      - id: zizmor
```

Notes:

- The hook scans the whole repository by default, so `files:` is optional.
- Works with `prek` as well as `pre-commit`.
- The hook runs in whatever operating mode the local environment implies. Without a token it is **offline**, so the four online-only audits do not run locally. That is a reasonable trade for hook latency, but it means pre-commit passing is not equivalent to CI passing. Say so when you install it.
- `rev:` is a mutable git tag from zizmor's perspective, but pre-commit resolves and caches it. Bump it via Renovate — see `/platform-skills:renovate`.

Zizmor also audits `.pre-commit-config.yaml` files themselves (`impostor-commit`, `insecure-url-scheme`), so a repo with pre-commit gets extra coverage for free via `--collect=pre-commit`.

---

## Triage decision tree

For each finding, in order:

1. **Is it a true positive?** If genuinely a false positive, report it upstream rather than suppressing it — the docs ask for this explicitly.
2. **Is it auto-fixable?** (`= note: this finding has an auto-fix`) → `--fix=safe`, review the diff, commit.
3. **Is the fix mechanical but unsafe-classified?** → `--fix=all` on a clean tree, review every hunk manually, or hand-apply.
4. **Is it real but accepted?** → suppress with a **written justification**:
   - one-off, or in a composite action → inline `# zizmor: ignore[...]` comment
   - many findings, or whole files → `zizmor.yml` `ignore`
   - noisy audit you still want counted → `remap.severity` downward, not `disable`
   - genuinely inapplicable audit → `disable`, last resort only
5. **Is it real, accepted, and org-wide?** → global config via `--config`, and document that in-repo configs are then ignored.

Never suppress without a reason string. A bare ignore is indistinguishable from an accident six months later.

---

## Common mistakes

| Mistake | Consequence | Fix |
|---|---|---|
| Running offline and calling the repo clean | `impostor-commit`, `known-vulnerable-actions`, `ref-confusion`, `stale-action-refs` never ran | `--gh-token "$(gh auth token)"`, or `GH_TOKEN` in CI |
| Gating on `--format=sarif` exit status | Exit codes 11+ suppressed; job green with high findings | Separate SARIF upload from a non-SARIF gating run |
| Using `--fix` inside a CI gate | Every finding is fixed, exit code masked, gate always passes | `--fix` locally only; gate re-audits |
| Omitting `--strict-collection` | Malformed workflows skipped with a warning; "0 findings" means "0 audited" | Add `--strict-collection` to every CI invocation |
| Gating on `--persona=auditor` | Documented to include likely false positives; team stops trusting the check | Gate on `regular`; run `pedantic`/`auditor` advisory |
| `annotations: true` with default `advanced-security` | Mutually exclusive inputs; misconfiguration | Set `advanced-security: false` explicitly |
| `zizmor.yml` in a subdirectory of a Git repo | Never read — in-repo discovery starts and ends at the repo root | Move to `.github/zizmor.yml` |
| Wildcards in `ignore` (`*.yml:10`) | Not supported; rule silently matches nothing | Use base filenames, or an inline comment |
| Ignore comment inside a block literal | Treated as string content, not a comment; no suppression | Put the comment on the `run:` key line |
| `ignore: ci.yml:100` on an actively edited file | Line numbers shift; suppression silently re-scopes | Inline comment on the construct itself |
| `disable: true` to quiet noise | Findings vanish from suppressed counts; new ones invisible forever | `ignore`, lower persona, or `remap.severity` down |
| Expecting `actions/cache` to cover `actions/cache/save` | Bare `owner/repo` is exact-match; subpaths unmatched | Use `actions/cache/*` |
| `--config` to add one rule | Disables all local discovery; in-repo `zizmor.yml` silently ignored | Edit the in-repo config instead |
| SHA-pinning everything, then never updating | Pins rot into `stale-action-refs` and unpatched CVEs | Pair pinning with Renovate or Dependabot |
| Treating zizmor as a replacement for actionlint | Syntax errors and shell bugs go uncaught | Run both — see `/platform-skills:github-actions` |

---

## Cross-references

- `/platform-skills:github-actions` — workflow design, `actionlint` syntax validation, OIDC, token scoping, failing-workflow debug
- `/platform-skills:composite-actions` — composite action scaffolding, `action.yml` review, hardening
- `/platform-skills:renovate` — keep the SHA pins zizmor demands from going stale
- `/platform-skills:checkov` — Terraform, Kubernetes, Helm, and Dockerfile IaC misconfiguration
- `/platform-skills:trivy` — container image, filesystem, and repo CVE + secret scanning
- `/platform-skills:supply-chain` — Cosign signing, SBOM, SLSA provenance
- `/platform-skills:preflight` — production-readiness sweep across mixed file types
- `/platform-skills:pr-review` — PR-level review including rollback feasibility and ownership
- `/platform-skills:commit` — conventional commit message for the resulting fix
