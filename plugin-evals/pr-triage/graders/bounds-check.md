---
# scenario_2_correct_fix (2): a 0-100 bounds check on discount.percent.
type: regex
weight: 2
target: last_message
pattern: '0\s*<=?\s*\w*\.?percent|percent\s*(<|>|<=|>=)|>\s*100|<\s*0\b'
flags: i
---
