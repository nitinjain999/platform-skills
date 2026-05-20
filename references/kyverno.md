# Kyverno Reference

Covers the new CEL-based policy types (`ValidatingPolicy`, `MutatingPolicy`, `GeneratingPolicy`, `ImageValidatingPolicy`) introduced in Kyverno v1.14–v1.15, their spec structure, match/exclude, CEL expressions, policy reporting, kyverno-cli testing, GitHub Actions integration, and troubleshooting.

> **Policy type versions**
> `ValidatingPolicy` + `ImageValidatingPolicy` → Kyverno v1.14 (April 2025)
> `MutatingPolicy`, `GeneratingPolicy`, `DeletingPolicy` → Kyverno v1.15 (July 2025)
> All types use `apiVersion: policies.kyverno.io/v1`
> Legacy `ClusterPolicy` (`kyverno.io/v1`) still works but is deprecated as of v1.17 and planned for removal in v1.20.

---

## Policy Type Overview

| Kind | Cluster-scoped | Namespace-scoped | Purpose |
|---|---|---|---|
| `ValidatingPolicy` | ✓ | `NamespacedValidatingPolicy` | Validate resources; Deny, Audit, or Warn |
| `MutatingPolicy` | ✓ | `NamespacedMutatingPolicy` | Add, replace, or remove fields |
| `GeneratingPolicy` | ✓ | `NamespacedGeneratingPolicy` | Create or clone resources on a trigger |
| `ImageValidatingPolicy` | ✓ | `NamespacedImageValidatingPolicy` | Verify container image signatures and attestations |
| `DeletingPolicy` | ✓ | `NamespacedDeletingPolicy` | Delete resources on a schedule |

All types share the same `apiVersion: policies.kyverno.io/v1`.

---

## ValidatingPolicy

Validates Kubernetes resources using CEL expressions. Replaces the `validate` rule in legacy `ClusterPolicy`.

### Minimal example

```yaml
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: require-team-labels
  annotations:
    policies.kyverno.io/title: Require team labels
    policies.kyverno.io/category: Best Practices
    policies.kyverno.io/severity: medium
    policies.kyverno.io/description: >-
      All Deployments must carry app.kubernetes.io/name and app.kubernetes.io/team labels.
spec:
  validationActions:
    - Audit                          # Audit (report only) | Deny (block) | Warn
  matchConstraints:
    resourceRules:
      - apiGroups: [apps]
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [deployments]
  validations:
    - expression: >-
        has(object.metadata.labels) &&
        'app.kubernetes.io/name' in object.metadata.labels &&
        'app.kubernetes.io/team' in object.metadata.labels
      messageExpression: >-
        "Deployment " + object.metadata.name +
        " is missing required labels app.kubernetes.io/name and app.kubernetes.io/team"
```

### Spec fields

| Field | Purpose |
|---|---|
| `validationActions` | `Deny` (block admission), `Audit` (PolicyReport only), `Warn` (warn but allow) |
| `matchConstraints.resourceRules` | Which resource kinds, API groups, versions, and operations to target |
| `matchConditions` | CEL pre-filters applied before `validations` — narrow which objects are evaluated |
| `validations` | List of CEL boolean expressions; `true` = pass, `false` = violation |
| `variables` | Named reusable CEL expressions referenced as `variables.<name>` |
| `auditAnnotations` | Key-value metadata attached to PolicyReport results |
| `evaluation` | Controls admission, background scan, and payload mode |
| `autogen` | Auto-generate rules for pod controllers |

### matchConstraints

```yaml
matchConstraints:
  resourceRules:
    - apiGroups: [apps]
      apiVersions: [v1]
      operations: [CREATE, UPDATE]        # CREATE | UPDATE | DELETE | CONNECT
      resources: [deployments, statefulsets]
```

### matchConditions — pre-filter with CEL

```yaml
matchConditions:
  - name: exclude-system-namespaces
    expression: >-
      !(object.metadata.namespace in ['kube-system', 'kube-public', 'flux-system', 'cert-manager'])
```

