#!/usr/bin/env node
// MCP server for clockapp. Launched as a subprocess by the clockapp app when the MCP
// toggle is on. It exposes tools to read/edit the RUNNING Clockify time entry, and
// forwards every call to the app's local HTTP API (which talks to Clockify).
//
// The app passes these via environment:
//   APP_API_PORT   port of the app's local HTTP API (127.0.0.1)
//   APP_API_TOKEN  bearer token for that API
//   MCP_PORT       port this MCP server listens on for the MCP client (Claude)
import { createServer } from "node:http";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { z } from "zod";

const APP_API_PORT = process.env.APP_API_PORT;
const APP_API_TOKEN = process.env.APP_API_TOKEN;
const MCP_PORT = Number(process.env.MCP_PORT || 39217);

if (!APP_API_PORT || !APP_API_TOKEN) {
  console.error("Missing APP_API_PORT/APP_API_TOKEN env — start via the clockapp app.");
  process.exit(1);
}

// --- Thin client for the app's local API ---
async function app(method, path, body) {
  const res = await fetch(`http://127.0.0.1:${APP_API_PORT}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${APP_API_TOKEN}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : {};
  if (!res.ok) throw new Error(json.error || `app API ${res.status}`);
  return json;
}

const asText = (obj) => ({ content: [{ type: "text", text: JSON.stringify(obj, null, 2) }] });

// --- MCP server + tools ---
const server = new McpServer({ name: "clockapp", version: "0.1.0" });

server.registerTool(
  "get_current_entry",
  {
    description:
      "Get the currently running time entry: description, project, client, start time and elapsed seconds. Returns { running: false } when the timer is stopped.",
    inputSchema: {},
  },
  async () => asText(await app("GET", "/current")),
);

server.registerTool(
  "set_description",
  {
    description: "Set the description of the running time entry (e.g. what you're working on right now).",
    inputSchema: { description: z.string().describe("New description for the running entry") },
  },
  async ({ description }) => asText(await app("PATCH", "/current", { description })),
);

server.registerTool(
  "set_project",
  {
    description:
      "Set the project of the running time entry. Pass a projectId (from list_projects), or null to clear the project.",
    inputSchema: { projectId: z.string().nullable().describe("Clockify project id, or null to clear") },
  },
  async ({ projectId }) => asText(await app("PATCH", "/current", { projectId })),
);

server.registerTool(
  "list_projects",
  {
    description:
      "List available Clockify projects with their id, name and client — use to resolve a project name to an id for set_project.",
    inputSchema: {},
  },
  async () => asText(await app("GET", "/projects")),
);

// --- Streamable HTTP transport (stateless: fine for a single local client) ---
const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
await server.connect(transport);

const http = createServer((req, res) => {
  if (req.url !== "/mcp") {
    res.writeHead(404).end();
    return;
  }
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : undefined;
    transport.handleRequest(req, res, body);
  });
});

http.listen(MCP_PORT, "127.0.0.1", () => {
  console.error(`clockapp MCP server on http://127.0.0.1:${MCP_PORT}/mcp`);
});
