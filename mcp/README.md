# BrickDot MCP server

Lets a Claude conversation on this Mac read and update BrickDot.

```
Claude  ──stdio──▶  brickdot-mcp  ──HTTP──▶  127.0.0.1:8787  ──▶  BrickDot (Mac Catalyst)
                                                                        │
                                                                   SwiftData
                                                                        │
                                                                    CloudKit ──▶ iPhone
```

Writes go through the same main-context save the task editor uses, so anything
changed here syncs to the phone like a normal edit.

## Setup

**1. Turn on the bridge in the app.** BrickDot on the Mac → Settings → Claude
Bridge → *Allow Claude to connect*. Leave **Read-only** on for the first run.
Tap *Show connection token* and copy it.

**2. Build the server.**

```sh
cd ~/Documents/BrickDot/mcp
npm install
npm run build
```

**3. Point Claude at it.** In `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "brickdot": {
      "command": "node",
      "args": ["/Users/michaelrobb/Documents/BrickDot/mcp/dist/index.js"],
      "env": { "BRICKDOT_TOKEN": "paste-the-token-here" }
    }
  }
}
```

Restart Claude. Tools appear as `brickdot_findTasks`, `brickdot_addTime`, and so on.

**4. Check it end to end** without Claude:

```sh
TOKEN=paste-the-token-here
curl -s -H "authorization: Bearer $TOKEN" http://127.0.0.1:8787/health
curl -s -H "authorization: Bearer $TOKEN" http://127.0.0.1:8787/snapshot | jq .
curl -s -X POST -H "authorization: Bearer $TOKEN" -H "content-type: application/json" \
  -d '{"name":"findTasks","input":{"query":"cobblestone"}}' \
  http://127.0.0.1:8787/tool | jq .
```

Once that looks right, turn **Read-only** off.

## Tools

The server does not keep its own list. It calls `GET /tools` and mirrors whatever
the running build exposes, so adding a Coach tool in `CoachToolSchema.swift` makes
it available to Claude with no change here. The last schema it saw is cached at
`~/.brickdot-mcp/tools.json`, so tools still list when BrickDot is closed — calls
then fail with a message saying so rather than disappearing.

## Environment

| Variable | Default | Notes |
|---|---|---|
| `BRICKDOT_TOKEN` | — | Required. From Settings → Claude Bridge. |
| `BRICKDOT_PORT` | `8787` | Must match the app. |
| `BRICKDOT_HOST` | `127.0.0.1` | Leave it. The app only binds loopback. |

## Notes

- **The app must be running on this Mac.** The listener dies with the process.
  The phone is downstream via CloudKit — it is not reachable directly.
- **The token is the only thing guarding the database.** Any process running as
  this user can reach a loopback port, which is why the bridge refuses
  unauthenticated requests. Regenerate it in Settings if it leaks, and update the
  config.
- **No confirmation step.** In-app, wide changes wait for a tap; over the bridge
  that judgment lives in the Claude conversation. Read-only mode is the seatbelt.