Only objects that pass **all** `matchConditions` proceed to `validations`.

### validations — CEL expressions

Each validation has:
- `expression` — CEL boolean; `true` means the resource passes
- `message` — static error string (shown when expression is false)
- `messageExpression` — dynamic CEL string (takes precedence over `message` if both present)

```yaml
validations:
  - expression: "object.spec.replicas >= 2"
    messageExpression: >-
      "Deployment " + object.metadata.name + " has " +
      string(object.spec.replicas) + " replicas; minimum is 2"

  - expression: >-
      object.spec.template.spec.containers.all(c,
        has(c.resources) && has(c.resources.limits) &&
        has(c.resources.limits.memory) && has(c.resources.limits.cpu)
      )
    message: "All containers must have CPU and memory limits set."

  - expression: >-
      object.spec.template.spec.containers.all(c,
        !c.image.endsWith(':latest')
      )
    messageExpression: >-
      "Container image must not use ':latest' tag in " + object.metadata.name
```

### variables — reusable sub-expressions

```yaml
spec:
  variables:
    - name: hasLabels
      expression: "has(object.metadata.labels)"
    - name: teamLabel
      expression: >-
        variables.hasLabels && 'app.kubernetes.io/team' in object.metadata.labels
  validations:
    - expression: "variables.teamLabel"
      message: "app.kubernetes.io/team label is required."
```

### evaluation — background scan and mode

```yaml
spec:
  evaluation:
    admission:
      enabled: true          # run at admission time (default true)
    background:
      enabled: true          # scan existing resources (default true)
    mode: Kubernetes          # Kubernetes | JSON
```

### Namespace-scoped variant

```yaml
apiVersion: policies.kyverno.io/v1
kind: NamespacedValidatingPolicy
metadata:
  name: require-min-replicas
  namespace: production
spec:
  validationActions: [Deny]
  matchConstraints:
    resourceRules:
      - apiGroups: [apps]
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [deployments]
  validations:
    - expression: "object.spec.replicas >= 2"
      message: "Deployments in production must have at least 2 replicas."
```

---

## MutatingPolicy

Adds, replaces, or removes fields using CEL expressions. Replaces the `mutate` rule in legacy `ClusterPolicy`.

Two mutation patch types:
- **`ApplyConfiguration`** — strategic merge style; CEL returns an `Object{...}` overlay
- **`JSONPatch`** — RFC 6902 operations; CEL returns a list of `JSONPatch{op, path, value}`

### Add a label (ApplyConfiguration)

```yaml
apiVersion: policies.kyverno.io/v1
kind: MutatingPolicy
metadata:
  name: add-managed-label
spec:
  matchConstraints:
    resourceRules:
      - apiGroups: [apps]
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [deployments, statefulsets, daemonsets]
  mutations:
    - patchType: ApplyConfiguration
      applyConfiguration:
        expression: >-
          Object{
            metadata: Object.metadata{
              labels: Object.metadata.labels{
                "app.kubernetes.io/managed-by": "platform"
              }
            }
          }
```

### Conditional mutation (ApplyConfiguration)

```yaml
mutations:
  - patchType: ApplyConfiguration
    applyConfiguration:
      expression: >-
        !has(object.metadata.labels) || !('env' in object.metadata.labels) ?
        Object{
          metadata: Object.metadata{
            labels: Object.metadata.labels{
              env: "dev"
            }
          }
        } :
        Object{}
```

### Set imagePullPolicy on all containers (loop)

```yaml
mutations:
  - patchType: ApplyConfiguration
    applyConfiguration:
      expression: >-
        Object{
          spec: Object.spec{
            containers: object.spec.containers.map(c, Object.spec.containers{
              name: c.name,
              imagePullPolicy: "IfNotPresent"
            })
          }
        }
```

### JSONPatch — precise operations

```yaml
mutations:
  - patchType: JSONPatch
    jsonPatch:
      expression: >-
        has(object.metadata.labels) ?
        [JSONPatch{op: "add", path: "/metadata/labels/managed", value: "true"}] :
        [JSONPatch{op: "add", path: "/metadata/labels", value: {"managed": "true"}}]
```

