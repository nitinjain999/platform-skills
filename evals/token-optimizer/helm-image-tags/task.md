# Task: Find which environments pin which image tags

The `web-service/` directory contains Helm templates, and `apps/` contains environment-specific Kustomize overlays.

Find all container image references and report:
- The image name
- The tag or digest
- Which environment(s) use it
- Whether any environment uses `latest` or a mutable tag

State what was omitted or truncated. Report complete, partial, or blocked.
