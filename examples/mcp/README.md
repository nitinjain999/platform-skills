Status: Stable

# MCP Examples

Production-ready MCP server implementations for common platform use cases.

## Examples

| Example | Transport | Language | Description |
|---------|-----------|----------|-------------|
| [docs-server/](docs-server/) | stdio | TypeScript | Search internal documentation |

## Usage

```bash
# TypeScript example
cd docs-server
npm install && npm run build
npx @modelcontextprotocol/inspector node dist/index.js
```

## See Also

- [references/mcp.md](../../references/mcp.md) — protocol guide, SDK patterns, security
- `/platform-skills:mcp` — scaffold, review, or debug an MCP server