Special characters in path keys must be escaped with `jsonpatch.escapeKey()`:

```yaml
expression: >-
  [JSONPatch{
    op: "add",
    path: "/metadata/labels/" + jsonpatch.escapeKey("app.kubernetes.io/name"),
    value: "my-app"
  }]
```

### Mutate existing resources

```yaml
spec:
  evaluation:
    mutateExisting:
      enabled: true      # applies to resources that already exist in the cluster
  matchConstraints:
    resourceRules:
      - apiGroups: [apps]
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [deployments]
  mutations:
    - patchType: ApplyConfiguration
      applyConfiguration:
        expression: >-
          Object{
            metadata: Object.metadata{
              labels: Object.metadata.labels{
                "platform.example.com/managed": "true"
              }
            }
          }
```

`mutateExisting` processing is asynchronous. Kyverno's background controller needs RBAC permissions to patch the target resources.

### reinvocationPolicy

```yaml
spec:
  reinvocationPolicy: IfNeeded    # re-runs if a prior mutation changed the object; default Never
```

---

## GeneratingPolicy

Creates or clones Kubernetes resources when a trigger resource is created or updated. Replaces the `generate` rule in legacy `ClusterPolicy`. Uses `generator.Apply()` in CEL expressions.

### Generate a NetworkPolicy in every new namespace

```yaml
apiVersion: policies.kyverno.io/v1
kind: GeneratingPolicy
metadata:
  name: default-deny-ingress
spec:
  evaluation:
    synchronize:
      enabled: true             # keep generated resource in sync with the policy
    generateExisting:
      enabled: true             # retroactively apply to existing namespaces
    orphanDownstreamOnPolicyDelete:
      enabled: false            # delete generated resources when policy is deleted
  matchConstraints:
    resourceRules:
      - apiGroups: ['']
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [namespaces]
  matchConditions:
    - name: exclude-system-namespaces
      expression: >-
        !(object.metadata.name in ['kube-system','kube-public','kube-node-lease'])
  variables:
    - name: nsName
      expression: "object.metadata.name"
    - name: networkPolicy
      expression: >-
        [
          {
            "kind": dyn("NetworkPolicy"),
            "apiVersion": dyn("networking.k8s.io/v1"),
            "metadata": dyn({
              "name": "default-deny-ingress",
              "namespace": string(variables.nsName),
              "labels": dyn({"app.kubernetes.io/managed-by": "kyverno"})
            }),
            "spec": dyn({
              "podSelector": dyn({}),
              "policyTypes": dyn(["Ingress"])
            })
          }
        ]
  generate:
    - expression: "generator.Apply(variables.nsName, variables.networkPolicy)"
```

### Clone a secret into every new namespace

```yaml
apiVersion: policies.kyverno.io/v1
kind: GeneratingPolicy
metadata:
  name: clone-registry-pull-secret
spec:
  evaluation:
    synchronize:
      enabled: true
  matchConstraints:
    resourceRules:
      - apiGroups: ['']
        apiVersions: [v1]
        operations: [CREATE]
        resources: [namespaces]
  variables:
    - name: nsName
      expression: "object.metadata.name"
    - name: source
      expression: 'resource.Get("v1", "secrets", "kube-system", "registry-pull-secret")'
  generate:
    - expression: "generator.Apply(variables.nsName, [variables.source])"
```

### Spec fields

| Field | Purpose |
|---|---|
| `evaluation.synchronize.enabled` | Keep generated resources in sync when the policy or source changes |
| `evaluation.generateExisting.enabled` | Apply retroactively to existing trigger resources |
| `evaluation.orphanDownstreamOnPolicyDelete.enabled` | Retain generated resources when the policy is deleted |
| `variables` | Named CEL expressions; inline resource definitions use `dyn()` for dynamic typing |
| `generate` | List of CEL expressions invoking `generator.Apply(namespace, [resources])` |

