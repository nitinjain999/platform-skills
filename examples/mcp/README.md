Status: Stable

# MCP Examples

Production-ready MCP (Model Context Protocol) server implementations.

## Examples

| Example | Transport | Language | Description |
|---------|-----------|----------|-------------|
| [docs-server/](docs-server/) | stdio | TypeScript | Search and retrieve internal documentation |

## Quick Start

```bash
cd docs-server

# Install dependencies
npm install

# Build
npm run build

# Test with MCP Inspector (interactive browser UI)
npx @modelcontextprotocol/inspector node dist/index.js

# Or run directly via Claude Code
claude mcp add docs-server -- node /path/to/docs-server/dist/index.js
```

## What docs-server Provides

| Capability | Name | Description |
|-----------|------|-------------|
| Tool | `search_docs` | Search documents by keyword, returns matching titles and excerpts |
| Tool | `get_doc` | Retrieve full document content by ID |
| Resource | `docs://index` | List all available documents |

## Key Patterns

### Tool with Zod input validation

```typescript
server.tool(
  "search_docs",
  "Search internal documentation by keyword",
  { query: z.string().min(1).describe("Search query"), limit: z.number().int().min(1).max(50).default(10) },
  async ({ query, limit }) => {
    const results = documents.filter(d => d.body.toLowerCase().includes(query.toLowerCase())).slice(0, limit);
    return { content: [{ type: "text", text: JSON.stringify(results) }] };
  }
);
```

### Resource handler

```typescript
server.resource("docs://index", "List all documents", async (uri) => ({
  contents: [{ uri: uri.href, text: JSON.stringify(documents.map(d => ({ id: d.id, title: d.title }))) }]
}));
```

### stdio transport (for Claude Code integration)

```typescript
const transport = new StdioServerTransport();
await server.connect(transport);
```

### SSE transport (for remote/browser access)

```typescript
// Transport must be created inside the /sse handler
app.get("/sse", async (req, res) => {
  const transport = new SSEServerTransport("/message", res);
  transports.set(transport.sessionId, transport);
  await server.connect(transport);
});
app.post("/message", async (req, res) => {
  const transport = transports.get(req.query.sessionId as string);
  await transport?.handlePostMessage(req, res);
});
```

## Extending the Example

Replace the in-memory `documents` array with a real backend:

```typescript
// Elasticsearch
const results = await esClient.search({ index: "docs", query: { match: { body: query } } });

// Postgres full-text search
const results = await db.query("SELECT * FROM docs WHERE to_tsvector(body) @@ plainto_tsquery($1)", [query]);
```

## See Also

- [references/mcp.md](../../references/mcp.md) — protocol fundamentals, TypeScript/Python SDKs, schema design, transports, security, deployment
- `/platform-skills:mcp` — scaffold a new MCP server, review an existing one, or debug transport/protocol issues
