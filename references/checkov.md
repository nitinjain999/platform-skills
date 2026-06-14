# Checkov Reference

## Contents

- Hard safety rules
- Bootstrap (install, version check, jq)
- Pre-commit generation
- Multi-root Terraform detection
- Cloud provider detection
- Private GitHub module authentication
- Non-interactive flags (CI/automation)
- Scan modes (static, plan)
- Output formats
- Secrets scanning
- Multi-framework scanning
- Baseline mode
- Fix mode
- Post-fix validation
- Scaffold mode (.checkov.yaml, custom checks, compliance profiles)
- Common mistakes
- Exit code handling
- Rollback and cleanup

---

## Hard safety rules

These rules are non-negotiable. Every implementation path must honour them.

| Rule | Rationale |
|---|---|
| Never run `terraform init --upgrade` by default | Upgrades mutate `.terraform.lock.hcl`; a security scan must not change the dependency graph behind the developer's back. Only run `--upgrade` when the user passes `--upgrade` explicitly. |
| Always target the selected root via `terraform -chdir=<root>` | Prevents the wrong state from being planned when the CWD differs from the Terraform root. Never `cd` into the root — use `-chdir` so the shell's working directory is unchanged and the script stays re-entrant. |
| Always install `trap cleanup EXIT INT TERM` before generating plan files | Plan files may contain secrets. A trap ensures `tfplan.binary` and `tfplan.json` are deleted even on error, Ctrl+C, or SIGTERM. Only skip deletion when `--keep-plan` is explicitly set. |
| Never report CLEAN when Checkov exits 2 | Exit 2 means a tool error — bad flag, version mismatch, parse failure. Treating it as CLEAN silently passes a broken gate. Always emit `Result: ERROR` and exit non-zero. |
| No implicit network calls — local by default | Several Checkov operations hit the network: `--download-external-modules` fetches remote modules, `sca_package`/`sca_image` call a vulnerability DB, `--upload-sarif` posts to GitHub. Locally, default to no upload and no SCA. In CI, all networked operations must be explicit flags. Never enable `--download-external-modules` or SCA frameworks silently. |
| Never print or log tokens | `GITHUB_PAT=$(gh auth token)` must never be echoed. Scope the export to the Checkov process only (`GITHUB_PAT="..." checkov ...`) rather than exporting it to the whole shell session. |
| Use `git rev-parse --show-toplevel` for repo-root operations | Terraform root and git root are not always the same (e.g., `--root terraform/aws`). `.gitignore` updates, SARIF upload `git` calls, and output-path decisions must resolve the repo root independently. |

---

## Bootstrap

On every invocation, check `checkov --version` before scanning.

### Install

| Platform | Detection | Command |
|---|---|---|
| macOS | `uname -s` = Darwin | `brew install checkov` |
| Alpine | `/etc/alpine-release` exists | `pip3 install --upgrade pip setuptools && pip3 install checkov` |
| Debian 12+ / Ubuntu | `pip3` available, no `brew` | `python3 -m venv ~/.checkov-venv && source ~/.checkov-venv/bin/activate && pip install checkov && sudo ln -s ~/.checkov-venv/bin/checkov /usr/local/bin/checkov` |
| Other Linux | fallback | `pip3 install checkov` |

### Minimum version

Run `checkov --version` after install. Required minimums:

| Feature | Minimum version |
|---|---|
| `--deep-analysis`, `--repo-root-for-plan-enrichment` | 2.3.0 |
| `--create-baseline` | 2.2.0 |

If below minimum:
- macOS: `brew upgrade checkov`
- Linux: `pip3 install -U checkov`

> **Version comparison:** `sort -V` is a GNU coreutils flag not available on default macOS `sort`. Use Python for portable version comparison — Python 3 ships on all target platforms:
> ```bash
> python3 -c "import sys; v='$CHECKOV_VERSION'; r='2.3.0'; sys.exit(0 if tuple(int(x) for x in v.split('.')) >= tuple(int(x) for x in r.split('.')) else 1)"
> ```

### jq (plan mode only)

`jq` is required — without it, `terraform show -json` outputs single-line JSON and all findings report at line 0.

Check: `which jq`

Install if missing:
- macOS: `brew install jq`
- Debian/Ubuntu: `apt-get install -y jq`
- Alpine: `apk add jq`

Abort plan mode with a clear message if `jq` cannot be installed.

### Exit code handling

| Exit code | Meaning | Action |
|---|---|---|
| `0` | All checks passed | Report CLEAN |
| `1` | One or more checks failed | Report findings, offer fix mode |
| `2` | Tool error (bad flag, version mismatch, parse failure) | Surface error message — do NOT report as CLEAN |

In `--bot` mode, exit code `2` must emit `Result: ERROR` — a silent tool failure must never pass the gate.

