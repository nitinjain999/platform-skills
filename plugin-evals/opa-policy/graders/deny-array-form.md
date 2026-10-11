---
# deny_rule_correct (half): also catches the array form. Iteration only counts
# when it is over the Action value; a generic "some x in" or "[_]" also appears
# in a string-only policy that iterates statements or resource_changes.
type: regex
weight: 1
target: last_message
pattern: 'is_array|\[\s*"\*"\s*\]|some [\w, ]+ in [\w.\[\]"]*(\.Action|\["Action"\])|(\.Action|\["Action"\])\[_\]|"\*" in [\w.\[\]"]*(\.Action|\["Action"\])'
---
