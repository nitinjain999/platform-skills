---
name: mcp
description: MCP server and client development — scaffold, implement tools/resources/prompts, validate schemas, debug protocol compliance, and deploy with auth and rate limiting.
argument-hint: "[create|review|debug] [typescript|python] [description]"
---

Build, review, or debug an MCP (Model Context Protocol) server or client.

## Mode: create

Scaffold a production-ready MCP server.

Steps:
1. Ask for: language (TypeScript or Python), transport (stdio / HTTP+SSE), list of tools and resources needed
2. Generate project scaffold with correct SDK setup
3. Implement tool handlers with Zod (TypeScript) or Pydantic (Python) schema validation
4. Add resource providers and prompt templates as needed
5. Configure transport layer
6. Add error handling — return `isError: true` content, never throw unhandled exceptions to clients
7. Add authentication and rate limiting for HTTP transports
8. Provide MCP Inspector test commands and expected responses
9. Add deployment checklist (env vars, secrets, logging)

Reference: `references/mcp.md` → Protocol Fundamentals, TypeScript SDK, Python SDK

## Mode: review

Review an existing MCP server or client implementation.

Evaluate in priority order:
1. **Protocol compliance** — JSON-RPC 2.0 correctness, proper capability negotiation, well-formed content arrays
2. **Schema validation** — all tool inputs validated with Zod/Pydantic; no `z.any()` or empty schemas
3. **Security** — no credentials in tool responses or resource content; auth on HTTP transports; rate limiting present
4. **Error handling** — errors return `isError: true` with a message, not unhandled exceptions
5. **Transport** — correct transport for the use case; no blocking sync code in async transports

Output: Critical (must fix) / Improvement (should fix) / Note (informational)

Reference: `references/mcp.md` → Security, Error Handling, Testing and Debugging

## Mode: debug

Diagnose MCP protocol or integration failures.

Classify the failure:
- **Transport** — connection refused, EOF, serialisation error
- **Protocol** — malformed JSON-RPC, missing `id`, wrong method names
- **Schema** — Zod/Pydantic validation rejection, unexpected input types
- **Handler** — unhandled exception, timeout, wrong return shape
- **Integration** — tool not appearing in host, capabilities mismatch

Evidence to collect:
```bash
# Run MCP Inspector to verify protocol compliance
npx @modelcontextprotocol/inspector node dist/index.js

# Smoke-test via stdio
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | node dist/index.js

# Check for schema errors
node -e "require('./dist/index.js')" 2>&1
```

Provide: observed symptom → likely root cause → evidence command → fix → validation step