---

## ImageValidatingPolicy

Verifies container image signatures and attestations. Replaces the `verifyImages` rule in legacy `ClusterPolicy`. Uses CEL functions `verifyImageSignatures()`, `verifyAttestationSignatures()`, and `extractPayload()`.

### Cosign keyless verification (Sigstore)

```yaml
apiVersion: policies.kyverno.io/v1
kind: ImageValidatingPolicy
metadata:
  name: verify-image-signatures
spec:
  validationActions: [Deny]
  matchConstraints:
    resourceRules:
      - apiGroups: ['']
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [pods]
  matchImageReferences:
    - glob: "registry.internal.example.com/*"
  attestors:
    - name: cosign
      cosign:
        keyless:
          identities:
            - subject: "https://github.com/your-org/your-repo/.github/workflows/release.yaml@refs/heads/main"
              issuer: "https://token.actions.githubusercontent.com"
          ctlog:
            url: https://rekor.sigstore.dev
            insecureIgnoreTlog: false
  validationConfigurations:
    mutateDigest: true         # replace tag with digest after verification
    required: true             # reject images with no valid signature
    verifyDigest: true
  validations:
    - expression: >-
        images.containers.map(image,
          verifyImageSignatures(image, [attestors.cosign])
        ).all(e, e > 0)
      message: "Image must be signed via Cosign keyless (Sigstore)."
```

### Cosign key-based verification

```yaml
attestors:
  - name: cosign
    cosign:
      key:
        data: |
          -----BEGIN PUBLIC KEY-----
          MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
          -----END PUBLIC KEY-----
validations:
  - expression: >-
      images.containers.map(image,
        verifyImageSignatures(image, [attestors.cosign])
      ).all(e, e > 0)
    message: "Image must be signed with the platform Cosign key."
```

### Notary with SBOM attestation

```yaml
attestors:
  - name: notary
    notary:
      certs:
        value: |-
          -----BEGIN CERTIFICATE-----
          MIIBjTCCATOg...
          -----END CERTIFICATE-----
attestations:
  - name: sbom
    referrer:
      type: sbom/cyclone-dx
validations:
  - expression: >-
      images.containers.map(image,
        verifyImageSignatures(image, [attestors.notary])
      ).all(e, e > 0)
    message: "Image must be signed with the Notary certificate."
  - expression: >-
      images.containers.map(image,
        verifyAttestationSignatures(image, attestations.sbom, [attestors.notary])
      ).all(e, e > 0)
    message: "Image must have a valid CycloneDX SBOM attestation."
  - expression: >-
      images.containers.map(image,
        extractPayload(image, attestations.sbom).bomFormat == "CycloneDX"
      ).all(e, e)
    message: "SBOM must be in CycloneDX format."
```

### matchImageReferences

```yaml
matchImageReferences:
  - glob: "ghcr.io/your-org/*"            # glob pattern
  - expression: "image.registry == 'registry.internal.example.com'"  # CEL
```

### CEL image verification functions

| Function | Returns | Purpose |
|---|---|---|
| `images.containers` | list | All container images in the resource |
| `verifyImageSignatures(image, [attestors.x])` | int (count) | Verify signatures; > 0 means at least one signature is valid |
| `verifyAttestationSignatures(image, attestations.x, [attestors.x])` | int | Verify attestation signatures |
| `extractPayload(image, attestations.x)` | object | Extract attestation payload (requires prior signature verification) |

---

## Audit → Enforce Promotion

Always start with `Audit`. Promote to `Deny` only after PolicyReport violations reach zero.

```
validationActions: [Audit]  →  fix workloads  →  validationActions: [Deny]
```

### Check violations

```bash
kubectl get policyreport -A
kubectl get clusterpolicyreport

# All failing results across all namespaces
kubectl get policyreport -A -o json \
  | jq '[.items[].results[] | select(.result == "fail")]'
```

### Promote to Deny

```bash
kubectl patch validatingpolicy require-team-labels \
  --type merge \
  -p '{"spec":{"validationActions":["Deny"]}}'
```