---

## Pre-commit generation

Runs after bootstrap if `which pre-commit` succeeds. Silent skip if not found.

1. Check `.pre-commit-config.yaml` for existing `bridgecrewio/checkov` entry
2. If absent, auto-append — do NOT overwrite existing hooks
3. Offer `checkov_diff` variant (scans only staged/changed files) as an alternative
4. Run `pre-commit install --install-hooks` after writing

**Hook block to append:**

```yaml
  - repo: https://github.com/bridgecrewio/checkov.git
    rev: 3.2.451  # pinned at scaffold time — run: pip index versions checkov 2>/dev/null | head -1
    hooks:
      - id: checkov
        args:
          - --framework
          - terraform
          - --download-external-modules
          - "true"
```

Use `checkov_diff` instead of `checkov` to scan only changed files.

---

## Multi-root Terraform detection

Before scanning, find all directories containing `.tf` files (excluding `.terraform/`):

```bash
find . -name "*.tf" -not -path "*/.terraform/*" | sed 's|/[^/]*\.tf$||' | sort -u
```

If multiple roots found:

```
Multiple Terraform roots detected:
  1. terraform/aws/
  2. terraform/azure/
  3. terraform/gcp/
  4. All (run sequentially)  [default]

Select root(s):
```

Each root gets its own Checkov run and output files (e.g. `checkov-results-aws.json`).

---

## Cloud provider detection

Read `required_providers` blocks from all `.tf` files in the selected root.

| Provider | Check prefix | Notable additions |
|---|---|---|
| `hashicorp/aws` | `CKV_AWS_*` | EKS: `CKV_AWS_148`, `CKV_AWS_58`, `CKV_AWS_39` |
| `hashicorp/azurerm` | `CKV_AZ_*` | AKS: `CKV_AZURE_7`, `CKV_AZURE_117` |
| `hashicorp/google` | `CKV_GCP_*` | GKE: `CKV_GCP_24`, `CKV_GCP_25`, `CKV_GCP_69` |
| Multiple providers | All prefixes | Full multi-cloud scan |
| No `required_providers` | All prefixes | Warn and scan everything |

Plan mode auto-skips lifecycle checks unsupported on plan JSON: `CKV_AWS_217`, `CKV_AWS_233`, `CKV_AWS_237`, `CKV_GCP_82`.

---

## Private GitHub module authentication

### Detection

Scan `.tf` files for private module sources:

```hcl
source = "github.com/my-org/terraform-modules//eks/cluster"
source = "git::https://github.com/my-org/infra-modules.git//vpc"
```

### Auth fallback chain

1. `which gh` → `gh auth status` succeeds → `export GITHUB_PAT=$(gh auth token)` — zero friction
2. `$GITHUB_PAT` already set → use it
3. Neither → prompt: `Run 'gh auth login' or set GITHUB_PAT env var, then re-run`

### Other private sources

| Source pattern | Env var |
|---|---|
| `app.terraform.io` | `TF_REGISTRY_TOKEN` |
| `tfe.example.com` | `TF_REGISTRY_TOKEN` + `TF_HOST_NAME` |
| Self-hosted VCS | `VCS_BASE_URL`, `VCS_USERNAME`, `VCS_TOKEN` |
| Bitbucket | `BITBUCKET_USERNAME`, `BITBUCKET_APP_PASSWORD` |

Detect which is needed from the `source` URL pattern and check/prompt only for the relevant var.

---

## Non-interactive flags (CI/automation)

All interactive prompts are skipped when the corresponding flag is provided. This makes the command scriptable in CI without modification.

| Flag | Effect |
|---|---|
| `--yes` | Skip all confirmation prompts (workspace, file write, apply fixes). Does not skip warnings — they are printed but execution continues. |
| `--no-precommit` | Skip pre-commit hook detection and generation entirely. |
| `--keep-plan` | Do not delete `tfplan.binary` / `tfplan.json` after scan. |
| `--output <format>` | `cli` (default), `json`, `sarif`, `junitxml`, `all`. Skips the output format prompt. |
| `--var-file <path>` | Use this `.tfvars` file for `terraform plan`. Skips the variable file selection prompt. |
| `--workspace <name>` | Select this Terraform workspace before planning. Skips the workspace confirmation prompt. |
| `--root <path>` | Use this directory as the Terraform root. Skips multi-root selection prompt. |
| `--bot` | Emit GitHub-flavoured markdown PR comment output. Implies `--yes` and `--output json` (for severity parsing). Slash-command concern only — not implemented in the CI helper script. |
| `--upload-sarif` | Upload `checkov-results.sarif` to the GitHub Security tab. Separate from `--output sarif` — generating SARIF and publishing code-scanning alerts require different permissions (`security-events: write`). Never automatic. |
| `--upgrade` | Pass `--upgrade` to `terraform init`. Must be explicit — never the default. |

