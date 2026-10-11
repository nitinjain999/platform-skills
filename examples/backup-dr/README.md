# Backup and DR Example

Status: Beta

Velero on EKS, managed by Flux: nightly backups of every namespace with EBS snapshots, IRSA instead of access keys, and a restore drill that proves a backup actually restores and measures how long it takes.

| File | What it is |
|---|---|
| `velero/helmrelease.yaml` | Velero chart 12.2.1 (Velero 1.18.2) with velero-plugin-for-aws 1.14.3, an S3 backup location and EBS snapshot location in `eu-north-1`, IRSA, and a `nightly` schedule kept 30 days |
| `iam-policy.json` | The plugin's documented permissions, with S3 scoped to the backup bucket and EC2 limited to one region |
| `restore-drill.sh` | Restores one namespace from the latest completed scheduled backup into `<ns>-drill`, waits for every pod to be Ready, reports the time taken, and deletes the drill namespace |

A backup you have never restored is a hope, not a recovery plan. Run the drill on a schedule and after any change to storage, CSI drivers or Velero itself:

```bash
bash examples/backup-dr/restore-drill.sh --namespace my-app
```

The drill excludes HTTPRoutes and Ingresses, so the restored copy never takes a production hostname. In the basic-monorepo layout the HTTPS listener only accepts routes from `my-app` anyway, so a stray route from `my-app-drill` would be rejected.

Pair it with `/platform-skills:chaos`: run a GameDay that deletes the namespace, then run this drill as the recovery step and compare the measured time with your recovery-time objective.

Validate the HelmRelease values against the real chart:

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
yq '.spec.values' examples/backup-dr/velero/helmrelease.yaml > /tmp/velero-values.yaml
helm template velero vmware-tanzu/velero --version 12.2.1 -n velero -f /tmp/velero-values.yaml | kubeconform -strict -summary -skip CustomResourceDefinition \
  -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/63669a570e231d4f1f8396d229a1de512bcf0a34/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```

The full guide is `/platform-skills:backup-dr` and `references/backup-dr.md`.
