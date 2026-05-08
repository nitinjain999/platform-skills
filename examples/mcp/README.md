Status: Stable

# MCP Examples

Production-ready MCP server implementations for common platform use cases.

## Examples

| Example | Transport | Language | Description |
|---------|-----------|----------|-------------|
| [docs-server/](docs-server/) | stdio | TypeScript | Search internal documentation |
| [k8s-server/](k8s-server/) | stdio | Python | Query Kubernetes cluster state |

## Usage

```bash
# TypeScript example
cd docs-server
npm install && npm run build
npx @modelcontextprotocol/inspector node dist/index.js

# Python example
cd k8s-server
pip install -r requirements.txt
npx @modelcontextprotocol/inspector python server.py
```

## See Also

- [references/mcp.md](../../references/mcp.md) — protocol guide, SDK patterns, security
- `/platform-skills:mcp` — scaffold, review, or debug an MCP server