**CI example (GitHub Actions):**
```yaml
- name: Checkov plan scan
  run: |
    /platform-skills:checkov plan \
      --root terraform/aws \
      --workspace staging \
      --var-file staging.tfvars \
      --output sarif \
      --yes \
      --no-precommit
```

When `--yes` is set and the workspace confirmation would have blocked, execution proceeds with a `WARN: skipping workspace confirmation (--yes)` log line.

---

## Scan modes

### Pre-flight: gitignore output files

Run before any scan (static or plan):

```bash
for entry in "tfplan.json" "*.tfplan" "tfplan.binary" "checkov-results.sarif" "checkov-results.json" "checkov-results.xml"; do
  grep -qF "$entry" .gitignore 2>/dev/null || echo "$entry" >> .gitignore
done
```

### Static mode

```bash
checkov -d <root> \
  --framework terraform \
  --download-external-modules true \
  --compact \
  --quiet \
  $([ -d "custom-checks" ] && echo "--external-checks-dir custom-checks") \
  -o cli -o <format> --output-file-path console,<file>
```

With `.checkov.yaml` present, flags are read from config automatically — only `-d` and `-o` are needed.

### Plan mode

```bash
# 1. Cloud credential preflight
#    AWS:   aws sts get-caller-identity
#    Azure: az account show              (if azurerm provider detected)
#    GCP:   gcloud auth application-default print-access-token  (if google provider detected)
#    On failure: surface exact login command and abort

# 2. .terraform/ guard — check under <root>, not CWD
# Use plain terraform init (not --upgrade) — a security scan must not mutate
# .terraform.lock.hcl or upgrade providers behind the developer's back.
# Pass --upgrade only when the user explicitly invokes plan --upgrade.
if [ ! -d "<root>/.terraform" ]; then
  terraform -chdir=<root> init
fi

# 3. Variable file detection
# Find *.tfvars and prompt:
#   Variable files found: staging.tfvars, production.tfvars, None
#   Select [default: first found]:
# Append -var-file=<selected> to terraform plan

# 4. Workspace awareness — use -chdir so all terraform commands target <root>
terraform -chdir=<root> workspace list   # show current workspace
# Prompt: "Planning against workspace '<name>'. Continue? (y/N)"

# 5. Plan
terraform -chdir=<root> plan -var-file=<selected> --out tfplan.binary

# 6. Convert to JSON (jq required — abort if missing)
terraform -chdir=<root> show -json tfplan.binary | jq '.' > tfplan.json

# 7. Scan — --repo-root-for-plan-enrichment must point to the same <root>
checkov -f tfplan.json \
  --repo-root-for-plan-enrichment <root> \
  --deep-analysis \
  --compact \
  --quiet \
  $([ -d "custom-checks" ] && echo "--external-checks-dir custom-checks") \
  -o cli -o <format> --output-file-path console,<file>

# 8. Cleanup (skip with --keep-plan flag)
rm -f tfplan.binary tfplan.json
```

---

## Output formats

```
Output format?
  1. cli              — terminal only  [default]
  2. cli + json       — terminal + checkov-results.json
  3. cli + sarif      — terminal + checkov-results.sarif
  4. cli + junitxml   — terminal + checkov-results.xml
  5. all              — cli + json + sarif + junitxml
```

Multi-format: `-o cli -o json -o sarif --output-file-path console,checkov-results.json,checkov-results.sarif`

> **⚠ Severity filter vs severity field — two different things:**
>
> - **`severity` field in JSON output** — populated by the check definition itself (e.g., `CKV_AWS_19` is always HIGH). Works for most built-in checks with no API key. A minority of checks have `null` severity because the check definition omits it; treat `null` as MEDIUM in `--bot` result classification.
> - **`--check HIGH` as a CLI filter argument** — routes to the Bridgecrew/Prisma Cloud platform to resolve which check IDs map to HIGH. Without `--bc-api-key` this silently runs zero checks and exits 0. Always use check IDs for filtering (`--check CKV_AWS_19,CKV_AWS_21`), never severity names as filter arguments.
> - **`--use-enforcement-rules`** — entirely platform-dependent; silently no-ops without `--bc-api-key`. Only relevant for teams on Prisma Cloud.

### SARIF → GitHub Security tab

**Generating SARIF and uploading code-scanning results are separate actions.** Use `--output sarif` to produce the file. Use `--upload-sarif` (a distinct flag) only when you intend to publish alerts to the Security tab. The distinction matters because:
- SARIF generation: no permissions needed, no network calls, safe for all environments
- Upload: requires `security-events: write` (GitHub Actions OIDC) or a personal token with `security_events` scope; adds findings to the repo's code-scanning alert list which is visible to all collaborators

