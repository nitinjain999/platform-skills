---
# Diagnoses the SecurityContextConstraints admission.
type: regex
weight: 1
target: last_message
pattern: 'security context constraint|SCC'
flags: i
---
