---
description: "Trigger check: a Secret rotation question must load the secrets skill, not kubernetes."
tags: [secrets, trigger]
max_turns: 12
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
---

Our payments service reads its database password from a Kubernetes Secret that External Secrets Operator syncs from AWS Secrets Manager. We need to rotate that password without downtime. What is the runbook, and how do we confirm the pods picked up the new value?