The GitHub API requires:
- `sarif`: gzip-compressed, Base64-encoded SARIF — `tr -d '\n'` is required because GNU `base64` (Linux) line-wraps at 76 chars; macOS `base64` does not; the API rejects line-wrapped payloads
- `commit_sha`: the full 40-character commit SHA
- `ref`: a full Git ref (`refs/heads/main`), not a bare SHA
- All three `git` calls must run against the repo root, not the Terraform root (`git -C "$REPO_ROOT"`)

```bash
REPO_ROOT=$(git -C "$ROOT" rev-parse --show-toplevel)
REPO=$(git -C "$REPO_ROOT" remote get-url origin | sed 's|.*github.com[:/]||;s|\.git$||')
COMMIT_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD)
REF=$(git -C "$REPO_ROOT" symbolic-ref HEAD 2>/dev/null || \
      echo "refs/tags/$(git -C "$REPO_ROOT" describe --tags --exact-match 2>/dev/null)")
SARIF_PAYLOAD=$(gzip -c "${ROOT}/checkov-results.sarif" | base64 | tr -d '\n')

gh api "repos/${REPO}/code-scanning/sarifs" \
  --method POST \
  --field sarif="$SARIF_PAYLOAD" \
  --field commit_sha="$COMMIT_SHA" \
  --field ref="$REF"
```

### `--bot` PR comment mode

When invoked with `--bot`, emit findings as GitHub-flavoured markdown:

```markdown
## 🔐 Checkov Scan Results

<!-- checkov-results -->

### Result: {BLOCKED | NEEDS_FIX | CLEAN | ERROR}

| Severity | Check ID | Resource | File |
|---|---|---|---|
| 🔴 HIGH | CKV_AWS_19 | aws_s3_bucket.data | terraform/aws/storage.tf:12 |

#### Findings

<!-- one subsection per FAILED check with: problem, corrected HCL, inline skip syntax -->

---
*Generated by [platform-skills](https://github.com/nitinjain999/platform-skills)*
```

Result values:
- **BLOCKED** — one or more HIGH or CRITICAL findings (checkov exit 1)
- **NEEDS_FIX** — MEDIUM findings only, no HIGH/CRITICAL (checkov exit 1)
- **CLEAN** — no failures (checkov exit 0)
- **ERROR** — tool error (checkov exit 2) — never silently pass

**Severity source:** Parse severity from the JSON output (`-o json`). Each failed check has a `"severity"` field (`"HIGH"`, `"MEDIUM"`, `"LOW"`, `"CRITICAL"`, or `null`). In Checkov 3.x, severity is baked into most built-in check definitions — it is populated without any API key or platform account. A minority of checks omit a severity in their definition; when `severity` is `null`, treat as `MEDIUM` and emit `NEEDS_FIX`. Never use `--check HIGH` as a filter argument without `--bc-api-key` — it silently runs zero checks. Always run `-o cli -o json` together so both human-readable and machine-parseable output are available even when `--bot` is not specified.

The `<!-- checkov-results -->` marker lets CI update the same comment on re-push.

---

## Baseline mode

For brownfield repos where the first scan surfaces hundreds of pre-existing violations.

### Baseline policy

| Rule | Rationale |
|---|---|
| Never auto-create a baseline in CI | A CI job running `--create-baseline` would silently suppress all current violations on every run. Baseline creation is a deliberate one-time act requiring human review. |
| Require explicit local confirmation | Before writing `.checkov.baseline`, show the full count of violations being suppressed by severity. Require the user to type `yes` — `--yes` flag does NOT skip this confirmation. |
| Warn on HIGH/CRITICAL suppression | If `--create-baseline` would suppress any HIGH or CRITICAL findings, print: `WARNING: X HIGH / Y CRITICAL findings will be permanently silenced. Remove entries you can fix now.` Require a second confirmation. |
| Always include owner and review date | Each skip entry in `.checkov.baseline` (and in `#checkov:skip` inline comments) must have `[Owner: <name>]` and `[Review: YYYY-MM-DD]` annotations. Generate them from `git config user.name` and a 90-day review date. |
| Re-evaluate suppressed HIGH/CRITICAL quarterly | Add a note to the committed baseline: `# Baseline created YYYY-MM-DD. Review HIGH/CRITICAL suppressions before YYYY-MM-DD.` |

### Creating a baseline

```
First scan detected N existing violations (X HIGH, Y CRITICAL). Create a baseline to suppress them?
  1. Yes — create .checkov.baseline (commit it; only new violations fail)
  2. No  — show all violations  [recommended for new repos]

WARNING: This will silence X HIGH and Y CRITICAL findings. Review .checkov.baseline
before committing and remove any entries you can fix now.

Type 'yes' to confirm:
```

If confirmed:
```bash
checkov -d <root> --framework terraform --create-baseline
# Checkov writes .checkov.baseline — review it before committing
```

