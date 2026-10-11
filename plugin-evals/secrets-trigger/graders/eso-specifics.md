---
# Answer works with External Secrets Operator objects, not a generic Secret.
type: regex
weight: 1
target: last_message
pattern: 'ExternalSecret|refreshInterval|force-sync|reconcile'
flags: i
---
