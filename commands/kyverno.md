---
name: kyverno
description: Generate, test, audit, debug, and migrate Kyverno policies using the new CEL-based policy types (ValidatingPolicy, MutatingPolicy, GeneratingPolicy, ImageValidatingPolicy — all apiVersion policies.kyverno.io/v1). Covers matchConstraints, matchConditions, CEL validations/mutations, generator.Apply(), Audit→Deny promotion, PolicyException, kyverno-cli testing, and migration from legacy ClusterPolicy or PodSecurityPolicy. Use when asked to "write a Kyverno policy", "test a ValidatingPolicy", "audit my cluster for violations", "why is my policy not firing", or "migrate from ClusterPolicy".
argument-hint: "[generate|test|audit|debug|migrate] [policy description or file path]"
---

Write, test, audit, debug, and migrate Kyverno policies using the new CEL-based policy types.

All new policies use `apiVersion: policies.kyverno.io/v1`. Legacy `ClusterPolicy` (`kyverno.io/v1`) still works but is deprecated in v1.17 and planned for removal in v1.20.

---

## Interactive Wizard (fires when no arguments are provided)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. generate — write a new production-ready Kyverno policy
  2. test     — write kyverno-test.yaml fixtures and run kyverno-cli
  3. audit    — analyse PolicyReport data from a running cluster
  4. debug    — diagnose why a policy is not behaving as expected
  5. migrate  — convert a legacy ClusterPolicy or PodSecurityPolicy

