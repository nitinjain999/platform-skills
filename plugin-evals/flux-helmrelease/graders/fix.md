---
# fix (2): uninstall and reconcile, or adopt via Helm ownership metadata.
type: regex
weight: 2
target: last_message
pattern: 'helm uninstall|meta\.helm\.sh/release-(name|namespace)|app\.kubernetes\.io/managed-by'
flags: i
---
