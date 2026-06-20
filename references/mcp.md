---
title: MCP
custom_edit_url: null
---

# MCP (Model Context Protocol) Reference

## AWS Multi-Account Profiles

For managing AWS MCP servers across multiple accounts (SSO, Granted, assumed-role chains, credential_process, team sharing):

→ See `references/aws-mcp-profiles.md`

Commands: `/platform-skills:aws-profile` · `/platform-skills:mcp configure-aws`

---

## Protocol Fundamentals

MCP is a JSON-RPC 2.0 protocol that connects AI hosts (Claude Desktop, Claude Code) with servers exposing tools, resources, and prompts.

### Message Lifecycle

```
Host (client)                    MCP Server
     │                                │
     │──── initialize ───────────────>│  negotiate capabilities
     │<─── initialized ───────────────│
     │                                │
     │──── tools/list ───────────────>│  discover tools
     │<─── { tools: [...] } ──────────│
     │                                │
     │──── tools/call ───────────────>│  invoke tool
     │<─── { content: [...] } ────────│
     │                                │
     │──── resources/list ───────────>│  discover resources
     │<─── { resources: [...] } ──────│
     │                                │
     │──── resources/read ───────────>│  read resource
     │<─── { contents: [...] } ───────│
```

### Transport Options

| Transport | Use Case | Notes |
|-----------|----------|-------|
| `stdio` | Local CLI tools, Claude Desktop | Process-level isolation, simplest |
| `SSE` (HTTP) | Remote servers, web services | Requires auth layer |
| `HTTP` (Streamable) | Production APIs | Preferred for new remote servers |

---

## TypeScript SDK

### Scaffold

```bash
npx @modelcontextprotocol/create-server my-server
cd my-server && npm install
```

### Tool Registration with Zod

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({ name: "my-server", version: "1.0.0" });

server.tool(
  "search_docs",
  "Search internal documentation by keyword",
  {
    query: z.string().min(1).describe("Search query"),
    limit: z.number().int().min(1).max(50).default(10),
  },
  async ({ query, limit }) => {
    const results = await searchIndex(query, limit);
    return {
      content: [{ type: "text", text: JSON.stringify(results) }],
    };
  }
);
```

### Resource Provider

```typescript
server.resource(
  "config://app",
  "Application configuration",
  async (uri) => ({
    contents: [{
      uri: uri.href,
      text: JSON.stringify(getConfig()),
      mimeType: "application/json",
    }],
  })
);

// Parameterised resource template
server.resource(
  "user://{userId}/profile",
  "User profile by ID",
  async (uri, { userId }) => ({
    contents: [{
      uri: uri.href,
      text: JSON.stringify(await getUserProfile(userId)),
      mimeType: "application/json",
    }],
  })
);
```

### Prompt Template

```typescript
server.prompt(
  "summarise_pr",
  "Summarise a pull request for a code review",
  {
    pr_url: z.string().url(),
    style: z.enum(["brief", "detailed"]).default("brief"),
  },
  async ({ pr_url, style }) => ({
    messages: [{
      role: "user",
      content: {
        type: "text",
        text: `Summarise this PR in ${style} style: ${pr_url}`,
      },
    }],
  })
);
```

### stdio Transport

```typescript
const transport = new StdioServerTransport();
await server.connect(transport);
```

### HTTP/SSE Transport (remote)

```typescript
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import express from "express";

const app = express();
const transports = new Map<string, SSEServerTransport>();

app.get("/sse", async (req, res) => {
  const transport = new SSEServerTransport("/message", res);
  transports.set(transport.sessionId, transport);
  await server.connect(transport);
});

app.post("/message", async (req, res) => {
  const sessionId = req.query.sessionId as string;
  const transport = transports.get(sessionId);
  await transport?.handlePostMessage(req, res);
});

app.listen(3000);
```

---

## Python SDK (FastMCP)

### Scaffold

```bash
pip install mcp
```

### Tool with Pydantic Validation

```python
import json

from mcp.server.fastmcp import FastMCP
from pydantic import BaseModel, Field

mcp = FastMCP("my-server")


