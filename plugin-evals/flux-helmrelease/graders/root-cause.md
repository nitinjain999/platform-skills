---
# root_cause (2): pre-existing ClusterRole not owned by this release.
type: regex
weight: 2
target: last_message
pattern: 'ClusterRole[\s\S]{0,300}(owner|ownership|meta\.helm\.sh)|(owner|ownership)[\s\S]{0,300}ClusterRole'
flags: i
---
