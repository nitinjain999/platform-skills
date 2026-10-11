---
description: "Trigger check: an SCC admission error must load the openshift skill, not kubernetes."
tags: [openshift, trigger]
max_turns: 12
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
---

A Deployment on our cluster is stuck with this event: "pods "api-7d9" is forbidden: unable to validate against any security context constraint". What is wrong and what is the minimum fix?