Blast radius: any non-compliant CREATE or UPDATE will be blocked immediately. Keep the Audit→Deny rollback ready.

---

## PolicyException

Grant a named exception to a specific resource without modifying the policy.

```yaml
apiVersion: kyverno.io/v2
kind: PolicyException
metadata:
  name: allow-privileged-monitoring-agent
  namespace: monitoring
spec:
  exceptions:
    - policyName: disallow-privileged-containers
      ruleNames:
        - disallow-privileged
  match:
    any:
      - resources:
          kinds:
            - DaemonSet
          names:
            - datadog-agent
          namespaces:
            - monitoring
```

PolicyException uses `kyverno.io/v2` — it is not part of the new `policies.kyverno.io/v1` group. Require platform team review before merging; it is a last resort.

---

## kyverno-cli Testing

Test policies locally without a running cluster.

### Install

```bash
brew install kyverno                          # macOS
```

### Apply a policy to a manifest

```bash
kyverno apply ./policies/require-team-labels.yaml \
  --resource ./resources/deployment.yaml \
  --detailed-results
```

### Run the full test suite

```bash
kyverno test .
```

This reads any `kyverno-test.yaml` in the current directory.

### Test manifest structure

```yaml
name: require-team-labels-test
policies:
  - policies/require-team-labels.yaml
resources:
  - resources/deployment-with-labels.yaml
  - resources/deployment-missing-labels.yaml
results:
  - policy: require-team-labels
    rule: autogen-check-labels        # name from spec.validations[0] or autogen name
    resource: deployment-with-labels
    kind: Deployment
    result: pass
  - policy: require-team-labels
    rule: autogen-check-labels
    resource: deployment-missing-labels
    kind: Deployment
    result: fail
```

---

## PolicyReport

Kyverno writes results to `PolicyReport` (namespaced) and `ClusterPolicyReport` (cluster-scoped).

```bash
# All namespaced violations
kubectl get policyreport -A -o json \
  | jq '[.items[].results[] | select(.result == "fail")
         | {policy: .policy, resource: .resources[0].name, message: .message}]'

# Export all violations to CSV
kubectl get policyreport -A -o json \
  | jq -r '["namespace","resource","policy","result","message"],
            (.items[] | .metadata.namespace as $ns |
             .results[] | [$ns, .resources[0].name, .policy, .result, .message])
            | @csv'
```

---

## GitHub Actions Integration

```yaml
name: Kyverno policy validation

on:
  pull_request:

jobs:
  kyverno:
    name: Kyverno
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1

      - name: Install kyverno CLI
        run: |
          VERSION=$(curl -s https://api.github.com/repos/kyverno/kyverno/releases/latest \
            | jq -r .tag_name)
          curl -LO "https://github.com/kyverno/kyverno/releases/download/${VERSION}/kyverno-cli_${VERSION}_linux_x86_64.tar.gz"
          tar xzf kyverno-cli_*.tar.gz
          sudo mv kyverno /usr/local/bin/

      - name: Apply policies to manifests
        run: |
          kyverno apply ./policies/ \
            --resource ./manifests/ \
            --detailed-results

      - name: Run kyverno tests
        run: kyverno test ./tests/
```

---

## Common Policy Patterns

### Require resource limits on all Deployments

```yaml
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: require-resource-limits
  annotations:
    policies.kyverno.io/title: Require resource limits
    policies.kyverno.io/category: Best Practices
    policies.kyverno.io/severity: medium
    policies.kyverno.io/description: >-
      All containers in a Deployment must have CPU and memory limits set.
spec:
  validationActions: [Audit]
  matchConstraints:
    resourceRules:
      - apiGroups: [apps]
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [deployments]
  matchConditions:
    - name: exclude-system-namespaces
      expression: >-
        !(object.metadata.namespace in ['kube-system', 'kube-public'])
  validations:
    - expression: >-
        object.spec.template.spec.containers.all(c,
          has(c.resources) &&
          has(c.resources.limits) &&
          has(c.resources.limits.cpu) &&
          has(c.resources.limits.memory)
        )
      messageExpression: >-
        "Deployment " + object.metadata.name +
        " has containers without CPU and memory limits."
```

