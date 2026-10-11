---
description: "Trigger check: an admission-policy request must load the kyverno skill, not opa or kubernetes."
tags: [kyverno, trigger]
max_turns: 12
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
---

Write an admission policy that blocks pods running as root in the payments namespace. Roll it out in audit mode first so we can see violations before enforcing.
