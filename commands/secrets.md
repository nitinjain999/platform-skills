---
name: secrets
description: Secrets strategy, External Secrets Operator scaffolding, Sealed Secrets seal/rotate/backup, rotation runbooks, and Kubernetes-side secrets audit.
argument-hint: "[design|eso|sealed|rotate|audit] [namespace or manifest path]"
title: "Secrets Command"
sidebar_label: "secrets"
custom_edit_url: null
---

# Secrets Command

Structured guidance for secrets strategy, External Secrets Operator, Sealed Secrets, rotation, and Kubernetes-side secrets audit.

## Activation

```
/platform-skills:secrets design   # ESO vs Sealed Secrets decision; choose a strategy for the cluster
/platform-skills:secrets eso      # ExternalSecret/SecretStore scaffold; debug sync errors
/platform-skills:secrets sealed   # seal, rotate, backup master key; troubleshoot decryption failures
/platform-skills:secrets rotate   # rotation runbook — update provider value, force sync, verify pods reload
/platform-skills:secrets audit    # find bad SA tokens, unhealthy ExternalSecrets, missing secrets
```

---

## Interactive Wizard (fires when no mode is provided)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. design   — choose ESO vs Sealed Secrets for a cluster or workload
  2. eso      — scaffold ExternalSecret/SecretStore, or debug a sync error
  3. sealed   — seal a new secret, rotate an existing one, or back up the master key
  4. rotate   — end-to-end rotation runbook for a live secret
  5. audit    — find service account token secrets, unhealthy ExternalSecrets, plain secrets in Git

Enter 1–5 or mode name:
```

**Q2 — Context** (after mode selected):
- **design**: `What is the backend — AWS Secrets Manager, Azure Key Vault, HashiCorp Vault, or no cloud provider?`
- **eso**: `Paste the ExternalSecret or SecretStore YAML, or describe the sync error.`
- **sealed**: `New secret or rotating an existing one? Which namespace?`
- **rotate**: `Which secret is rotating — database password, API key, TLS cert? Which backend?`
- **audit**: `Cluster name and namespace scope. Any specific concern — Git scan, SA tokens, ESO health?`

---

## Mode: design

**Triggers:** which pattern, ESO vs Sealed Secrets, choose secrets strategy, what should I use

Read `references/secrets.md` before responding.

### Decision matrix

| Pattern | Best for | Tradeoff |
|---|---|---|
| External Secrets Operator (ESO) | Cloud-native backends: AWS Secrets Manager, Azure Key Vault, GCP Secret Manager, HashiCorp Vault | Runtime dependency on provider; requires workload identity or static credentials |
| Sealed Secrets | Air-gapped or GitOps-first teams; no external runtime dependency | Rotation requires re-sealing and a Git commit; master key backup is critical |

**Pick ESO when:**
- Cluster has workload identity (IRSA on EKS, Azure Workload Identity on AKS, Vault Kubernetes auth)
- Rotation should propagate automatically without a Git commit
- Secrets are managed centrally in a provider (team already uses AWS SM / Azure KV / Vault)

**Pick Sealed Secrets when:**
- No cloud provider or Vault
- Air-gapped environment
- Team prefers all cluster state — including encrypted secrets — reviewable in Git without a runtime backend

**Handoffs:**
- For filesystem or Git history scanning for leaked secrets → `/platform-skills:trivy` (`--scanners secret`)
- For Azure Key Vault identity setup → `/platform-skills:azure identity`
- For AWS IRSA setup → `/platform-skills:aws`

---

## Mode: eso

**Triggers:** ExternalSecret, SecretStore, ClusterSecretStore, sync error, ESO, external secrets operator, SecretSyncError

Read `references/secrets.md` → External Secrets Operator section before responding.

> **Before generating commands, confirm:**
> - ESO namespace — common values: `external-secrets`, `platform-system`, `kube-system`. Discover with: `kubectl get pods -A | grep external-secrets`
> - ESO deploy name — common values: `external-secrets`, `external-secrets-controller`. Discover with: `kubectl get deploy -n <eso-namespace>`
> - ESO service account name — the SA annotated with IRSA or Workload Identity. Common: `external-secrets-sa`, but teams name it differently.
>
> Substitute these into all namespace flags, `kubectl logs`, and `serviceAccountRef` fields below.

### ExternalSecret scaffold (provider-agnostic)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: app-team
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: my-secret-store
    kind: SecretStore
  target:
    name: database-credentials
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: prod/app-team/db
        property: password
```

