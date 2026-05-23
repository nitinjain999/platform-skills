# Composite Actions Examples

Production-ready composite GitHub Actions covering the most common platform engineering workflows. Every example ships with a full repo structure: `action.yml`, `README.md`, `CHANGELOG.md`, test workflow, release workflow, and `dependabot.yml`.

Status: Stable

---

## Quick reference

| Example | What it does | Key patterns |
|---|---|---|
| [docker-build-push](docker-build-push/) | Build + push to GHCR | OIDC, multi-platform, SLSA provenance, SBOM |
| [notify-slack](notify-slack/) | Slack build status notification | `::add-mask::`, secrets-as-inputs, payload via printf |
| [k8s-deploy](k8s-deploy/) | Apply manifest + rollout wait | kubeconfig tempfile, chmod 600, cleanup always |
| [terraform-plan](terraform-plan/) | tf fmt → validate → plan → PR comment | AWS+Azure OIDC, idempotent comment upsert |
| [security-scan](security-scan/) | Trivy image/fs scan + gate | Severity enum, SARIF output, inline annotations |
| [release-tag](release-tag/) | Semver bump + GitHub release | Conventional commits, `$GITHUB_OUTPUT` chaining |
| [pr-comment](pr-comment/) | Post or update a PR comment | Hidden marker upsert, collapsible, delete-on-close |
| [setup-env](setup-env/) | Install Node/Python/Go + cache | Multi-runtime, cache key, `runtime_version` output |

---

## Pick the right example

```
Need to build and push a container image?          → docker-build-push
Need to notify a team on success/failure?          → notify-slack
Need to deploy to Kubernetes?                      → k8s-deploy
Need to run Terraform and show the plan in a PR?   → terraform-plan
Need to scan for CVEs before deploying?            → security-scan
Need to version and release automatically?         → release-tag
Need to post a structured comment on a PR?         → pr-comment
Need to set up a language runtime with caching?    → setup-env (tutorial baseline)
```

---

## What every example includes

| File | Purpose |
|---|---|
| `action.yml` | Composite action definition |
| `README.md` | Inputs/outputs table, variables & secrets guide, full usage example |
| `CHANGELOG.md` | Version history |
| `.github/workflows/test-action.yml` | Test workflow using local path reference + matrix |
| `.github/workflows/release.yml` | Tag → actionlint validation → floating major tag → GitHub release |
| `.github/dependabot.yml` | Weekly SHA updates for all pinned external actions |

---

## Shared best practices applied across all examples

| Practice | Applied in |
|---|---|
| `shell:` on every `run:` step | All |
| All external `uses:` pinned to 40-char SHA with version comment | All |
| Secrets passed as `required: true` inputs, never `${{ secrets.* }}` | All |
| `::add-mask::` on secrets immediately after reading | notify-slack, k8s-deploy, terraform-plan, release-tag, pr-comment |
| Inputs passed through `env:` block — never interpolated in `run:` | All |
| Input validation step as the first step with `::error::` fail-fast | All |
| `$GITHUB_STEP_SUMMARY` written in every action | All |
| `::group::` / `::endgroup::` around each logical phase | All |
| `::error::` / `::warning::` annotations for findings | security-scan, release-tag |
| `timeout-minutes` on network-bound steps | notify-slack, k8s-deploy, security-scan |
| Idempotent by design (documented in each README) | All |
| `dependabot.yml` for `github-actions` ecosystem | All |
| Release workflow with `actionlint` gate + SHA pinning check | All |

---

## Generate a new action

```
/platform-skills:composite-actions generate
```

Runs a guided interview → produces a full repo scaffold matching this structure → optionally opens a PR on an existing repo.

---

## Audit an existing action

```
/platform-skills:composite-actions review
```

Audits any `action.yml` against the production checklist. Reports CRITICAL / WARNING / INFORMATIONAL findings with a score.

---

## Further reading

- **Reference:** [references/composite-actions.md](../../../references/composite-actions.md) — full documentation
- **Command:** [commands/composite-actions.md](../../../commands/composite-actions.md) — all modes
- **Upstream docs:** [Creating a composite action — GitHub Docs](https://docs.github.com/en/actions/tutorials/create-actions/create-a-composite-action)
