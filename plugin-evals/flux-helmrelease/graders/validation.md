---
# validation (1): both checks, in either order: flux get helmrelease (Ready)
# and a cert-manager workload check (kubectl get pods or deploy, rollout
# status, or wait, with -n/--namespace cert-manager on the same line).
type: regex
weight: 1
target: last_message
pattern: 'flux get (helmrelease|hr)[\s\S]*kubectl[^\n]*((-n|--namespace)[ =]cert-manager[^\n]*(get (po|pods?|deploy|deployments?)\b|rollout status|wait\b)|(get (po|pods?|deploy|deployments?)\b|rollout status|wait\b)[^\n]*(-n|--namespace)[ =]cert-manager)|kubectl[^\n]*((-n|--namespace)[ =]cert-manager[^\n]*(get (po|pods?|deploy|deployments?)\b|rollout status|wait\b)|(get (po|pods?|deploy|deployments?)\b|rollout status|wait\b)[^\n]*(-n|--namespace)[ =]cert-manager)[\s\S]*flux get (helmrelease|hr)'
flags: i
---
