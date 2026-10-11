---
# fix (2): helm uninstall followed by flux reconcile helmrelease, or adoption
# via Helm ownership metadata. Uninstall alone is half the fix: without the
# reconcile nothing reinstalls the chart.
type: regex
weight: 2
target: last_message
pattern: 'helm uninstall[\s\S]*flux reconcile (helmrelease|hr)|meta\.helm\.sh/release-(name|namespace)|app\.kubernetes\.io/managed-by'
flags: i
---
