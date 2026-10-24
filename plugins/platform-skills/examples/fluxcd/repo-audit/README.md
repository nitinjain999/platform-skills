# Bundled Flux repository audit helpers

These scripts are vendored from [fluxcd/agent-skills v0.2.0](https://github.com/fluxcd/agent-skills/tree/9b05787530a3e200a9ac031fc8a477566e0b7adc/skills/gitops-repo-audit/scripts),
commit `9b05787530a3e200a9ac031fc8a477566e0b7adc`, under Apache-2.0.
Copyright 2026 The Flux authors. The license ships beside this file.

`discover.sh` is unchanged. Local changes to the other helpers:

- `validate.sh` retains kustomize's default file-loading restriction, recognizes
  `kustomization.yaml`, `kustomization.yml` and `Kustomization`, and resolves
  relative exclusions against the audit root.
- `check-deprecated.sh` preserves a failing `flux migrate` exit status even when
  its output contains no deprecated-version message, and matches large reports
  without a pipe that can fail early with SIGPIPE.

Install the tools separately before an audit:

- `flux-schema >= 0.10.0`: a standalone binary from the
  [official releases](https://github.com/fluxcd/flux-schema/releases), or an
  already installed Flux schema plugin. Discovery checks the minimum version.
- `kustomize` or `kubectl` for rendering overlays.
- `flux >= 2.9.0` for deprecated-API checks.
- `helm >= 4.0` only if explicitly enabling the validator's `--helm-charts` option.

The helpers run the installed tools. They do not clone or download executable
code. Schema validation may retrieve schema data from the ecosystem catalog,
and kustomize may resolve a repository's remote resources.

The validator leaves kustomize's
[`LoadRestrictionsRootOnly` default](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_kustomize/)
in place.
Generator files and patches outside a kustomization's root fail the build;
the helper does not expose an unrestricted-loading option. This restriction is
not a filesystem sandbox: kustomize can still load other kustomization bases.
Use an isolated environment without local credentials for untrusted repositories.

Set `audit_dir` to the absolute path of this directory in the loaded
installation. Repository clones and Claude plugins put it under
`examples/fluxcd/repo-audit` at their root. A rendered portable skill carries
the same path under its own skill directory.

```bash
audit_dir='<absolute path to bundled examples/fluxcd/repo-audit>'
bash "$audit_dir/scripts/discover.sh" -d .
bash "$audit_dir/scripts/validate.sh" -d .
bash "$audit_dir/scripts/check-deprecated.sh" -d .
```

The validator uses `.fluxschema.yml` when present, otherwise the ecosystem
catalog with SOPS metadata stripped and missing schemas skipped. Review its
skipped-resource count as a coverage gap. Arguments after `--` override
validation settings; see `bash "$audit_dir/scripts/validate.sh" --help`.
For `validate.sh -d <root> -e <directory>`, relative exclusions are resolved
under `<root>`; absolute exclusions are also accepted.

Both standalone and overlay validation failures make the validator fail.
The deprecated-API check fails for deprecated versions and for CLI errors.
The default commands audit files; they do not apply resources to a cluster.