### SecretStore — provider examples

**AWS Secrets Manager (IRSA):**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: my-secret-store
  namespace: app-team
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-north-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
```

Required IAM (least privilege):

```json
{
  "Effect": "Allow",
  "Action": "secretsmanager:GetSecretValue",
  "Resource": "arn:aws:secretsmanager:<region>:<account>:secret:prod/app-team/*"
}
```

**Azure Key Vault (Workload Identity):**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: my-secret-store
  namespace: app-team
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity
      vaultUrl: "https://my-keyvault.vault.azure.net"
      serviceAccountRef:
        name: external-secrets-sa
```

The managed identity needs `Key Vault Secrets User` on the Key Vault.

**HashiCorp Vault (Kubernetes auth):**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: my-secret-store
  namespace: app-team
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "app-team-role"
          serviceAccountRef:
            name: external-secrets-sa
```

### Debug ESO sync errors

```bash
# Sync status and last sync time
kubectl get externalsecret -n app-team database-credentials

# Full status including error message
kubectl describe externalsecret -n app-team database-credentials

# Operator logs for this secret
kubectl logs -n external-secrets deploy/external-secrets \
  | grep -i "database-credentials"

# SecretStore health
kubectl get secretstore -n app-team my-secret-store
kubectl describe secretstore -n app-team my-secret-store
```

| Symptom | Cause | Fix |
|---|---|---|
| `SecretSyncError: unauthorized` / `AccessDenied` | Identity missing the required permission | Check provider access policy; verify IRSA/Workload Identity annotation |
| `SecretSyncError: not found` | Secret path wrong or deleted in provider | Verify `remoteRef.key` matches the exact name in the backend |
| Secret exists but data is stale | `refreshInterval` too long | Reduce interval or force sync: `kubectl annotate externalsecret database-credentials force-sync=$(date +%s) -n app-team` |
| `SecretStore` shows `NotReady` | Provider unreachable or auth misconfigured | Check network connectivity to the provider; re-validate identity setup |
| Pod can't read the Secret | Pod references wrong Secret name or key | Verify `envFrom`/`secretKeyRef` in pod spec matches `target.name` and `secretKey` |

---

## Mode: sealed

**Triggers:** SealedSecret, kubeseal, seal, sealed secrets, no key could decrypt, master key, backup

Read `references/secrets.md` → Sealed Secrets section before responding.

### Interview — ask before generating any commands

Before writing any `kubeseal` or `kubectl` commands, collect the following. Different organisations deploy the controller with different names and namespaces.

```
Q1 — Controller namespace:
  Where is the sealed-secrets controller running?
  (common: sealed-secrets, kube-system, platform-system — check with: kubectl get pods -A | grep sealed)

Q2 — Controller name:
  What is the controller deployment name?
  (common: sealed-secrets, sealed-secrets-controller — check with: kubectl get deploy -n <namespace> | grep sealed)

Q3 — Secret namespace:
  Which namespace will the unsealed Secret live in?

Q4 — Secret name:
  What is the name of the secret?

Q5 — Action:
  1. Seal a new secret
  2. Rotate an existing sealed secret
  3. Back up the master key
  4. Restore the master key
  5. Troubleshoot a decryption failure
