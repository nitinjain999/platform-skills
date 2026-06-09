#!/usr/bin/env bash
# render.sh — substitute __TOKEN__ placeholders in a template file.
# Usage: bash render.sh <template> KEY1=value1 KEY2=value2 > output
# Token format: __SNAKE_CASE__ — valid in YAML, JSON, and Markdown.
# Values may contain slashes and newlines; bash parameter expansion handles both
# without the escaping hazards of sed.
set -euo pipefail
template="$1"; shift
content="$(cat "$template")"
for pair in "$@"; do
  key="${pair%%=*}"
  value="${pair#*=}"
  content="${content//__"${key}"__/${value}}"
done
printf '%s\n' "$content"
