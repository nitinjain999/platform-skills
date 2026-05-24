# Task: Diagnose a stuck HelmRelease

A platform engineer reports that a HelmRelease has been in a `Reconciling` state for 20 minutes and the application pods have not been updated.

The following output was collected:

```
$ flux get helmrelease cert-manager -n cert-manager
NAME         REVISION  SUSPENDED  READY  MESSAGE
cert-manager           False      False  Helm install failed: rendered manifests contain a resource that already exists...
```

```
$ kubectl describe helmrelease cert-manager -n cert-manager | grep -A 10 "Status:"
Status:
  Conditions:
    Last Transition Time:  2026-05-24T10:00:00Z
    Message:               Helm install failed: rendered manifests contain a resource that already exists. Unable to continue with install: ClusterRole "cert-manager-cainjector" in namespace "" exists and cannot be imported into the current release: invalid ownership metadata
    Reason:                InstallFailed
    Status:                False
    Type:                  Ready
```

1. Classify which Flux layer this failure belongs to: source | artifact | reconciliation | chart rendering | runtime.
2. List the evidence you would collect next (exact commands).
3. State the root cause.
4. Provide the fix with exact commands.
5. State the blast radius and rollback plan.
6. Provide the validation steps to confirm the fix worked.