Subsequent runs add `--baseline .checkov.baseline` automatically when the file exists.

---

## Secrets scanning

Hardcoded credentials and tokens are the most common source of cloud breaches. Checkov's secrets framework scans source files directly — no Terraform plan required.

### `secrets` mode — scan current files

```bash
checkov -d . \
  --framework secrets \
  --enable-secret-scan-all-files \
  --compact \
  --quiet \
  -o cli -o json --output-file-path console,checkov-results.json
```

`--enable-secret-scan-all-files` extends scanning beyond `.tf` files to all file types (YAML, JSON, shell scripts, `.env`, Python, etc.).

To exclude specific patterns or paths:
```bash
  --block-list-secret-scan "fake_secret,PLACEHOLDER"  # comma-separated false-positive values
```

#### When to use
- Before first commit to any repo containing cloud configs or application code
- As a pre-commit hook variant (`checkov_secrets` — see Pre-commit generation)
- After an access key rotation to confirm old keys are removed from source

### `audit` mode — scan git commit history

One-time scan to detect secrets ever committed, even in deleted files:

```bash
checkov -d . \
  --framework secrets \
  --enable-secret-scan-all-files \
  --scan-secrets-history \
  --compact \
  -o cli -o json --output-file-path console,checkov-audit.json
```

> **⚠ This is slow on large repos** — `--scan-secrets-history` walks every commit. Run on a dedicated CI job, not a pre-commit hook. For very large histories, scope with `git log --since=<date>` or run on a shallow clone.

**After secrets-history findings:** Rotate the exposed credential immediately. Then assess whether the commit history needs rewriting (BFG Repo Cleaner / `git filter-repo`). Checkov confirms presence — remediation requires credential rotation and, if secrets were in public commits, consider them compromised regardless of whether the history is rewritten.

### Pre-commit hook for secrets

Add the `checkov_secrets` hook alongside the standard Terraform hook to catch secrets on every commit:

```yaml
      # checkov_secrets — scans ALL files for secrets (not just Terraform)
      # Uncomment to add alongside checkov:
      # - id: checkov_secrets
      #   args:
      #     - --enable-secret-scan-all-files
```

See the Pre-commit generation section for the full hook block template.

---

## Multi-framework scanning

For repos containing more than Terraform — GitHub Actions workflows, Dockerfiles, Kubernetes/Helm manifests.

### `multi` mode — combined scan

```bash
checkov -d . \
  --framework terraform,github_actions,dockerfile,kubernetes,helm \
  --download-external-modules true \
  --compact \
  --quiet \
  -o cli -o json --output-file-path console,checkov-results.json
```

**Available frameworks (subset most relevant to platform repos):**

| Framework | Scans |
|---|---|
| `terraform` | `.tf` source files |
| `terraform_plan` | `tfplan.json` from `terraform show -json` |
| `github_actions` | `.github/workflows/*.yml` |
| `dockerfile` | `Dockerfile*` |
| `kubernetes` | Raw Kubernetes manifests (`.yaml`) |
| `helm` | Helm chart templates |
| `kustomize` | Kustomize overlays |
| `secrets` | All file types for hardcoded secrets |
| `all` | All of the above (slowest) |

**Skipping expensive frameworks on large repos:**

Use `--skip-framework` to exclude frameworks that take too long or produce too much noise in the current context:

```bash
# Example: scan terraform and github_actions, skip image SCA (slow, requires internet)
checkov -d . \
  --framework all \
  --skip-framework sca_package,sca_image \
  --compact --quiet
```

Common skip candidates for CI speed:
- `sca_package` — software composition analysis (requires network access to vulnerability DB)
- `sca_image` — container image scanning (overlaps with dedicated tools like Trivy)
- `secrets` — if running as a separate pre-commit hook step

#### GitHub Actions scanning

Checkov `github_actions` framework checks for:
- `pull_request_target` with checkout of PR head (code injection risk)
- Unpinned action versions (`uses: actions/checkout@v4` instead of SHA-pinned)
- Secrets passed as environment variables
- `permissions: write-all` or missing permissions block

```bash
checkov -d .github/workflows \
  --framework github_actions \
  --compact --quiet
```

#### Dockerfile scanning

```bash
checkov -d . \
  --framework dockerfile \
  --compact --quiet
```

Key checks: `USER root`, missing `HEALTHCHECK`, `ADD` instead of `COPY`, no `--no-cache` on `apk/apt-get`.

#### Combined platform repo scan (recommended pattern)

```bash
# Run terraform (source) + secrets + github_actions + dockerfile in one pass
checkov -d . \
  --framework terraform,secrets,github_actions,dockerfile \
  --download-external-modules true \
  --skip-framework sca_package,sca_image \
  --compact --quiet \
  -o cli -o sarif --output-file-path console,checkov-results.sarif
```

