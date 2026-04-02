# Secrets Reference

## Contents

- Scope
- Decision matrix
- External Secrets Operator
- Sealed Secrets
- Operational rules

## Scope

Use this reference when:

- Choosing a secrets strategy for a new cluster
- Rotating secrets without redeploying workloads
- Auditing how secrets flow from a provider into pods
- Debugging missing or stale secrets in running workloads

Do not store plain secrets in Git. Choose one of the patterns below based on your infrastructure and GitOps setup.

## Decision matrix

| Pattern | Best for | Tradeoff |
|---|---|---|
| External Secrets Operator (ESO) | Cloud-native backends: AWS Secrets Manager, Azure Key Vault, GCP Secret Manager, HashiCorp Vault, and more | Runtime dependency on provider; requires identity or static credentials |
| Sealed Secrets | Air-gapped or simple setups; GitOps-first encryption with no external runtime dependency | Rotation requires re-sealing and a Git commit; master key backup is critical |
| Vault Secrets Operator | HashiCorp Vault as primary secrets backend; multi-cloud or on-prem | Vault HA required in production; more moving parts |

**When to pick ESO:** The cluster already has workload identity (IRSA on EKS, Workload Identity on AKS/GKE, Vault JWT auth). Secrets are managed in a central provider. Rotation should propagate automatically without a Git commit.

**When to pick Sealed Secrets:** No cloud provider or Vault. Air-gapped environment. Team prefers all cluster state — including encrypted secrets — reviewable in Git.

## External Secrets Operator

### How it works

ESO reads a secret from a provider backend and writes a Kubernetes `Secret`. The sync is continuous — provider changes appear in the cluster within `refreshInterval`. ESO does not store secret values in Git.

Two resources define the integration:

- **`SecretStore`** (namespace-scoped) or **`ClusterSecretStore`** (cluster-wide) — holds provider credentials and connection details.
- **`ExternalSecret`** — maps a specific key in the provider to a Kubernetes `Secret`.

### ExternalSecret — provider-agnostic structure

The `ExternalSecret` structure is the same regardless of provider:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: app-team
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: my-secret-store   # name of the SecretStore in this namespace
    kind: SecretStore
  target:
    name: database-credentials    # name of the resulting Kubernetes Secret
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD      # key in the Kubernetes Secret
      remoteRef:
        key: prod/app-team/db     # path or name in the provider
        property: password        # JSON key within the secret value (if applicable)
```

### SecretStore — provider examples

Pick the block that matches your infrastructure. Only the `spec.provider` section changes.

#### AWS Secrets Manager (IRSA)

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
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa   # ServiceAccount with IRSA annotation
```

Required IAM permission (least privilege):

```json
{
  "Effect": "Allow",
  "Action": "secretsmanager:GetSecretValue",
  "Resource": "arn:aws:secretsmanager:<region>:<account-id>:secret:prod/app-team/*"
}
```

Never use `Resource: "*"`.

#### Azure Key Vault (Workload Identity)

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
        name: external-secrets-sa   # ServiceAccount with azure.workload.identity/client-id annotation
```

The managed identity needs the `Key Vault Secrets User` role on the Key Vault.

#### HashiCorp Vault (JWT / Kubernetes auth)

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

#### Static credentials (fallback — avoid in production)

Use only when workload identity is not available. Store the provider credential in a Kubernetes `Secret` and reference it from the `SecretStore`.

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
      region: us-east-1
      auth:
        secretRef:
          accessKeyIDSecretRef:
            name: aws-static-creds
            key: access-key-id
          secretAccessKeySecretRef:
            name: aws-static-creds
            key: secret-access-key
```

Rotate static credentials on a defined schedule and restrict their scope to the minimum required path.

### Troubleshooting ESO

```bash
# Check sync status and last sync time
kubectl get externalsecret -n app-team database-credentials

# Get full status including error message
kubectl describe externalsecret -n app-team database-credentials

# Check operator logs for this specific secret
kubectl logs -n external-secrets deploy/external-secrets \
  | grep -i "database-credentials"

# Check SecretStore health
kubectl get secretstore -n app-team my-secret-store
kubectl describe secretstore -n app-team my-secret-store
```

**Common failures:**

