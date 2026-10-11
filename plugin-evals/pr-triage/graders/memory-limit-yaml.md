---
# correct_yaml (half of 2): a memory limit in the corrected YAML. A CPU limit
# before it is tolerated; the requests half is requests-yaml.md.
type: regex
weight: 1
target: last_message
pattern: 'limits:\s*\n(\s*cpu:[^\n]*\n)?\s*memory:'
---
