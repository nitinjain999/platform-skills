---
# scenario_2_correct_fix (2): a 0-100 bounds check on discount.percent. Both
# bounds are required, in either order: a lower-bound comparison against 0 and
# an upper-bound comparison against 100. A chained `0 <= discount.percent <= 100`
# satisfies both; a one-sided `discount.percent < 0` does not.
type: regex
weight: 2
target: last_message
pattern: '^(?=[\s\S]*(percent\s*[<>]=?\s*0\b|\b0\s*[<>]=?\s*[\w.]*percent))(?=[\s\S]*(percent\s*[<>]=?\s*100\b|\b100\s*[<>]=?\s*[\w.]*percent))'
flags: i
---
