---
# States how to roll back to the previous secret version.
type: regex
weight: 1
target: last_message
pattern: 'roll ?back|previous version|AWSPREVIOUS'
flags: i
---
