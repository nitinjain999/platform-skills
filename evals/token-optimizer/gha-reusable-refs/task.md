# Task: Resolve reusable workflow and action references

Scan the workflow files in `workflows/` and find all references to reusable workflows and actions.

For each reference, report:
- The action or workflow name
- The repository and path
- The version (tag, SHA, or branch)
- Whether it's pinned to a SHA or uses a mutable reference

Flag any mutable references (branches) as risky. Report complete, partial, or blocked.
