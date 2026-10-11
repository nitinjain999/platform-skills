---
# evidence_commands (2): names concrete evidence commands.
type: regex
weight: 2
target: last_message
pattern: 'flux logs|kubectl get clusterrole|helm list|kubectl get events'
flags: i
---