| Symptom | Cause | Fix |
|---|---|---|
| `SecretSyncError: unauthorized` / `AccessDenied` | Identity or credential missing the required permission | Check the provider's access policy; verify the identity annotation on the ServiceAccount |
| `SecretSyncError: not found` | Secret path wrong or deleted in provider | Verify `remoteRef.key` matches the exact name or path in the backend |
| Secret exists but data is stale | `refreshInterval` too long | Reduce interval or force sync: `kubectl annotate externalsecret database-credentials force-sync=$(date +%s) -n app-team` |
| `SecretStore` shows `NotReady` | Provider unreachable or authentication misconfigured | Check network connectivity to the provider endpoint; re-validate identity setup |
| Secret created but pod can't read it | Pod references wrong Secret name or key | Verify `envFrom`/`secretKeyRef` in the pod spec matches `target.name` and `secretKey` in the `ExternalSecret` |

---

## Sealed Secrets

### How it works

`kubeseal` encrypts a Kubernetes `Secret` with the cluster's public key. The encrypted `SealedSecret` is committed to Git. The in-cluster controller decrypts it back to a `Secret` at reconciliation time. The plain `Secret` is never committed.

Sealed Secrets works with any GitOps tool (Flux, Argo CD) and any infrastructure provider.

### Seal a secret

```bash
# Fetch the cluster public key — run once per cluster or when the key rotates
kubeseal --fetch-cert \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  > pub-cert.pem

# Create a plain Secret and immediately seal it — never commit the plain Secret
kubectl create secret generic database-credentials \
  --namespace=app-team \
  --from-literal=DB_PASSWORD=supersecret \
  --dry-run=client -o yaml \
  | kubeseal --cert pub-cert.pem --format yaml \
  > database-credentials-sealed.yaml

# Commit the sealed file — this is safe to store in Git
git add database-credentials-sealed.yaml
git commit -m "chore: seal database-credentials for app-team"
```

### Rotation

```bash
# Re-seal with the new value and overwrite the existing file
kubectl create secret generic database-credentials \
  --namespace=app-team \
  --from-literal=DB_PASSWORD=newvalue \
  --dry-run=client -o yaml \
  | kubeseal --cert pub-cert.pem --format yaml \
  > database-credentials-sealed.yaml

git add database-credentials-sealed.yaml
git commit -m "chore: rotate database-credentials"
```

Your GitOps tool applies the updated `SealedSecret`; the controller decrypts and overwrites the `Secret`. Pods consuming it as a mounted volume pick up the new value automatically via kubelet refresh. Pods consuming it as an env var require a rollout restart.

### Troubleshooting Sealed Secrets

```bash
# Confirm the controller is running
kubectl get pods -n sealed-secrets

# Inspect SealedSecret status and events
kubectl describe sealedsecret -n app-team database-credentials

# Check controller logs for decryption errors
kubectl logs -n sealed-secrets deploy/sealed-secrets-controller | tail -50
```

**Common failures:**

| Symptom | Cause | Fix |
|---|---|---|
| `no key could decrypt secret` | Secret sealed with an old key after controller key rotation | Re-seal with the current cluster public key using `--fetch-cert` |
| Secret not created after GitOps sync | `metadata.namespace` in the sealed file does not match the target namespace | Ensure namespace in the sealed YAML matches where it will be applied |
| `cannot fetch key: secret not found` | Controller lost its own key Secret (e.g. cluster was recreated) | Restore the master key from backup before applying any sealed secrets |

### Key backup — critical

The controller's master key decrypts all sealed secrets for the cluster. Export it before any cluster migration or destruction:

```bash
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-master-key-backup.yaml
```

Store this backup in a secure location outside the cluster (a password manager, a vault, an encrypted object store). Without it, sealed secrets cannot be decrypted after cluster recreation.

**Restore:**

```bash
kubectl apply -f sealed-secrets-master-key-backup.yaml
kubectl rollout restart deploy/sealed-secrets-controller -n sealed-secrets
```

---

## Operational rules

- Never commit plain `Secret` manifests to Git. Use ESO, Sealed Secrets, or Vault.
- Automate rotation where possible. Manual rotation is error-prone and often skipped.
- Scope `SecretStore` to the owning namespace. Use `ClusterSecretStore` only for secrets that are genuinely platform-wide.
- Prefer workload identity (IRSA, Azure Workload Identity, GKE Workload Identity, Vault Kubernetes auth) over static credentials. Static credentials must be rotated on a defined schedule.
- Scope provider permissions to the minimum required paths or secret names — never grant access to all secrets in a provider.
- For Sealed Secrets: back up the controller master key before cluster destruction. Test the restore procedure before you need it.
- Audit which workloads consume which secrets. Use `ExternalSecret` status and Kubernetes events to track sync health.
- Do not use `kubernetes.io/service-account-token` secrets for application auth to the Kubernetes API. Use projected tokens (automatic since Kubernetes 1.24).