```

Use the answers to substitute `<controller-namespace>`, `<controller-name>`, and `<secret-namespace>` in all commands below. Never output hardcoded namespace or deployment names — always use the values the user provided.

### Seal a new secret

```bash
# Fetch the cluster public key — run once per cluster or after key rotation
kubeseal --fetch-cert \
  --controller-name=<controller-name> \
  --controller-namespace=<controller-namespace> \
  > pub-cert.pem

# Create a plain Secret and immediately seal it — never commit the plain Secret
kubectl create secret generic <secret-name> \
  --namespace=<secret-namespace> \
  --from-literal=KEY=value \
  --dry-run=client -o yaml \
  | kubeseal --cert pub-cert.pem --format yaml \
  > <secret-name>-sealed.yaml

git add <secret-name>-sealed.yaml
git commit -m "chore: seal <secret-name> for <secret-namespace>"
```

### Rotate an existing sealed secret

```bash
kubectl create secret generic <secret-name> \
  --namespace=<secret-namespace> \
  --from-literal=KEY=newvalue \
  --dry-run=client -o yaml \
  | kubeseal --cert pub-cert.pem --format yaml \
  > <secret-name>-sealed.yaml

git add <secret-name>-sealed.yaml
git commit -m "chore: rotate <secret-name>"
```

After GitOps applies the updated SealedSecret:
- Pods using a mounted volume pick up the new value automatically via kubelet refresh
- Pods using env vars require a rollout restart: `kubectl rollout restart deployment/<name> -n <secret-namespace>`

### Back up the master key

```bash
kubectl get secret -n <controller-namespace> \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-master-key-backup.yaml
```

Store this file outside the cluster (password manager, vault, encrypted object store). Without it, sealed secrets cannot be decrypted after cluster recreation.

### Restore the master key

```bash
kubectl apply -f sealed-secrets-master-key-backup.yaml
kubectl rollout restart deploy/<controller-name> -n <controller-namespace>
```

### Troubleshoot

```bash
# Confirm the controller is running
kubectl get pods -n <controller-namespace>

# Inspect SealedSecret status
kubectl describe sealedsecret <secret-name> -n <secret-namespace>

# Controller logs for decryption errors
kubectl logs -n <controller-namespace> deploy/<controller-name> | tail -50
```

| Symptom | Cause | Fix |
|---|---|---|
| `no key could decrypt secret` | Sealed with an old key after rotation | Re-seal with current cluster public key using `--fetch-cert` |
| Secret not created after GitOps sync | `metadata.namespace` mismatch | Ensure namespace in the sealed YAML matches where it will be applied |
| `cannot fetch key: secret not found` | Controller lost its own key Secret | Restore master key from backup before applying any sealed secrets |

---

## Mode: rotate

**Triggers:** rotate, rotation runbook, change password, new token, expired credential, update secret

Apply this runbook for any secret rotation:

### Step 1 — Update the value in the provider

**AWS Secrets Manager:**
```bash
aws secretsmanager put-secret-value \
  --secret-id prod/app-team/db \
  --secret-string '{"password":"new-password"}' \
  --profile <aws-profile>
```

**Azure Key Vault:**
```bash
az keyvault secret set \
  --vault-name my-keyvault \
  --name db-password \
  --value "new-password"
```

**Sealed Secrets:** Re-seal with the new value (see `sealed` mode).

### Step 2 — Force sync (ESO)

```bash
kubectl annotate externalsecret database-credentials \
  force-sync=$(date +%s) \
  -n app-team
```

### Step 3 — Verify the Kubernetes Secret was updated

```bash
# Check the last sync time
kubectl get externalsecret database-credentials -n app-team

# Confirm the Secret data changed (check hash, not the value)
kubectl get secret database-credentials -n app-team \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d | sha256sum
```

### Step 4 — Reload pods if needed

```bash
# Pods using env vars require a restart to pick up the new Secret value
kubectl rollout restart deployment/<name> -n app-team
kubectl rollout status deployment/<name> -n app-team
```

Pods using mounted volumes reload automatically within the kubelet sync period (default 60s) — no restart needed unless the app reads the value at startup only.

### Step 5 — Validate the application is using the new credential

```bash
# Application-specific validation — confirm connectivity to the backend
kubectl exec -n app-team deploy/<name> -- \
  env | grep DB_PASSWORD   # or test the connection directly
