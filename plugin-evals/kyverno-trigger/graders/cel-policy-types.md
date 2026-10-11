---
# Uses the CEL-based policy types this plugin standardises on.
type: regex
weight: 1
target: last_message
pattern: 'policies\.kyverno\.io/v1|ValidatingPolicy'
flags: i
---
