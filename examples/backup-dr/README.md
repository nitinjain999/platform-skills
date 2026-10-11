# Backup and DR Example

Status: Beta

Velero on EKS, managed by Flux: nightly backups of every namespace with EBS snapshots, IRSA instead of access keys, and a restore drill that proves a backup actually restores and measures how long it takes.

| File | What it is |
|---|---|
| `velero/helmrelease.yaml` | Velero chart 12.2.1 (Velero 1.18.2) with velero-plugin-for-aws 1.14.3, an S3 backup location and EBS snapshot location in `eu-north-1`, IRSA, and a `nightly` schedule kept 30 days |
| `iam-policy.json` | The plugin's actions, scoped: S3 to the backup bucket, `Describe*` to one region, and snapshot create, restore and delete to snapshots tagged `velero.io/backup` (Velero 1.18 tags every snapshot it takes), so the role cannot delete snapshots it did not create |
| `bucket/main.tf` | The backup bucket, protected from deletion: versioning, public access blocked, encryption, noncurrent versions kept 30 days, `prevent_destroy`, and a bucket policy that denies version deletion, versioning suspension, lifecycle and policy changes and bucket deletion to everyone but `admin_role_arns`. Velero still holds `s3:DeleteObject` to expire backups, but on this bucket that only adds a delete marker |
| `restore-drill.sh` | Restores one namespace from the latest completed scheduled backup into `<ns>-drill`, waits for every pod to be Ready, reports the time taken, and deletes the drill namespace on every exit, success or failure |

Create the bucket before installing Velero, with a role listed in `admin_role_arns` (the policy denies the next apply to anyone else):

```bash
cd examples/backup-dr/bucket
cp terraform.tfvars.example terraform.tfvars   # set your break-glass and Terraform roles
terraform init && terraform plan -out=bucket.plan && terraform apply bucket.plan
```

To recover a deleted backup object, the break-glass role removes its delete marker (`aws s3api list-object-versions`, then `aws s3api delete-object --version-id <marker id>`). The bucket cannot be destroyed by `terraform destroy`; remove `prevent_destroy` deliberately if you ever retire it.

A backup you have never restored is a hope, not a recovery plan. Run the drill on a schedule and after any change to storage, CSI drivers or Velero itself:

```bash
bash examples/backup-dr/restore-drill.sh --namespace my-app
```

The drill excludes HTTPRoutes, Ingresses and Services from the restore, so the copy never takes a production hostname. It then recreates each Service as an internal ClusterIP (or headless) copy with the same selector and ports, so in-namespace DNS still works. A Service restored as it was could provision a new public load balancer (type `LoadBalancer`) or open a port on every node (`NodePort`). The script needs `jq` for that step. In the basic-monorepo layout the HTTPS listener only accepts routes from `my-app` anyway, so a stray route from `my-app-drill` would be rejected.

Blocking inbound traffic is not enough on its own. The restored Deployments, Jobs and consumers start with production Secrets and config, and they could write to the production database, call external APIs or consume live queues before the readiness check. So the script creates `<ns>-drill` before the restore, copying the source namespace's labels, and applies a default-deny `NetworkPolicy` (`restore-drill-isolation`) that allows only pod-to-pod traffic inside the drill namespace and DNS ports to the cluster DNS pods. The DNS rule selects one namespace by name and one pod label, so a pod elsewhere listening on port 53 or 5353 is not an egress path. The defaults match CoreDNS on EKS, GKE and AKS (`kube-system`, `k8s-app=kube-dns`); the script stops before creating anything if no pod matches. Set them for other resolvers, and add NodeLocal DNSCache's address explicitly (DNS ports only):

```bash
# OpenShift DNS
bash examples/backup-dr/restore-drill.sh --namespace my-app \
  --dns-namespace openshift-dns --dns-pod-label dns.operator.openshift.io/daemonset-dns=default
# NodeLocal DNSCache
bash examples/backup-dr/restore-drill.sh --namespace my-app --node-local-dns 169.254.20.10
```

The backup's own NetworkPolicies are not restored, because policies are additive and one that allows egress would undo the isolation. If you provide test instances of a workload's dependencies, allow them explicitly:

```bash
bash examples/backup-dr/restore-drill.sh --namespace my-app --allow-egress 10.20.30.0/24
```

Pods that cannot reach a dependency they need at startup will not become Ready. That is a finding about the drill setup, not about the backup. Egress isolation needs a CNI that enforces NetworkPolicy egress (Calico, Cilium, the VPC CNI with network policy enabled, OVN-Kubernetes). If your CNI does not, run the drill in a separate cluster.

The drill namespace holds production Secrets, so the script deletes it on every exit: after a pass, a failed restore, a readiness timeout or Ctrl-C. To inspect a failed drill, pass `--keep` and delete `<ns>-drill` yourself when done.

Pair it with `/platform-skills:chaos`: run a GameDay that deletes the namespace, then run this drill as the recovery step and compare the measured time with your recovery-time objective.

Validate the HelmRelease values against the real chart:

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
yq '.spec.values' examples/backup-dr/velero/helmrelease.yaml > /tmp/velero-values.yaml
helm template velero vmware-tanzu/velero --version 12.2.1 -n velero -f /tmp/velero-values.yaml | kubeconform -strict -summary -skip CustomResourceDefinition \
  -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/63669a570e231d4f1f8396d229a1de512bcf0a34/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```

The full guide is `/platform-skills:backup-dr` and `references/backup-dr.md`.
