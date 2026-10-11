---
# validation (1).
type: regex
weight: 1
target: last_message
pattern: 'flux get (helmrelease|hr)|kubectl get pods -n cert-manager'
flags: i
---