---

## Fix mode

After findings are displayed:

```
Fix violations?
  1. No       — show findings only  [default]
  2. Suggest  — show corrected HCL per finding
  3. Apply    — rewrite .tf files (diff shown, confirm before write)
```

**Suggest:** For each FAILED check, show:
- Corrected HCL resource block with `# checkov fix: <check-id>` comment
- Inline skip syntax for genuine false positives:

```hcl
#checkov:skip=CKV_AWS_8:Justification: registry-level scanning covers this [Owner: platform] [Review: 2026-07-01]
```

**Apply:** Generate patches → show unified diff → prompt `Apply changes? (y/N)` → use Edit tool to rewrite files.

Note: Checkov's `--fix` flag covers ~20 checks. AI-generated fixes cover all findings.

---

## Post-fix validation

Auto-applied HCL is not considered done until it passes all three gates. Run them in order after Apply mode writes any file:

```bash
# 1. Format — catch syntax introduced by the patch
terraform fmt -recursive <root>

# 2. Validate — catch type errors and missing references
terraform -chdir=<root> validate

# 3. Re-scan — confirm the specific check now passes
checkov -d <root> \
  --framework terraform \
  --check <CKV_ID_THAT_WAS_FIXED> \
  --compact --quiet
```

If any gate fails:
- `terraform fmt` failure → the patch introduced invalid HCL; show the offending line and offer a corrected version
- `terraform validate` failure → the patch broke a reference or type; do not mark the fix as complete
- Checkov re-scan still fails → the fix was incorrect; generate a revised patch

Do not mark a finding as fixed until all three gates pass.

---

## Scaffold mode

### `.checkov.yaml` config

Generate scoped to detected provider(s) and compliance profile. Profiles: `soc2` (default), `cis`, `pci`, `hipaa`.

**SOC 2 / general hardening (default — `aws` provider)**

```yaml
# .checkov.yaml — generated by /platform-skills:checkov scaffold (profile: soc2, provider: aws)
compact: true
download-external-modules: true
evaluate-variables: true
framework:
  - terraform

check:
  - CKV_AWS_19   # S3 server-side encryption             [CC6.1]
  - CKV_AWS_18   # S3 access logging                     [CC7.2]
  - CKV_AWS_21   # S3 versioning                         [A1.2]
  - CKV_AWS_7    # KMS key rotation                      [CC6.1]
  - CKV_AWS_16   # RDS encrypted at rest                 [CC6.1]
  - CKV_AWS_17   # RDS not publicly accessible           [CC6.6]
  - CKV_AWS_40   # IAM no inline policies                [CC6.3]
  - CKV_AWS_1    # IAM policy no Action *                [CC6.3]
  - CKV_AWS_36   # CloudTrail log file validation        [CC7.2]
  - CKV_AWS_35   # CloudTrail encrypted with KMS         [CC6.1]
  - CKV_AWS_67   # CloudTrail enabled all regions        [CC7.2]
  - CKV_AWS_148  # EKS node groups in private subnets    [CC6.6]
  - CKV_AWS_58   # EKS secrets encryption                [CC6.1]
  - CKV_AWS_25   # No SG ingress 0.0.0.0/0 port 22      [CC6.6]
  - CKV_TF_1     # Module sources use commit hash
  - CKV_TF_2     # Registry modules use version tag

skip-check: []
# skip-check:
#   - CKV_AWS_8  # Justification: ... [Owner: ...] [Review: YYYY-MM-DD]
```

**CIS AWS Foundations Benchmark (profile: `cis`)**

```yaml
# .checkov.yaml — profile: cis-aws
compact: true
download-external-modules: true
framework:
  - terraform

check:
  # CIS Section 1 — Identity and Access Management
  - CKV_AWS_9    # IAM password policy: 14+ chars         [1.8]
  - CKV_AWS_10   # IAM password policy: uppercase         [1.9]
  - CKV_AWS_11   # IAM password policy: lowercase         [1.10]
  - CKV_AWS_12   # IAM password policy: symbols           [1.11]
  - CKV_AWS_13   # IAM password policy: numbers           [1.12]
  - CKV_AWS_9    # IAM password policy: reuse prevention  [1.13]
  - CKV_AWS_1    # IAM no wildcard actions                [1.16]
  - CKV_AWS_40   # No inline policies                     [1.16]
  # CIS Section 2 — Logging
  - CKV_AWS_36   # CloudTrail log validation              [2.2]
  - CKV_AWS_35   # CloudTrail KMS encryption              [2.7]
  - CKV_AWS_67   # CloudTrail all regions                 [2.1]
  - CKV_AWS_65   # Config enabled                         [2.5]
  # CIS Section 3 — Networking
  - CKV_AWS_25   # No SSH ingress 0.0.0.0/0              [5.2]
  - CKV_AWS_24   # No RDP ingress 0.0.0.0/0              [5.3]
  - CKV_AWS_23   # No unrestricted outbound              [5.4]
```