### Disallow privileged containers

```yaml
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: disallow-privileged-containers
  annotations:
    policies.kyverno.io/title: Disallow privileged containers
    policies.kyverno.io/category: Pod Security
    policies.kyverno.io/severity: high
    policies.kyverno.io/description: >-
      Privileged containers have unrestricted host access and must not be used.
spec:
  validationActions: [Deny]
  matchConstraints:
    resourceRules:
      - apiGroups: ['']
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [pods]
  matchConditions:
    - name: exclude-system-namespaces
      expression: "!(object.metadata.namespace in ['kube-system'])"
  validations:
    - expression: >-
        object.spec.containers.all(c,
          !has(c.securityContext) ||
          !has(c.securityContext.privileged) ||
          c.securityContext.privileged == false
        ) &&
        (!has(object.spec.initContainers) ||
          object.spec.initContainers.all(c,
            !has(c.securityContext) ||
            !has(c.securityContext.privileged) ||
            c.securityContext.privileged == false
          )
        )
      message: >-
        Privileged containers are not allowed.
        Remove securityContext.privileged: true from all containers and initContainers.
```

### Add default labels via mutation

```yaml
apiVersion: policies.kyverno.io/v1
kind: MutatingPolicy
metadata:
  name: add-platform-label
spec:
  matchConstraints:
    resourceRules:
      - apiGroups: [apps]
        apiVersions: [v1]
        operations: [CREATE]
        resources: [deployments, statefulsets, daemonsets]
  mutations:
    - patchType: ApplyConfiguration
      applyConfiguration:
        expression: >-
          Object{
            metadata: Object.metadata{
              labels: Object.metadata.labels{
                "app.kubernetes.io/managed-by": "platform"
              }
            }
          }
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Policy created but no PolicyReport entries | `evaluation.background.enabled` is false | Set `evaluation.background.enabled: true` |
| Admission passes when it should fail | `validationActions: [Audit]` not `[Deny]` | Change to `[Deny]` after fixing violations |
| CEL expression error on admission | Syntax error or wrong field path | Test with `kyverno apply` CLI and check events on the resource |
| `matchConditions` not filtering expected resources | `matchConditions` uses AND logic — all must pass | Verify each condition independently with `kyverno apply` |
| `GeneratingPolicy` not creating downstream resource | `generator.Apply()` target namespace doesn't exist yet, or missing RBAC | Check background controller logs: `kubectl logs -n kyverno -l app.kubernetes.io/component=background-controller` |
| `MutatingPolicy` not applying to existing resources | `evaluation.mutateExisting.enabled` not set | Set `mutateExisting.enabled: true`; note processing is async |
| `verifyImageSignatures()` returns 0 | Attestor subject/issuer mismatch, or no signature in transparency log | Run `cosign verify` manually; check `subjectRegExp`/`issuerRegExp` against the actual certificate |
| PolicyException not taking effect | PolicyException still uses `kyverno.io/v2` — check the rule name matches | Verify `spec.exceptions[].ruleNames` matches the rule name in the policy's `validations` |
| `resource.Get()` in GeneratingPolicy returns empty | Source resource does not exist or RBAC missing for background controller | Confirm source resource exists; check Kyverno RBAC for `get` on that resource type |
| Legacy `ClusterPolicy` coexists with new types | Both APIs work in parallel — no conflict | Migration is optional until v1.20; convert incrementally |

## Platform Rules

- `ImageValidatingPolicy`: target `apiGroups: [""]` / `resources: ["pods"]` to cover all workload types; Kyverno autogen does not extend `ImageValidatingPolicy` by default
- Audit→Deny promotion sequence applies to pre-emptive policies; reactive policies (e.g. Falco→Kyverno bridge where violation is already confirmed) should start at `validationActions: [Deny]`
