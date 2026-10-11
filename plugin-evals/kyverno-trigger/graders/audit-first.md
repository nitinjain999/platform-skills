---
# Starts in Audit before Deny.
type: regex
weight: 1
target: last_message
pattern: 'Audit'
flags: i
---
