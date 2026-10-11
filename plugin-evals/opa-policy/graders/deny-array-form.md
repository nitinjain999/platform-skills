---
# deny_rule_correct (half): also catches the array form.
type: regex
weight: 1
target: last_message
pattern: 'is_array|\[_\]|some \w+ in|\[\s*"\*"\s*\]'
---
