---
# deny_rule_correct (half): also catches the array form. Every alternative is
# tied to the statement's Action expression: a bare `["*"]` also appears in the
# required failing test fixture, and a generic "some x in", "[_]" or is_array
# also appears in a string-only policy that iterates statements or
# resource_changes.
type: regex
weight: 1
target: last_message
pattern: 'is_array\(\s*[\w.\[\]"]*(\.Action|\["Action"\])\s*\)|some [\w, ]+ in [\w.\[\]"]*(\.Action|\["Action"\])|(\.Action|\["Action"\])\[_\]|"\*" in [\w.\[\]"]*(\.Action|\["Action"\])|(\.Action|\["Action"\])\s*==\s*\[\s*"\*"\s*\]'
---