**PCI DSS v4.0.1 (profile: `pci`)**

```yaml
# .checkov.yaml — profile: pci-dss-v4
compact: true
download-external-modules: true
framework:
  - terraform

check:
  # Requirement 2 — Do not use vendor-supplied defaults
  - CKV_AWS_25   # No SSH 0.0.0.0/0                    [2.2.4]
  - CKV_AWS_24   # No RDP 0.0.0.0/0                    [2.2.4]
  # Requirement 3 — Protect stored cardholder data
  - CKV_AWS_19   # S3 encryption at rest               [3.4]
  - CKV_AWS_16   # RDS encryption                      [3.4]
  - CKV_AWS_7    # KMS key rotation                    [3.6.4]
  # Requirement 7 — Restrict access
  - CKV_AWS_1    # No wildcard IAM actions             [7.1.2]
  - CKV_AWS_40   # No inline IAM policies              [7.1.2]
  # Requirement 10 — Track and monitor
  - CKV_AWS_36   # CloudTrail validation               [10.5.2]
  - CKV_AWS_35   # CloudTrail KMS                      [10.5.2]
  - CKV_AWS_67   # CloudTrail all regions              [10.2]
  # Requirement 6 — Develop secure systems
  - CKV_AWS_17   # RDS not publicly accessible         [6.4.1]
  - CKV_AWS_18   # S3 access logging                   [10.2.1]
```

**HIPAA (profile: `hipaa`)**

```yaml
# .checkov.yaml — profile: hipaa
compact: true
download-external-modules: true
framework:
  - terraform

check:
  # Administrative safeguards: audit controls
  - CKV_AWS_36   # CloudTrail log validation           [§164.312(b)]
  - CKV_AWS_35   # CloudTrail KMS encryption           [§164.312(a)(2)(iv)]
  - CKV_AWS_67   # CloudTrail all regions              [§164.312(b)]
  # Technical safeguards: encryption at rest
  - CKV_AWS_19   # S3 encryption                      [§164.312(a)(2)(iv)]
  - CKV_AWS_16   # RDS encryption                     [§164.312(a)(2)(iv)]
  - CKV_AWS_7    # KMS key rotation                   [§164.312(a)(2)(iv)]
  - CKV_AWS_58   # EKS secrets encryption             [§164.312(a)(2)(iv)]
  # Access controls: least privilege
  - CKV_AWS_1    # IAM no wildcard actions             [§164.312(a)(1)]
  - CKV_AWS_40   # No inline IAM policies              [§164.312(a)(1)]
  # Transmission security
  - CKV_AWS_17   # RDS not public                     [§164.312(e)(1)]
  - CKV_AWS_25   # No SSH 0.0.0.0/0                   [§164.312(e)(1)]
  - CKV_AWS_21   # S3 versioning (integrity)          [§164.312(c)(1)]
```

When the user asks for scaffold mode, ask:
```
Compliance profile?
  1. soc2   — SOC 2 Type II controls  [default]
  2. cis    — CIS AWS Foundations Benchmark
  3. pci    — PCI DSS v4.0.1
  4. hipaa  — HIPAA Technical/Administrative Safeguards
  5. custom — generate .checkov.yaml with all provider checks + empty skip list

Enter 1–5 or profile name:
```

For Azure and GCP providers, replace `CKV_AWS_*` check IDs with the equivalent `CKV_AZ_*` / `CKV_GCP_*` check IDs from the provider detection table above.

> **Compliance mapping disclaimer:** The control references (`[CC6.1]`, `[PCI 3.4]`, `[§164.312]`) are **starter mappings and evidence aids**, not authoritative compliance certifications. A single Checkov check rarely satisfies a full control — it is one technical evidence point among many. The actual mapping between check IDs and controls varies by assessor, scope, and organisation. Have a qualified auditor validate mappings before using them in formal audit reports. Checkov does not read these comments — they are documentation only.

#### Skipping expensive frameworks in `.checkov.yaml`

For large repos where a full `--framework all` scan takes too long, scaffold the config with `skip-framework` entries:

```yaml
# Add to .checkov.yaml to skip SCA scanning (requires network, slow)
skip-framework:
  - sca_package   # software composition analysis — use Dependabot/Renovate instead
  - sca_image     # container image CVE scan — use Trivy/ECR scanning instead
```

Recommend `--skip-framework sca_package,sca_image` in any repo where SCA scanning is handled by a dedicated tool.

### Custom checks scaffold

```
custom-checks/
├── __init__.py
└── CKV_MYCO_1.py
```