```

---

## Mode: audit

**Triggers:** audit, find plain secrets, SA token, kubernetes.io/service-account-token, secrets health, hygiene

This mode covers Kubernetes-side audit only. For filesystem and Git history scanning for leaked secrets → `/platform-skills:trivy` (`trivy fs --scanners secret` or `trivy repo --scanners secret`).

### Find workloads using legacy SA token secrets

```bash
# Find all kubernetes.io/service-account-token type secrets
kubectl get secrets -A \
  --field-selector type=kubernetes.io/service-account-token \
  -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,SA:.metadata.annotations.kubernetes\.io/service-account\.name'
```

Legacy manually-created SA token secrets do not auto-rotate. Migrate workloads to projected tokens (automatic since Kubernetes 1.24).

### Check ExternalSecret sync health across namespaces

```bash
# All ExternalSecrets and their status
kubectl get externalsecrets -A \
  -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,STATUS:.status.conditions[0].reason,LAST:.status.refreshTime'

# Find any not in Ready state
kubectl get externalsecrets -A \
  -o json \
  | jq -r '.items[] | select(.status.conditions[]?.type=="Ready" and .status.conditions[]?.status!="True") | "\(.metadata.namespace)/\(.metadata.name): \(.status.conditions[]?.message)"'
```

### Check for plain secrets committed to Git

```bash
# Trivy handles this — hand off explicitly
# trivy repo --scanners secret <repo-url>
# or for a local clone:
# trivy fs --scanners secret .
```

For a Git history and filesystem scan → `/platform-skills:trivy`

### Check SecretStore health

```bash
kubectl get secretstores -A
kubectl get clustersecretstores

# Describe any not-ready stores
kubectl get secretstores -A -o json \
  | jq -r '.items[] | select(.status.conditions[]?.status!="True") | "\(.metadata.namespace)/\(.metadata.name): \(.status.conditions[]?.message)"'
```

### Operational rules to validate

- [ ] No plain `Secret` manifests committed to Git — verify with `git log --all -- '*.yaml' | xargs grep -l 'kind: Secret'`
- [ ] All workloads use dedicated service accounts, not `default`
- [ ] No `kubernetes.io/service-account-token` type secrets for application API auth
- [ ] `ClusterSecretStore` used only for platform-wide secrets; namespace-scoped `SecretStore` for everything else
- [ ] Provider permissions scoped to minimum required paths — not `Resource: "*"` or all secrets in the vault

---

## Common mistakes

- **Committing plain `Secret` manifests to Git** — use ESO, Sealed Secrets, or Vault. Rotate any secret that was ever in Git history.
- **`secretsmanager:GetSecretValue` with `Resource: "*"`** — scope to the specific path or secret name. Wildcard grants access to all secrets in the account.
- **Using `default` service account for ESO** — creates implicit access. Create a dedicated `external-secrets-sa` per namespace.
- **Sealed Secrets rotation without `--fetch-cert`** — if the controller key rotated since the last seal, the new SealedSecret cannot be decrypted. Always fetch the current cert before sealing.
- **Skipping the master key backup before cluster destruction** — without the backup, all sealed secrets in Git are permanently unreadable on the new cluster.
- **Relying on env var pod restart for mounted volume secrets** — mounted volume secrets refresh automatically; env vars do not. Know which pattern each workload uses before planning rotation.

---

## Reference

Full guidance: `references/secrets.md`

For filesystem and Git history secret scanning: `/platform-skills:trivy`

For Azure Key Vault identity setup: `/platform-skills:azure identity`

For AWS IRSA setup: `/platform-skills:aws`
