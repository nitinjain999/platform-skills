---
# correct_yaml (half of 2): CPU and memory requests, in either order.
type: regex
weight: 1
target: last_message
pattern: 'requests:\s*\n\s*(cpu:[^\n]*\n\s*memory:|memory:[^\n]*\n\s*cpu:)'
---