`__init__.py`:
```python
from os.path import dirname, basename, isfile, join
import glob
modules = glob.glob(join(dirname(__file__), "*.py"))
__all__ = [basename(f)[:-3] for f in modules if isfile(f) and not f.endswith('__init__.py')]
```

`CKV_MYCO_1.py` (example — enforce required tags):
```python
from checkov.common.models.enums import CheckResult, CheckCategories
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck
from typing import Any

class EnforceRequiredTags(BaseResourceCheck):
    def __init__(self) -> None:
        name = "Ensure resource has required tags: team and environment"
        id = "CKV_MYCO_1"
        supported_resources = ("aws_instance", "aws_s3_bucket", "aws_db_instance")
        categories = (CheckCategories.GENERAL_SECURITY,)
        super().__init__(name=name, id=id, categories=categories, supported_resources=supported_resources)

    def scan_resource_conf(self, conf: dict[str, list[Any]]) -> CheckResult:
        tags = conf.get("tags", [{}])
        tag_map = tags[0] if isinstance(tags, list) else tags
        if isinstance(tag_map, dict) and "team" in tag_map and "environment" in tag_map:
            return CheckResult.PASSED
        return CheckResult.FAILED

check = EnforceRequiredTags()
```

Check ID convention: `CKV_<ORG_ABBREVIATION>_<NUMBER>` (e.g. `CKV_MYCO_1`).

---

## Common mistakes

| Mistake | Impact | Prevention |
|---|---|---|
| Committing `tfplan.json` or `checkov-results.*` | Secrets / resource details leak in git | Command auto-adds all output files to `.gitignore` before scanning |
| Running plan mode without `jq` | All findings at line 0, useless | Command aborts and installs `jq` first |
| Using `--soft-fail` in CI | Gate never blocks merges | Command warns; `--soft-fail` only offered for local explore mode |
| Baseline-suppressing HIGH/CRITICAL on first run | Silences real findings permanently | Command shows count and prompts review before committing |
| Wrong Terraform workspace | Plan scans wrong state | Command shows workspace list and prompts confirmation |
| Missing cloud credentials | Plan fails with cryptic auth error | Command runs `aws sts get-caller-identity` / `az account show` / `gcloud auth application-default print-access-token` first |
| Checkov exit code 2 treated as CLEAN | Tool error silently passes gate | Command checks exit code; exit 2 → ERROR result |
| Missing `terraform init` | Plan fails immediately | Command checks for `.terraform/` and runs `terraform init` if absent (pass `--upgrade` explicitly to also upgrade providers) |
| Wrong or missing `-var-file` | Plan uses wrong variable values | Command detects `*.tfvars` and prompts selection before planning |
| `--check HIGH` as a CLI filter without `--bc-api-key` | Silently runs zero checks; scan exits 0 and reports CLEAN | Use check IDs to filter (`--check CKV_AWS_19,CKV_AWS_21`); severity names as filter args require a Prisma Cloud API key. The `severity` field in JSON output works fine without an API key — most built-in checks have it baked in |
| `--use-enforcement-rules` without Prisma Cloud API key | Silently no-ops — every check passes | Only valid with `--bc-api-key` pointing to a Prisma Cloud tenant; document this clearly in CI config |
| Running `--scan-secrets-history` in pre-commit | Extremely slow on large repos; blocks every commit | Reserve `--scan-secrets-history` for nightly CI or one-time audit jobs; use `checkov_secrets` hook for per-commit scanning |

---

## Rollback and cleanup

### Remove the pre-commit hook

```bash
# Open .pre-commit-config.yaml and delete the bridgecrewio/checkov repo block.
# Then reinstall hooks without checkov:
pre-commit install --install-hooks
```

### Remove the baseline

```bash
rm .checkov.baseline
# Next scan will report all violations again.
```

### Remove the config file

```bash
rm .checkov.yaml
# Checkov reverts to scanning all checks for the detected provider.
```

### Remove gitignore entries

```bash
# Edit .gitignore and delete the lines added for tfplan.json, tfplan.binary, checkov-results-*.
# These entries are safe to keep — they only prevent accidental commits of scan artefacts.
```

### Undo an AI-applied fix

```bash
# Fixes are applied via the Edit tool and tracked in git diff.
git diff terraform/     # review what changed
git checkout -- terraform/aws/storage.tf   # revert a specific file
# Or revert all uncommitted Terraform changes:
git checkout -- '*.tf'
```

### Remove Checkov entirely

```bash
# macOS:
brew uninstall checkov

# pip (venv):
pip3 uninstall checkov

# pip (system):
pip3 uninstall checkov
```

After removal, the pre-commit hook will error on next commit if the `bridgecrewio/checkov` repo block is still in `.pre-commit-config.yaml`. Remove it (see above) before uninstalling.
