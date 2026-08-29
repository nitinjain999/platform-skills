---
title: Kingfisher
custom_edit_url: null
---

# Kingfisher Reference

Covers all `/platform-skills:kingfisher` mode logic: bootstrap, scan usage, rule namespaces, direct validation and revocation, baseline management, `kingfisher.yaml` configuration, CI diff-scanning, platform-specific targets, alerting, pre-commit, and exit-code gating.

Kingfisher is a Rust secret scanner from MongoDB. It detects candidate secrets with a SIMD-accelerated regex engine (Vectorscan) and language-aware parsing, then **live-validates** each candidate against the issuing provider's API to tell "a string that looks like a key" apart from "a credential that still authenticates." Optionally it maps the **blast radius** of a validated credential — identity, permissions, reachable resources — and can **revoke** it directly.

**Verified against Kingfisher `v2.0.0`.** This is a recent major version: built-in rule IDs moved from a `kingfisher.*` namespace to `betterleaks.*` / `veles.*` (see [Rule namespaces and the v2 migration](#rule-namespaces-and-the-v2-migration) below). Version-sensitive claims are marked inline.

---

## Tool Ownership Boundary

Kingfisher owns **finding, validating, mapping, and killing leaked credentials** — wherever they live, not just in a local checkout.

| Question | Authoritative command |
|---|---|
| "Is there a hardcoded-looking secret in this repo?" (fast, pattern-only, bundled with a CVE scan) | `/platform-skills:trivy` `secrets` mode |
| "Is that secret still **live**? What can it reach? Can I kill it?" | **this command** |
| "Did a secret leak into Slack, Jira, Confluence, an S3 bucket, or a GitHub org — not just this one repo?" | **this command** |
| "How should secrets be stored/rotated *inside* my Kubernetes cluster?" (ESO, Sealed Secrets) | `/platform-skills:secrets` |
| "Is my workflow's `secrets:` context usage safe?" (overprovisioned, unredacted, `secrets: inherit`) | `/platform-skills:zizmor` |
| "Is there a CVE in my image or dependencies?" | `/platform-skills:trivy` |
| "How do I sign images or generate an SBOM?" | `/platform-skills:supply-chain` |

**Trivy and Kingfisher are not the same depth of tool.** Trivy's `secrets` scanner is a fast, offline, regex/entropy pass bundled alongside its CVE and license scanning — it tells you a string *matches a secret pattern*. Kingfisher is a dedicated secret-scanning platform: it live-validates candidates against the real provider API, groups by canonical repository for baseline tracking, and can enumerate secrets across GitHub/GitLab/Bitbucket/Gitea/Azure Repos/Hugging Face organizations, Slack, Jira, Confluence, Microsoft Teams, Postman, S3, GCS, and Docker images — then map blast radius and revoke. Reach for Trivy for a quick "does this smell like a secret" pass inside a broader vuln/license scan; reach for Kingfisher when the answer needs to be "yes this key is still active, it can read three S3 buckets, and I just revoked it."

**Zizmor's `secrets:`-context audits and Kingfisher do not overlap.** Zizmor audits how a *workflow definition* references the `secrets` context (whole-context sharing, missing redaction, `secrets: inherit`). It never looks at file contents for an actual leaked string. Kingfisher never looks at workflow YAML semantics. A repo can pass every zizmor secrets audit and still have a live AWS key sitting in a commit from three years ago.

### What Kingfisher structurally cannot see

- **Static candidates still need validation.** Detection finds a string that *matches* a rule; only `--no-validate`-free scanning (the default) or `kingfisher validate` confirms it is still live. A `verified_active` finding is provably dangerous; an `assumed` finding is high-confidence but not network-checked; treat the two differently in a report.
- **Live validation calls the provider.** It needs network access and, for private validators, is subject to that provider's rate limits — the `--validation-rps` / `--validation-rps-rule` flags exist because aggressive validation can itself look like credential-stuffing to the provider.
- **Blast-radius mapping and revocation are privileged operations.** Both authenticate *as the discovered credential* against a live provider. Never run either against an account you are not authorized to inspect or modify.

---

## Bootstrap

### macOS / Homebrew

```bash
brew install kingfisher
```

### mise

```bash
mise use --global github:mongodb/kingfisher
# pin a version
mise use --global github:mongodb/kingfisher@1.113.0
```

### Linux and macOS install script

```bash
curl --silent --location \
  https://raw.githubusercontent.com/mongodb/kingfisher/main/scripts/install-kingfisher.sh | \
  bash

# custom install dir
curl --silent --location .../install-kingfisher.sh | bash -s -- /opt/kingfisher

# pin a specific tag
curl --silent --location .../install-kingfisher.sh | bash -s -- --tag v1.71.0
```

### Windows (PowerShell)

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/mongodb/kingfisher/main/scripts/install-kingfisher.ps1' -OutFile install-kingfisher.ps1
./install-kingfisher.ps1
```

### PyPI / uv (no persistent install)

```bash
uv tool install kingfisher-bin      # recommended
pip install kingfisher-bin          # or plain pip
uvx kingfisher-bin --help           # one-shot, no install
```

### Docker

```bash
docker run --rm ghcr.io/mongodb/kingfisher:2.0.0 --version

docker run --rm -v "$PWD":/src ghcr.io/mongodb/kingfisher:2.0.0 scan /src
```

**Pin the tag.** `:latest` moves under you — a scan that passed yesterday can behave differently today because the rule catalogue or validator set changed. Pin to a released version tag (`ghcr.io/mongodb/kingfisher:2.0.0`) for reproducible CI, the same reason zizmor's `unpinned-images` audit flags `:latest` container references.

Also available: pre-built GitHub Releases, MegaLinter bundling, or `make linux` / `make darwin` / `./buildwin.bat` from source (source builds need outbound HTTPS to fetch the pinned Betterleaks rule snapshot at build time).

---

## Basic scanning

`kingfisher scan` auto-detects whether a path is a Git repo, a directory of many repos, or a plain folder — no extra flag needed.

```bash
# Local checkout, with live validation (the default)
kingfisher scan /path/to/code

# Explicitly skip Git commit history, scan only the working tree
kingfisher scan /path/to/code --git-history=none

# Skip live validation entirely (fast, offline, static-only)
kingfisher scan ~/src/myrepo --no-validate

# Pipe arbitrary text in
cat generated.env | kingfisher scan - ./src ./tests
```

> **Remote clone vs. local checkout give different counts.** A remote URL target clones `--mirror`/bare by default, so only Git history is scanned. A local working-tree target scans the filesystem *and* history, so a secret still present in a tracked file shows up twice — once from the file, once from the commit it entered on. To reproduce remote behavior locally, scan a bare clone or pass `--git-history=none`.

### Validation filters

| Filter | Included outcomes |
|---|---|
| `all` (default) | Every finding, including inconclusive/skipped/inactive/not-attempted |
| `active` | `verified_active` only |
| `actionable` | `verified_active`, `assumed`, and `locally_derived` |

```bash
kingfisher scan /path/to/repo --only-valid              # alias for --validation-filter active
kingfisher scan /path/to/repo --validation-filter actionable
```

`--only-valid` and `--validation-filter` are mutually exclusive — pick one. In JSON/JSONL, read `finding.validation.outcome` for automation rather than parsing the human label.

### Output formats

```bash
kingfisher scan . --format json | tee kingfisher.json
kingfisher scan . --format toon                                    # token-efficient, for LLM/agent consumption
kingfisher scan /path/to/repo --format sarif --output findings.sarif
kingfisher scan /path/to/repo --format html --output kingfisher-audit.html   # standalone evidence report
```

`pretty` (default), `json`, `jsonl`, `bson`, `toon`, `sarif`, `html`. `toon` exists specifically for LLM/agent callers — it front-loads the scan summary and flattens each finding into a token-cheap row, so prefer it over `json` when *this* command is the consumer.

### Blast radius / access map

```bash
kingfisher scan /path/to/repo --blast-radius              # alias: --access-map
kingfisher scan /path/to/repo --view-report                # generate report, launch local viewer, open browser
```

`--blast-radius` authenticates as each validated credential against its provider (AWS, GCP, Azure Storage, Entra ID/Graph, Azure RBAC, Azure DevOps, GitHub, GitLab, Slack, Microsoft Teams) and enriches the report's `access_map` field with the resources and permissions it can reach, grouped when identical. **Use it only when authorized to inspect the target account** — it is an authenticated reconnaissance action against a live account, not a passive read.

### Report viewer

```bash
kingfisher view kingfisher.json                       # opens http://127.0.0.1:7890 and your browser
kingfisher view report1.json report2.jsonl            # merge, dedup by fingerprint
kingfisher view ./reports/                             # ingest a whole directory
kingfisher view gitleaks-report.json                   # also reads Gitleaks and TruffleHog reports
kingfisher view kingfisher.sarif --address 0.0.0.0 --port 9000   # expose from a container
```

The same viewer, as a static hosted page with no server, no install, and nothing leaving the machine: **https://mongodb.github.io/kingfisher/viewer/**. Both accept Kingfisher JSON/JSONL/SARIF, generic SARIF 2.1.0, Gitleaks JSON, and TruffleHog JSON/JSONL — useful for triaging three scanners' output in one place. Imported (non-Kingfisher) reports are display-only: `kingfisher validate`/`revoke` cannot act on a Gitleaks or TruffleHog finding, and generic SARIF carries no `access_map` data.

---

## Rule namespaces and the v2 migration

Kingfisher v2.0.x sources its candidate detector catalogue from **Betterleaks** (`betterleaks.*`), with selected **Veles** detectors (`veles.*`) filling gaps, both fetched and compiled at build time. Kingfisher's own 1.x YAML rule format is still supported, but now only recommended for **private, org-specific** custom rules — write new generally-useful detectors upstream in Betterleaks instead.

```bash
kingfisher rules list          # current catalogue
kingfisher rules compile-cache
kingfisher rules prune-cache --dry-run
kingfisher rules prune-cache
```

**Old `kingfisher.*` rule selectors still resolve, with a warning:**

```console
$ kingfisher scan ./repo --rule kingfisher.aws.1
WARN Rule selector `kingfisher.aws.1` is a Kingfisher 1.x ID. Kingfisher 2.0 renamed the
     built-in catalog; resolving it as `betterleaks.aws` for now. Update your configuration -
     this fallback will be removed in a future release.
```

The alias resolves to the **whole provider family**, not the original single rule (1.x ordinals have no 2.x equivalent). A `kingfisher.*` selector with no known replacement is still a hard error — typos are not silently swallowed. This fallback is scheduled for removal; do not build new automation on `kingfisher.*` IDs.

### Selecting rules

```bash
# Family prefix match: loads every betterleaks.aws-* rule
kingfisher scan /path/to/repo --rule betterleaks.aws

# Exact IDs, repeatable, prefix optional for short selectors
kingfisher scan ./repo \
  --rule betterleaks.github-pat \
  --rule betterleaks.github-fine-grained-pat \
  --exclude-rule betterleaks.openai-api-key

# The betterleaks. prefix is optional for short selectors
kingfisher scan ./repo --rule github-pat
```

No wildcards (`betterleaks.g*` does not work) — use a family prefix instead. `--rule-stats` prints rule performance stats for a scan.

---

## Direct validation and revocation

These act on a single known secret string — no scan, no surrounding file context required.

### `kingfisher validate`

```bash
kingfisher validate --rule github-pat "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
echo "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" | kingfisher validate --rule github -

kingfisher validate --rule mongodb-connection-string \
  "mongodb+srv://user:password@cluster.mongodb.net/db"

kingfisher validate --rule aws-access-token \
  --var AWS_SECRET_ACCESS_KEY="secret_key" \
  "AKIAEXAMPLE000000000"
```

Use `--arg VALUE` when you don't know a validator's exact template variable name (auto-assigned alphabetically); use `--var NAME=VALUE` when you do, or to override `--arg`. Exit code `0` if any matching rule validates the secret as live, `1` if all are invalid or an error occurred.

### `kingfisher revoke`

**Destructive — this kills a live credential.** Blast radius: anything currently authenticating with that credential loses access the moment revocation succeeds, including production workloads you may not know about. There is no dry-run and no undo; the only rollback is issuing a new credential through the provider and redeploying it.

```bash
kingfisher revoke --rule github-pat "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# AWS: secret key positional, access-key ID via --var
kingfisher revoke --rule aws-access-token \
  --var AKID=AKIAIOSFODNN7EXAMPLE \
  "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

# Custom rule with its own revocation: block
kingfisher revoke --rules-path ./custom-rules.yml --rule custom.provider.token "secret"
```

Betterleaks does not currently ship revocation metadata; Kingfisher maintains a detection-free revocation-capability overlay joined to upstream rule IDs at build time. Exit code `0` on a successful revocation, `1` if all attempts failed or errored. Before running it: confirm with `kingfisher validate` that the credential is still live, confirm who owns it, and confirm rotation is ready to redeploy — revoking first and asking questions later is how an incident response action becomes an outage.

### Self-hosted endpoints (`--endpoint` / `--endpoint-config`)

Route validation/revocation at a self-hosted instance instead of the public SaaS API:

```bash
kingfisher validate --rule github \
  --endpoint github=https://ghe.corp.example.com \
  "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

Supported keys: `github`, `gitlab`, `gitea`, `jira`, `jira-cloud`, `confluence`, `artifactory`. `--endpoint-config FILE` loads a reusable YAML mapping of the same keys. For an internal/private-IP endpoint, pair with `--allow-internal-ips` (see [SSRF protection](#ssrf-protection) below).

---

## Baseline: track only new secrets

A baseline records known findings so later scans report only what's new **for the repository it occurred in**. Version 2 (current) is repository-aware — one file can safely cover a whole GitHub org, GitLab group, or a directory of many repos, because each finding is keyed to a canonical repository ID plus fingerprint, not a global fingerprint alone.

```bash
# Create (low confidence is common, to capture every existing candidate)
kingfisher scan /path/to/code \
  --confidence low \
  --manage-baseline \
  --baseline-file ./baseline-file.yml

# Use on later scans — repository section is selected automatically
kingfisher scan /path/to/code --baseline-file /path/to/baseline-file.yml
```

`--manage-baseline` implies `--no-dedup`, so every repository occurrence is observed for the update. After a multi-repo managed scan, Kingfisher performs one deterministic atomic write once **every** repository worker has finished — a single failed repository leaves the existing baseline untouched rather than partially pruning it. Repositories not included in a given managed run keep their existing section unchanged; repositories that *are* included are replaced with exactly what that run found (so a narrower rule/path selection than last time can silently drop entries — use the same scan scope for baseline creation and management).

Repository IDs are derived from the normalized remote URL (credentials, query strings, transport, and trailing `.git` stripped, host lowercased) — `https://Example.COM/team/repo.git` and `git@example.com:team/repo.git` both become `git://example.com/team/repo`. A non-Git local input falls back to a `local://` ID from the normalized absolute path, so a baseline for a plain directory is tied to that path.

Kingfisher still reads the legacy unversioned `ExactFindings` format read-only; a successful `--manage-baseline` run upgrades it to version 2 in place. Legacy (version 1) fingerprints are global — a match suppresses that fingerprint in *any* scanned repository, which version 2 fixes.

---

## Project configuration: `kingfisher.yaml`

Long CLI invocations are awkward in CI. `kingfisher.yaml` supplies defaults for nearly every scan flag.

**Not auto-discovered.** Pass `--config FILE` explicitly or it is never loaded — a missing or malformed file is a fatal error, not a silent fallback. This is deliberate: auto-discovery would make results depend on the launch directory.

**Precedence:** `CLI flag > environment variable > kingfisher.yaml > built-in default`. List-typed values (rules, excludes, skip-words, webhooks) are **additive** across sources; scalars are default-only, so a CLI flag always wins outright.

Scan-target inputs stay CLI-only by design — they describe *what this run scans*, not project policy: positional paths, `--git-url`, every `--<platform>-user`/`--<platform>-org`/`--<platform>-group`, `--s3-bucket`, `--gcs-bucket`, `--docker-image`, `--jira-url`, `--confluence-url`, `--slack-query`, `--teams-query`, `--postman-*`. Auth tokens stay in environment variables too, never in the config file.

### Generate, don't hand-write

```bash
kingfisher config init \
  --confidence high \
  --redact \
  --exclude vendor/ \
  --exclude '**/node_modules/**' \
  --format sarif \
  --output ./kingfisher.sarif \
  > kingfisher.yaml

kingfisher scan . --config ./kingfisher.yaml
kingfisher scan . --config ./kingfisher.yaml --confidence low   # per-run override
```

**Never pass `--alert-webhook` to `config init`.** A webhook URL is a bearer credential — anyone who can trigger a call to it can post as your security channel — and `kingfisher.yaml` is meant to be committed. Leave webhooks out of the generated file and inject them at scan time from a CI secret instead, as the [CI pattern](#ci-pattern) below does.

### Full schema

```yaml
scan:
  confidence: medium            # low | medium | high           (--confidence)
  min_entropy: 3.5              # float                          (--min-entropy)
  no_validate: false            # bool                           (--no-validate)
  validation_filter: actionable # all | active | actionable      (--validation-filter)
  redact: false                 # bool                           (--redact)
  no_dedup: false                # bool                          (--no-dedup)
  turbo: false                  # bool                           (--turbo)
  access_map: false             # bool                           (--blast-radius; alias --access-map)
  jobs: 8                       # int                            (--jobs)

rules:
  enabled: ["all"]              # list, additive; replaces synthetic ["all"] if you list your own  (--rule)
  disabled: [betterleaks.github-pat]   # list, additive          (--exclude-rule)
  paths: [./custom-rules/]      # list, additive                 (--rules-path)
  cache_dir: ./.kingfisher-cache # optional path                 (--rule-cache-dir, KF_RULE_CACHE_DIR)

validation:
  timeout: 10                   # seconds, 1..=60                (--validation-timeout)
  rps: 5.0                      # float                          (--validation-rps)
  rps_per_rule: {betterleaks.aws: 1.0}  # map, additive          (--validation-rps-rule)

filters:
  skip_words: [EXAMPLE, PLACEHOLDER]     # list, additive        (--skip-word)
  skip_regex: ['^DUMMY_[A-Z]+$']         # list, additive        (--skip-regex)
  exclude: [vendor/, "**/node_modules/**"]  # list, additive     (--exclude)
  max_file_size_mb: 256.0       # float                          (--max-file-size)
  skip_aws_accounts: []         # list, additive                 (--skip-aws-account)

output:
  format: pretty                 # pretty|json|jsonl|bson|toon|sarif|html  (--format)
  path: ./kingfisher-report.json # path                          (--output)

baseline:
  file: ./baseline.json          # path                          (--baseline-file)
  manage: false                  # bool                          (--manage-baseline)

alerts:
  defaults:
    on: findings                 # findings | always              (--alert-on)
    min_confidence: medium       # low | medium | high            (--alert-min-confidence)
    detail: auto                 # summary | detail | auto        (--alert-detail)
  webhooks:
    - url: https://hooks.slack.com/services/T0/B0/AAA
      format: slack               # slack|teams|generic|discord|mattermost|googlechat

global:
  tls_mode: strict               # strict | lax | off             (--tls-mode)
  allow_internal_ips: false      # bool                           (--allow-internal-ips)
  endpoints: ["github=https://ghe.example.com/api/v3"]  # list    (--endpoint)

git:
  clone_dir: null                # path                           (--git-clone-dir)
  github_api_url: null           # URL, GHE / self-hosted GH      (--github-api-url)
  gitlab_api_url: null           # URL, self-hosted GitLab        (--gitlab-api-url)
```

Unknown fields are rejected (typo protection). `rules.enabled` only *replaces* the implicit `["all"]` default if you don't also pass `--rule` on the CLI — otherwise the two lists are additive, same as every other list field. `scan.only_valid: true` is a config alias for `validation_filter: active`; the two are mutually exclusive, same rule as the CLI flags.

### CI pattern

```bash
# .github/workflows/secrets.yml — run step
kingfisher scan . \
  --config ./kingfisher.yaml \
  --alert-webhook "$SLACK_SECURITY_WEBHOOK"
# kingfisher.yaml intentionally has no webhooks baked in (see the config
# init warning above) — this is how one gets added, from a CI secret, at
# scan time, with nothing credential-bearing in the committed file
```

Full worked example, including alert routing, in [CI integration](#ci-integration) below.

---

## Scanning changes in CI (diff-focused)

Keep CI fast and still block new secrets by scanning only what changed, instead of the whole tree every run.

```bash
kingfisher scan . \
  --since-commit origin/main \
  --branch "$CI_BRANCH"
```

- `--since-commit <ref>` diffs the branch tip against another ref and scans only what changed between them — the default fast path for a PR check.
- `--branch <ref>` (defaults to `HEAD`) names the ref being scanned; can point at an unchecked-out ref or even a bare Git URL.
- `--branch-root-commit <sha>` rewinds to that commit's parent and scans everything from there forward, regardless of whether files changed relative to another baseline — for resuming from a previous review point or a hotfix fork point, not for routine PR diffs.

```bash
# CI systems that expose base/head SHAs directly, scanning a Git URL with no local checkout
kingfisher scan https://github.com/org/repo.git \
  --since-commit "$BASE_COMMIT" \
  --branch "$PR_HEAD_COMMIT"

# Resume from where a hotfix branch forked from main
kingfisher scan /path/to/repo --branch hotfix \
  --branch-root-commit "$(git merge-base main hotfix)"
```

Exits `200` on any finding, `205` if any is validated-live — a CI job can fail automatically the moment a new credential slips in. See [Exit codes](#exit-codes).

---

## Platform-specific targets

Beyond a local path or Git URL, `scan` takes a provider subcommand. All of these need an auth token env var for private content; public content works without one.

| Platform | Subcommand | Auth env var | Example |
|---|---|---|---|
| GitHub org | `scan github --organization <org>` | `KF_GITHUB_TOKEN` | `kingfisher scan github --organization my-org --repo-clone-limit 500` |
| GitHub public events | `scan github --public-events` | `KF_GITHUB_TOKEN` (raises rate limit) | `kingfisher scan github --public-events --user alice --event-lookback-hours 12` |
| GitLab group | `scan gitlab --group <group>` | `KF_GITLAB_TOKEN` | `kingfisher scan gitlab --group my-group` |
| Azure Repos org | `scan azure --azure-organization <org>` | `KF_AZURE_TOKEN` / `KF_AZURE_PAT` | `kingfisher scan azure --azure-organization my-org` |
| Bitbucket workspace | `scan bitbucket --workspace <ws>` | `KF_BITBUCKET_TOKEN` (or `KF_BITBUCKET_OAUTH_TOKEN`) | `kingfisher scan bitbucket --workspace my-team` |
| Gitea org | `scan gitea --organization <org>` | `KF_GITEA_TOKEN` | `kingfisher scan gitea --organization my-org` |
| Hugging Face org | `scan huggingface --huggingface-organization <org>` | `KF_HUGGINGFACE_TOKEN` | `kingfisher scan huggingface --huggingface-organization my-org` |
| S3 bucket | `scan s3 <bucket> [--prefix path/]` | `KF_AWS_KEY` + `KF_AWS_SECRET` (or `--profile`, or anonymous for public) | `kingfisher scan s3 my-bucket --prefix logs/` |
| GCS bucket | `scan gcs <bucket> [--prefix path/]` | `GOOGLE_APPLICATION_CREDENTIALS` or `--service-account` | `kingfisher scan gcs my-bucket --prefix data/` |
| Docker image | `scan docker <image>` or `scan docker --archive <tar>` | `KF_DOCKER_TOKEN` (else Docker keychain) | `kingfisher scan docker ghcr.io/org/image:latest` |
| Jira issues | `scan jira --url <url> --jql "<query>"` | `KF_JIRA_TOKEN` (+ `KF_JIRA_USER` for Cloud) | `kingfisher scan jira --url https://jira.example.com --jql "project = SEC"` |
| Confluence pages | `scan confluence --url <url> --cql "<query>"` | `KF_CONFLUENCE_TOKEN` (+ `KF_CONFLUENCE_USER` for Cloud) | `kingfisher scan confluence --url https://wiki.example.com --cql "label = secret"` |
| Slack | `scan slack "<search query>"` | `KF_SLACK_TOKEN` | `kingfisher scan slack "api_key OR password"` |
| Microsoft Teams | `scan teams "<search query>"` | `KF_TEAMS_TOKEN` (Graph API) | `kingfisher scan teams "password OR api_key"` |
| Postman | `scan postman --all` (or `--workspace`, `--collection`) | `KF_POSTMAN_TOKEN` / `POSTMAN_API_KEY` | `kingfisher scan postman --all` |

**Scanning Slack, Jira, Confluence, Teams, or Postman content is a compliance action, not just a technical one** — you are pulling private organizational communications and search results through a scanner. Confirm you're authorized to search that workspace/site before running any of these, the same caution as blast-radius mapping.

### GitHub Enterprise / self-hosted

Two separate flags matter, and they're not interchangeable:

- `--api-url <url>` on `scan github` — the **clone/enumeration** root (`https://ghe.example.com/api/v3/`).
- `--endpoint github=<url>` — the **validation** root, so PATs discovered in scanned source are checked against your GHE instance instead of `api.github.com`.

```bash
KF_GITHUB_TOKEN="ghp_…" kingfisher scan github \
  --organization my-org \
  --api-url https://ghe.corp.example.com/api/v3/ \
  --endpoint github=https://ghe.corp.example.com
```

They're usually the same host, but stay separate because some deployments front an SSO portal for repo access while token validation hits a direct API endpoint.

### Deprecated flags

`--github-user`, `--gitlab-group`, `--bitbucket-workspace`, `--slack-query`, `--jira-url`, `--confluence-url`, `--s3-bucket`, `--gcs-bucket`, `--docker-image`, and similar legacy top-level flags are deprecated. Use the `kingfisher scan <provider>` subcommand form shown above.

---

## Environment variables

| Variable | Purpose |
|---|---|
| `KF_GITHUB_TOKEN` | GitHub PAT |
| `KF_GITLAB_TOKEN` | GitLab PAT |
| `KF_GITEA_TOKEN` / `KF_GITEA_USERNAME` | Gitea PAT / private-clone username |
| `KF_AZURE_TOKEN` / `KF_AZURE_PAT` / `KF_AZURE_USERNAME` | Azure Repos PAT (username defaults to `pat`) |
| `KF_BITBUCKET_TOKEN` / `KF_BITBUCKET_USERNAME` / `KF_BITBUCKET_APP_PASSWORD` (deprecated 2025-09-09, disabled 2026-06-09) / `KF_BITBUCKET_OAUTH_TOKEN` | Bitbucket Cloud/Server auth |
| `KF_HUGGINGFACE_TOKEN` / `KF_HUGGINGFACE_USERNAME` | Hugging Face API + git auth |
| `KF_JIRA_TOKEN` / `KF_JIRA_USER` | Jira API token; user email required for Jira Cloud |
| `KF_CONFLUENCE_TOKEN` / `KF_CONFLUENCE_USER` | Confluence API token; user email required for Cloud |
| `KF_SLACK_TOKEN` | Slack API token |
| `KF_TEAMS_TOKEN` | Microsoft Graph API token |
| `KF_DOCKER_TOKEN` | Registry token (`user:pass` or bearer); falls back to Docker keychain |
| `KF_AWS_KEY`, `KF_AWS_SECRET`, `KF_AWS_SESSION_TOKEN` | S3 scanning credentials (session token optional) |
| `KF_RULE_CACHE_DIR` | Compiled rule cache location |

No token → public content still works everywhere it's publicly readable.

---

## Exit codes

| Code | Meaning |
|---|---|
| 0 | No findings |
| 200 | Findings discovered |
| 205 | Validated (live) findings discovered |

`kingfisher validate` and `kingfisher revoke` use a separate, simpler pair: `0` = at least one rule succeeded (valid / revoked), `1` = all failed or errored.

```bash
kingfisher scan . --since-commit origin/main --branch "$CI_BRANCH"
rc=$?
case "$rc" in
  0)   echo "✅ no findings" ;;
  200) echo "⚠️  findings, none confirmed live" ;;
  205) echo "❌ live credential found"; exit 1 ;;
  *)   echo "❌ kingfisher failed (exit $rc)"; exit 1 ;;
esac
```

Decide up front whether CI should fail on `200` (any candidate) or only `205` (confirmed live). Failing only on `205` is materially more forgiving on day one of rollout — see [Rolling this out on a repo that has never run it](#rolling-this-out-on-a-repo-that-has-never-run-it).

---

## SSRF protection and TLS

Kingfisher blocks requests to internal/RFC1918/loopback addresses by default when validating discovered credentials or hitting configured endpoints — a scanner that fetches attacker-influenced URLs is itself an SSRF vector. Pass `--allow-internal-ips` to lift this, and only for endpoints you explicitly configured (self-hosted GHE, internal Artifactory, on-prem GitLab). `--tls-mode lax` relaxes certificate validation for the same category of internal self-hosted endpoints with non-public CAs; leave it `strict` for anything reaching the public internet.

---

## Alerting

`--alert-webhook <url>` (repeatable) sends findings to a chat/SIEM sink as they're discovered. Supported payload shapes: **Slack** (Block Kit), **Microsoft Teams** (MessageCard), **generic JSON**, **Discord** (Embed), **Mattermost** (Slack-compatible attachments), **Google Chat** (cardsV2) — set explicitly with `--alert-format`, or let Kingfisher infer it from the URL.

Key knobs: `--alert-on findings|always`, `--alert-min-confidence low|medium|high`, `--alert-detail summary|detail|auto`, `--alert-finding-filter all|exclude-inactive|only-active|access-map-only`, `--alert-include-secret` (off by default — opting in puts the literal secret value in the chat payload), `--alert-prevent-empty` (skip the sink when filters leave nothing to report). All of these have `kingfisher.yaml` `alerts:` equivalents (see [schema](#full-schema)), with per-webhook overrides taking precedence over `alerts.defaults`.

---

## Pre-commit and Husky

### `pre-commit` framework

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/mongodb/kingfisher
    rev: v2.0.0
    hooks:
      - id: kingfisher-auto     # recommended: auto-downloads and caches the binary, no Docker/manual install
      # - id: kingfisher-docker # alternative: runs via Docker
      # - id: kingfisher        # alternative: uses an already-installed local binary
```

Every hook drives `kingfisher scan . --staged --quiet --no-update-check` under the hood: it snapshots the staged index into a temporary commit, diffs against `HEAD` (or an empty tree pre-first-commit), and scans only the staged delta. Exit codes surface straight to `pre-commit`, so a `205` (live credential staged) fails the commit with no extra plumbing. Trigger it in CI without installing to `.git/hooks`:

```bash
pre-commit run kingfisher-auto --all-files
```

Pin a specific binary version independent of `rev:` via `KINGFISHER_VERSION` in the hook's `env:`.

### Standalone installer (no `pre-commit` framework)

```bash
# per-repo
curl --silent --location \
  https://raw.githubusercontent.com/mongodb/kingfisher/main/scripts/install-kingfisher-pre-commit.sh | bash

# global (core.hooksPath)
curl --silent --location .../install-kingfisher-pre-commit.sh | bash -s -- --global
```

Chains **before** any existing `pre-commit` hook rather than replacing it.

### Husky (Node.js)

```bash
npx husky init
# Pin the script to the v2.0.0 commit (not `main`) and pin the binary version
# it installs — otherwise an upstream change to either runs on every
# contributor's machine on their next commit, with no PR in this repo to
# review it.
echo 'curl -fsSL https://raw.githubusercontent.com/mongodb/kingfisher/50dd87544632716fbb029f0eda7326cd868bef68/scripts/kingfisher-pre-commit-auto.sh | KINGFISHER_VERSION=2.0.0 bash' >> .husky/pre-commit
```

**State the caveat when installing any of these:** these hooks run locally and cannot enforce anything on a contributor who commits with `--no-verify` or on a clone that skipped hook install — the CI gate (below) is the actual control; the hook is a fast, friendly first line.

---

## CI integration

**There is no official `mongodb/kingfisher-action`** (unlike, say, `zizmorcore/zizmor-action`). The install-script + direct-invocation pattern below is the documented, supported path.

### Option A — hard-fail gate, install script

```yaml
# .github/workflows/secrets.yml
name: kingfisher

on:
  push:
    branches: [main]
  pull_request:

permissions: {}

jobs:
  kingfisher:
    name: Scan for leaked secrets
    runs-on: ubuntu-latest
    permissions:
      # Private repos only — public repos do not need this.
      contents: read
    steps:
      - name: Checkout
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          fetch-depth: 0           # kingfisher needs history for --since-commit
          persist-credentials: false

      - name: Install kingfisher
        run: |
          # Pin the raw script to the v2.0.0 commit, not the mutable `main`
          # branch — otherwise --tag v2.0.0 only pins the binary, and upstream
          # can still change what this job executes without a PR here.
          curl --silent --location --fail \
            https://raw.githubusercontent.com/mongodb/kingfisher/50dd87544632716fbb029f0eda7326cd868bef68/scripts/install-kingfisher.sh | \
            bash -s -- --tag v2.0.0
          # install-kingfisher.sh places the binary in ~/.local/bin by default.
          # $GITHUB_PATH is the runner-safe way to make it available to later
          # steps — safer than exporting PATH by hand, which silently breaks
          # if the install location ever changes.
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"

      - name: Scan PR diff for secrets
        env:
          # Named env vars, resolved in shell — `${{ a || b }}` does not
          # evaluate `||` between two context lookups, it silently picks
          # empty string whenever `a` is unset.
          PR_BASE_SHA: ${{ github.event.pull_request.base.sha }}
          PUSH_BEFORE_SHA: ${{ github.event.before }}
        run: |
          set +e
          BASE_SHA="${PR_BASE_SHA:-$PUSH_BEFORE_SHA}"
          # On `push`, checkout has already moved the branch ref to this
          # commit, so comparing against it (or against `origin/main`, which
          # is the same commit on a direct push to main) diffs a commit
          # against itself and finds nothing. `github.event.before` is the
          # immutable pre-push SHA. A force-push or a branch's first push
          # reports an all-zero `before`, so fall back to the parent commit.
          if [ -z "$BASE_SHA" ] || [ "$BASE_SHA" = "0000000000000000000000000000000000000000" ]; then
            BASE_SHA="HEAD~1"
          fi
          kingfisher scan . \
            --since-commit "$BASE_SHA" \
            --branch "HEAD" \
            --redact
          rc=$?
          set -e
          case "$rc" in
            0)   echo "✅ no findings" ;;
            200) echo "⚠️  candidate findings, none confirmed live — not failing by default on a first rollout; see baseline/triage guidance below. Change this line to 'exit 1' for a stricter gate once a baseline absorbs the existing backlog" ;;
            205) echo "❌ live credential found in this diff"; exit 1 ;;
            *)   echo "❌ kingfisher failed (exit $rc)"; exit 1 ;;
          esac
```

Pin `--tag` to a specific released version so the gate doesn't silently change behavior on an upstream release. If `install-kingfisher.sh` ever changes its install directory, update the `$GITHUB_PATH` line to match — check by running the script locally, don't guess.

### Option B — SARIF upload, findings as code-scanning alerts

```yaml
      - name: Scan and emit SARIF
        run: |
          kingfisher scan . --format sarif --output kingfisher.sarif --redact || true
          # kingfisher's exit code still reflects findings; `|| true` here because
          # this step's job is producing the SARIF, not gating — do the gating
          # in a separate step against the live exit code (Option A), not this one.

      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@cdf488f595d80d6e07e03d4674febd5ab45fa938  # v4.37.9
        with:
          sarif_file: kingfisher.sarif
          category: kingfisher
```

Needs `security-events: write` on the job. As with any SARIF-only step, a green job here does **not** mean no secrets were found — it means they were filed as Security-tab alerts instead of failing the build. Pair with Option A's gating step if the check itself must go red.

### Option C — Docker, no runner-side install

```yaml
      - name: Scan for secrets (Docker)
        run: |
          docker run --rm -v "$PWD":/src \
            ghcr.io/mongodb/kingfisher:2.0.0 \
            scan /src --since-commit "origin/main" --branch HEAD
```

Pin the tag (`2.0.0`, not `latest`) for the same reproducibility reason as any other container reference in CI.

### Rolling this out on a repo that has never run it

Do not start by hard-failing on exit code `200` (any candidate). A first run against an established repo typically turns up a long tail of test fixtures, documentation examples, and intentionally-fake keys (`AKIAIOSFODNN7EXAMPLE` is AWS's own canonical example key and will match). Start advisory, or gate on `205` (confirmed-live) only, while you build the baseline:

```bash
kingfisher scan . \
  --confidence low \
  --manage-baseline \
  --baseline-file ./baseline-file.yml
```

Commit that baseline, then gate future PRs against it — new secrets fail, the existing backlog is tracked without blocking merges on day one. Burn the backlog down deliberately (validate each entry, rotate anything live, then remove it from the baseline), the same posture zizmor recommends for `unpinned-uses` on a repo that predates its default policy.

---

## Common mistakes

| Mistake | Consequence | Fix |
|---|---|---|
| Treating an `assumed` finding as confirmed-live | Ships a false sense of urgency, or the opposite — ignoring it | Check `finding.validation.outcome`; only `verified_active` is network-confirmed |
| Running `--blast-radius` or `revoke` against an account without authorization | Authenticated reconnaissance/destructive action against infrastructure you don't own the risk on | Confirm authorization before either flag, same as any pentest action |
| `revoke` without validating first | Kills a credential that may already be dead, or one still in active legitimate use | `validate` → confirm owner and rotation readiness → `revoke` |
| Comparing local scan counts to CI and calling it a regression | Remote clone = history only; local checkout = filesystem + history, so local often double-counts | Use `--git-history=none` locally to reproduce remote-style counts |
| Gating CI on exit code `200` from day one on an established repo | Every PR blocked by pre-existing fixtures and example keys | Baseline first, gate on `205` or start advisory |
| `:latest` Docker tag in a CI gate | Behavior changes silently on upstream release | Pin a released version tag |
| Assuming `kingfisher.yaml` is auto-loaded | Config silently ignored, scan runs on defaults | Always pass `--config FILE` explicitly |
| Narrowing scan scope between baseline runs | `--manage-baseline` replaces a scanned repository's section with exactly what that run found — a narrower rule/path selection prunes entries that are still real | Use the same scope for baseline creation and later management |
| Building new automation on `kingfisher.*` rule IDs | Works today via the compatibility alias, breaks when the fallback is removed | Use `betterleaks.*` / `veles.*` IDs; run `kingfisher rules list` |
| Scanning Slack/Jira/Confluence without authorization to search that content | Compliance and access-scope violation, not just a technical one | Confirm authorization before any platform-target scan, same as blast-radius |

---

## Cross-references

- `/platform-skills:trivy` — fast, offline secret-pattern scanning bundled with CVE/license scans; hand off here when live validation, blast-radius, or platform-wide (Slack/Jira/S3/org) coverage is actually needed
- `/platform-skills:secrets` — how secrets are stored and rotated *inside* the cluster (ESO, Sealed Secrets); this reference is about secrets that already leaked, wherever they leaked to
- `/platform-skills:zizmor` — workflow-level `secrets:` context safety; complements, does not overlap with, literal leaked-credential detection
- `/platform-skills:supply-chain` — Cosign signing, SBOM, SLSA provenance for what the pipeline *produces*, not what leaked into it
- `/platform-skills:github-actions` — the CI workflow itself: OIDC, token scoping, job design
- `/platform-skills:preflight` — production-readiness sweep across mixed file types, including a secrets check