class SearchInput(BaseModel):
    query: str = Field(description="Search query string")
    limit: int = Field(default=10, ge=1, le=50, description="Maximum results")


@mcp.tool()
async def search_docs(input: SearchInput) -> str:
    """Search internal documentation by keyword."""
    results = await search_index(input.query, input.limit)
    return json.dumps(results)
```

### Resource

```python
@mcp.resource("config://app")
async def app_config() -> str:
    """Expose application configuration."""
    return json.dumps(get_config())

@mcp.resource("user://{user_id}/profile")
async def user_profile(user_id: str) -> str:
    """User profile by ID."""
    return json.dumps(await get_user_profile(user_id))
```

### Run

```python
if __name__ == "__main__":
    mcp.run()        # stdio (default)
    # mcp.run(transport="sse")   # SSE
```

---

## Schema Design

### Zod Best Practices (TypeScript)

```typescript
// Good — narrow, descriptive schemas
const InputSchema = z.object({
  environment: z.enum(["dev", "staging", "prod"]),
  timeout_ms: z.number().int().min(100).max(30_000).default(5_000),
  tags: z.array(z.string().max(64)).max(20).optional(),
});

// Bad — overly permissive
const BadSchema = z.object({
  data: z.any(),        // ❌ no validation
  config: z.object({}), // ❌ empty object
});
```

### Pydantic Best Practices (Python)

```python
from pydantic import BaseModel, Field, validator

class SearchInput(BaseModel):
    query: str = Field(..., min_length=1, max_length=500)
    limit: int = Field(10, ge=1, le=50)
    filters: list[str] = Field(default_factory=list)

    @validator("filters")
    def no_empty_filters(cls, v):
        return [f.strip() for f in v if f.strip()]
```

---

## Error Handling

```typescript
// TypeScript — return structured errors, never throw to client
server.tool("risky_op", "...", { id: z.string() }, async ({ id }) => {
  try {
    const result = await performOperation(id);
    return { content: [{ type: "text", text: JSON.stringify(result) }] };
  } catch (err) {
    return {
      content: [{ type: "text", text: `Error: ${err.message}` }],
      isError: true,
    };
  }
});
```

```python
# Python — return error content, never let exceptions propagate unhandled
@mcp.tool()
async def risky_op(id: str) -> str:
    try:
        return json.dumps(await perform_operation(id))
    except OperationError as e:
        return f"Error: {e}"
```

---

## Testing and Debugging

### MCP Inspector

```bash
# Launch interactive protocol debugger
npx @modelcontextprotocol/inspector node dist/index.js
```

Verify:
- Tools appear in the tool list
- Schemas reject invalid inputs with clear messages
- Successful calls return well-formed `content` arrays
- Error calls set `isError: true`

### Protocol Smoke Test (curl)

```bash
# List tools via stdio
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | node dist/index.js
```

---

## Security

### Authentication (HTTP transport)

```typescript
app.use((req, res, next) => {
  const token = req.headers.authorization?.split(" ")[1];
  if (!verifyToken(token)) return res.status(401).json({ error: "Unauthorized" });
  next();
});
```

### Rate Limiting

```typescript
import rateLimit from "express-rate-limit";

app.use("/message", rateLimit({
  windowMs: 60 * 1000,
  max: 100,
  message: { error: "Too many requests" },
}));
```

### Secrets — Never in Tool Responses

```typescript
// ❌ Never expose credentials in tool output
return { content: [{ type: "text", text: JSON.stringify({ apiKey: process.env.SECRET }) }] };

// ✅ Return only what the client needs
return { content: [{ type: "text", text: JSON.stringify({ status: "authenticated" }) }] };
```

---

## Deployment Checklist

- [ ] All tool inputs validated with Zod or Pydantic schemas
- [ ] Error paths return `isError: true`, not unhandled exceptions
- [ ] No credentials or secrets in resource content or tool responses
- [ ] Authentication on HTTP/SSE transports
- [ ] Rate limiting configured
- [ ] Protocol compliance verified with MCP Inspector
- [ ] Environment variables used for all secrets (`process.env` / `os.environ`)
- [ ] Logging of tool calls (without sensitive param values)