Enter 1–5 or mode name:
```

**Q2 — Context** (after mode selected, one at a time):
- **generate**: `Describe the policy — what should it validate, mutate, or enforce? (e.g. "require app.kubernetes.io/team label on all Deployments"):`
- **test**: `Paste or describe the policy to test:`
- **audit**: `Paste the PolicyReport JSON or run: kubectl get policyreport -A -o json | jq '[.items[].results[] | select(.result == "fail")]'`
- **debug**: `Describe the symptom — is the policy not blocking, not mutating, or not appearing in PolicyReport?`
- **migrate**: `Paste the existing ClusterPolicy or PodSecurityPolicy YAML to migrate:`

Then proceed into the relevant mode below.

---

## Mode: generate

Write a production-ready Kyverno policy from a description.

Steps:
1. Ask for: policy type (ValidatingPolicy / MutatingPolicy / GeneratingPolicy / ImageValidatingPolicy), target resource kinds, whether cluster-wide or namespace-scoped, and whether to start in Audit or Deny mode
2. Start in `validationActions: [Audit]` unless the user explicitly requests Deny — blocking admission with an untested policy is high blast radius
3. Generate the policy with:
   - `apiVersion: policies.kyverno.io/v1`
   - `annotations` block: `policies.kyverno.io/title`, `category`, `severity`, `description`
   - `matchConstraints.resourceRules` targeting only the required kinds and operations
   - `matchConditions` to exclude system namespaces (`kube-system`, `kube-public`, and platform tooling namespaces) — this replaces the old `exclude` block
   - For `ValidatingPolicy`: `validations` with CEL boolean expressions; use `messageExpression` for dynamic messages that include the resource name
   - For `MutatingPolicy`: `mutations` with `patchType: ApplyConfiguration` (prefer for adds/merges) or `patchType: JSONPatch` (for precise path operations); use `jsonpatch.escapeKey()` for special characters in paths
   - For `GeneratingPolicy`: `variables` with `dyn()` for inline resource definitions; `generate` with `generator.Apply(namespace, [resources])`; set `evaluation.synchronize.enabled: true`
   - For `ImageValidatingPolicy`: `matchImageReferences` with glob or CEL; `attestors` with cosign keyless or key-based; `validations` using `verifyImageSignatures()` CEL function
4. Show the kyverno-cli command to dry-run: `kyverno apply <policy.yaml> --resource <manifest.yaml> --detailed-results`

Reference: `references/kyverno.md` → ValidatingPolicy, MutatingPolicy, GeneratingPolicy, ImageValidatingPolicy

## Mode: test

Write a `kyverno-test.yaml` manifest and companion resource fixtures.

Steps:
1. Read the policy — identify: kind, `matchConstraints` resource rules, `matchConditions`, and what each validation expression approves vs denies
2. For each validation, create:
   - A **passing resource** — a manifest that satisfies the CEL expression (result: pass)
   - A **failing resource** — a manifest that violates the CEL expression (result: fail)
   - If `matchConditions` exclude a namespace, a **resource in an excluded namespace** (result: skip)
3. Build `kyverno-test.yaml`:
   ```yaml
   name: <policy-name>-test
   policies:
     - <policy-file>.yaml
   resources:
     - resources/<passing-manifest>.yaml
     - resources/<failing-manifest>.yaml
   results:
     - policy: <policy-name>
       rule: <validation-name-or-autogen>
       resource: <passing-resource-name>
       kind: <Kind>
       result: pass
     - policy: <policy-name>
       rule: <validation-name-or-autogen>
       resource: <failing-resource-name>
       kind: <Kind>
       result: fail
   ```
4. Run: `kyverno test .` — all results must match
5. Note: CEL `resource.Get()` / `resource.List()` (used in GeneratingPolicy) are not available in CLI tests — those require cluster-side testing

Reference: `references/kyverno.md` → kyverno-cli Testing

## Mode: audit

Analyse PolicyReport data from a running cluster and produce an actionable violation summary.

Steps:
1. Collect violation data:
   ```bash
   kubectl get policyreport -A -o json \
     | jq '[.items[].results[] | select(.result == "fail")]'
   kubectl get clusterpolicyreport -o json \
     | jq '[.items[].results[] | select(.result == "fail")]'
   ```
2. Group violations by policy (highest severity first), then by resource kind — identify highest-volume policies first
3. For each violated policy:
   - State the policy name, severity, and current `validationActions`
   - List affected resources (namespace/name)
   - Assess fix effort: update the resource manifest, or use PolicyException for a legitimate carve-out?
4. Recommend remediation order: fix high-severity violations first; PolicyException is a last resort requiring documented justification
5. Show the promote command for each zero-violation policy:
   ```bash
   kubectl patch validatingpolicy <name> \
     --type merge \
     -p '{"spec":{"validationActions":["Deny"]}}'
   ```
6. Flag any policy in `[Deny]` mode with active PolicyReport violations — indicates a suppressed PolicyException that needs review

Reference: `references/kyverno.md` → Audit → Enforce Promotion, PolicyReport

## Mode: debug

Diagnose why a Kyverno policy is not behaving as expected.

Steps:
1. Collect:
   - Policy YAML: `kubectl get validatingpolicy <name> -o yaml`
   - Resource YAML: `kubectl get <kind> <name> -n <ns> -o yaml`
   - Admission events: `kubectl describe <kind> <name> -n <ns>`
   - Kyverno admission controller logs: `kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller --tail=100`
   - Background controller logs (for GeneratingPolicy/MutatingPolicy existing): `kubectl logs -n kyverno -l app.kubernetes.io/component=background-controller --tail=100`
   - PolicyReport: `kubectl get policyreport -n <ns> -o yaml`
2. Check in order:
   - **Webhook not registered**: `kubectl get validatingwebhookconfigurations` — if missing, Kyverno is not running or failed to register
   - **matchConstraints not covering the resource**: compare `spec.matchConstraints.resourceRules` kinds, apiGroups, and operations against the actual resource
   - **matchConditions filtering out the resource**: evaluate each `matchConditions` expression against the resource manually with `kyverno apply`
   - **validationActions is [Audit] not [Deny]**: policy reports violation but doesn't block — check PolicyReport, not admission events
   - **background scan not yet run**: existing resources may not appear in PolicyReport until next background scan (default interval 1h); check `evaluation.background.enabled: true`
   - **MutatingPolicy mutateExisting not set**: existing resources are not patched — set `evaluation.mutateExisting.enabled: true`
   - **CEL expression syntax error**: look for CEL evaluation error in admission events; test the expression with `kyverno apply` CLI
   - **PolicyException suppressing**: `kubectl get policyexception -A` — check if an exception covers this resource and policy
3. State the most likely root cause with the exact field to change
4. Show the corrected policy section and the command: `kyverno apply <policy.yaml> --resource <manifest.yaml> --detailed-results`

Reference: `references/kyverno.md` → Troubleshooting

## Mode: migrate

Migrate from legacy `ClusterPolicy` (`kyverno.io/v1`) or PodSecurityPolicy to the new policy types.

### From legacy ClusterPolicy

Map each rule type to the new kind:

| Legacy rule type | New kind |
|---|---|
| `validate` rule | `ValidatingPolicy` |
| `mutate` rule | `MutatingPolicy` |
| `generate` rule | `GeneratingPolicy` |
| `verifyImages` rule | `ImageValidatingPolicy` |

Key syntax changes:
- `spec.rules[].match.any[].resources` → `spec.matchConstraints.resourceRules[]`
- `spec.rules[].exclude` → `spec.matchConditions` with CEL negation
- `validate.pattern` (JMESPath anchors) → `validations[].expression` (CEL boolean)
- `validate.deny.conditions` → `validations[].expression` with inverted CEL
- `mutate.patchStrategicMerge` → `mutations[].patchType: ApplyConfiguration` with `Object{...}` CEL
- `mutate.patchesJSON6902` → `mutations[].patchType: JSONPatch` with `[JSONPatch{...}]` CEL
- `generate.data` / `generate.clone` → `generate[].expression` using `generator.Apply()` and `resource.Get()`
- `verifyImages[].attestors` → `attestors[]` + `validations[].expression` using `verifyImageSignatures()`
- `validationFailureAction: Enforce` → `validationActions: [Deny]`
- `validationFailureAction: Audit` → `validationActions: [Audit]`

Migration workflow:
1. Write the new-style policy in `[Audit]` mode
2. Deploy alongside the existing ClusterPolicy — both can coexist
3. Verify PolicyReport shows identical violations from the new policy
4. Switch new policy to `[Deny]`
5. Remove the legacy ClusterPolicy

### From PodSecurityPolicy

Map each PSP field to a `ValidatingPolicy`:

| PSP field | ValidatingPolicy CEL expression |
|---|---|
| `privileged: false` | `object.spec.containers.all(c, !has(c.securityContext) \|\| !c.securityContext.?privileged.orValue(false))` |
| `hostNetwork: false` | `!has(object.spec.hostNetwork) \|\| object.spec.hostNetwork == false` |
| `runAsNonRoot: true` | `object.spec.containers.all(c, has(c.securityContext) && c.securityContext.runAsNonRoot == true)` |
| `readOnlyRootFilesystem: true` | `object.spec.containers.all(c, has(c.securityContext) && c.securityContext.readOnlyRootFilesystem == true)` |

Deploy all new policies in `[Audit]` mode first, fix workloads, then switch to `[Deny]` before removing PSPs.

Reference: `references/kyverno.md` → Common Policy Patterns
