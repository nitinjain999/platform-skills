---
# Prefers the narrowest SCC over anyuid/privileged.
type: regex
weight: 1
target: last_message
pattern: 'restricted-v2|nonroot|least privilege|minimum'
flags: i
---
