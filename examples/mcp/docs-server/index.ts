import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({ name: "docs-server", version: "1.0.0" });

// In-memory document store — replace with real search backend
const documents: Array<{ id: string; title: string; body: string; tags: string[] }> = [
  { id: "1", title: "Getting Started", body: "Install the CLI with npm install -g @example/cli", tags: ["quickstart"] },
  { id: "2", title: "Authentication", body: "Use OIDC with your identity provider. Set OIDC_ISSUER env var.", tags: ["auth", "security"] },
  { id: "3", title: "Deployment", body: "Deploy with helm upgrade --install. See values.yaml for configuration.", tags: ["helm", "kubernetes"] },
];

server.tool(
  "search_docs",
  "Search internal documentation by keyword",
  {
    query: z.string().min(1).describe("Search query"),
    limit: z.number().int().min(1).max(20).default(5),
    tag: z.string().optional().describe("Filter by tag"),
  },
  async ({ query, limit, tag }) => {
    const q = query.toLowerCase();
    const results = documents
      .filter((doc) => {
        const matches = doc.title.toLowerCase().includes(q) || doc.body.toLowerCase().includes(q);
        const tagMatch = tag ? doc.tags.includes(tag) : true;
        return matches && tagMatch;
      })
      .slice(0, limit)
      .map(({ id, title, tags }) => ({ id, title, tags }));

    return {
      content: [{ type: "text", text: JSON.stringify(results, null, 2) }],
    };
  }
);

server.tool(
  "get_doc",
  "Retrieve full content of a documentation page by ID",
  {
    id: z.string().min(1).describe("Document ID from search results"),
  },
  async ({ id }) => {
    const doc = documents.find((d) => d.id === id);
    if (!doc) {
      return {
        content: [{ type: "text", text: `Document '${id}' not found` }],
        isError: true,
      };
    }
    return {
      content: [{ type: "text", text: JSON.stringify(doc, null, 2) }],
    };
  }
);

server.resource(
  "docs://index",
  "Index of all available documentation pages",
  async (uri) => ({
    contents: [{
      uri: uri.href,
      text: JSON.stringify(documents.map(({ id, title, tags }) => ({ id, title, tags })), null, 2),
      mimeType: "application/json",
    }],
  })
);

const transport = new StdioServerTransport();
await server.connect(transport);
