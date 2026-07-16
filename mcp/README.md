# clockapp MCP server

A tiny [MCP](https://modelcontextprotocol.io) server that lets an assistant (Claude, etc.)
read and edit the **currently running** Clockify time entry — what you're working on,
its project/client, and its start time / elapsed duration.

## How it works

```
Claude ⇄ (HTTP) ⇄ this server (Node) ⇄ (HTTP + token) ⇄ clockapp app ⇄ Clockify
                   └── spawned & killed by the clockapp app (MCP toggle)
```

The app owns the lifecycle: enabling **Settings → MCP server** starts this process
(passing the app's local API port + a token via env); disabling it kills the process.
So the app must be running with the toggle on.

## Tools

| Tool | Description |
|---|---|
| `get_current_entry` | Running entry: description, project, client, start, elapsed seconds. |
| `set_description` | Set the running entry's description. |
| `set_project` | Set the running entry's project (by id, or null to clear). |
| `list_projects` | List projects (id, name, client) to resolve a name → id. |

## Connect a client

The server listens on a fixed local URL: `http://127.0.0.1:39217/mcp`.

**Claude Code:**
```bash
claude mcp add --transport http clockapp http://127.0.0.1:39217/mcp
```

**Claude Desktop** (`claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "clockapp": { "url": "http://127.0.0.1:39217/mcp" }
  }
}
```

## Requirements

- **Node.js** installed (the app looks in `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`).
- The clockapp app running with the MCP toggle enabled and Clockify connected.

## Env (set by the app)

| Var | Meaning |
|---|---|
| `APP_API_PORT` | Port of the app's local HTTP API. |
| `APP_API_TOKEN` | Bearer token for that API. |
| `MCP_PORT` | Port this server listens on (default 39217). |
