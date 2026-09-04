#!/usr/bin/env node
/**
 * BrickDot MCP server.
 *
 * Bridges a Claude conversation to the BrickDot Mac app over its loopback
 * listener (Settings › Claude Bridge). The app is the single source of truth for
 * what tools exist: this server fetches the schema from `GET /tools` and mirrors
 * it, so shipping a new Coach tool in the app makes it available here without
 * touching this file. The last good schema is cached on disk so the tool list
 * survives Claude Desktop starting before BrickDot does.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  type Tool,
} from "@modelcontextprotocol/sdk/types.js";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const HOST = process.env.BRICKDOT_HOST ?? "127.0.0.1";
const PORT = process.env.BRICKDOT_PORT ?? "8787";
const TOKEN = process.env.BRICKDOT_TOKEN ?? "";
const BASE = `http://${HOST}:${PORT}`;
const CACHE = join(homedir(), ".brickdot-mcp", "tools.json");

const PREFIX = "brickdot_";
const OFFLINE =
  "BrickDot isn't answering on " +
  BASE +
  ". Check that the app is running on this Mac and that Settings › Claude Bridge is switched on.";

/** Shape the app returns from GET /tools. */
interface AppTool {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
}

async function call(path: string, init: RequestInit = {}): Promise<unknown> {
  if (!TOKEN) {
    throw new Error(
      "BRICKDOT_TOKEN is not set. Copy the token from BrickDot › Settings › Claude Bridge into your MCP config."
    );
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch(BASE + path, {
      ...init,
      signal: controller.signal,
      headers: {
        authorization: `Bearer ${TOKEN}`,
        "content-type": "application/json",
        ...(init.headers ?? {}),
      },
    });
    const text = await response.text();
    if (response.status === 401) {
      throw new Error(
        "BrickDot rejected the token. Re-copy it from Settings › Claude Bridge."
      );
    }
    if (!response.ok) {
      throw new Error(`BrickDot returned ${response.status}: ${text}`);
    }
    return text ? JSON.parse(text) : {};
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (
      message.includes("ECONNREFUSED") ||
      message.includes("fetch failed") ||
      message.includes("aborted")
    ) {
      throw new Error(OFFLINE);
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

/** Tools the app exposes, plus one of our own for the daily snapshot. */
function toMCP(appTools: AppTool[]): Tool[] {
  const mapped: Tool[] = appTools.map((tool) => ({
    name: PREFIX + tool.name,
    description: tool.description,
    inputSchema: tool.input_schema as Tool["inputSchema"],
  }));

  mapped.push({
    name: PREFIX + "snapshot",
    description:
      "Everything open right now in BrickDot: active timer, per-client unbilled minutes, and every unfinished task with its id. Cheapest way to get oriented before looking anything up.",
    inputSchema: { type: "object", properties: {} },
  });

  return mapped;
}

async function loadTools(): Promise<Tool[]> {
  try {
    const payload = (await call("/tools")) as { tools: AppTool[] };
    await mkdir(dirname(CACHE), { recursive: true });
    await writeFile(CACHE, JSON.stringify(payload.tools), "utf8");
    return toMCP(payload.tools);
  } catch {
    // App is down. Serve the last schema we saw so the tools still appear and
    // fail with a useful message, rather than vanishing from the conversation.
    try {
      const cached = JSON.parse(await readFile(CACHE, "utf8")) as AppTool[];
      return toMCP(cached);
    } catch {
      return [
        {
          name: PREFIX + "status",
          description:
            "Check whether the BrickDot app is reachable from this Mac.",
          inputSchema: { type: "object", properties: {} },
        },
      ];
    }
  }
}

const server = new Server(
  { name: "brickdot", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: await loadTools(),
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const name = request.params.name.startsWith(PREFIX)
    ? request.params.name.slice(PREFIX.length)
    : request.params.name;
  const args = (request.params.arguments ?? {}) as Record<string, unknown>;

  try {
    if (name === "status") {
      const health = await call("/health");
      return text(`BrickDot is reachable. ${JSON.stringify(health)}`);
    }

    if (name === "snapshot") {
      return text(JSON.stringify(await call("/snapshot")));
    }

    const response = (await call("/tool", {
      method: "POST",
      body: JSON.stringify({ name, input: args }),
    })) as { ok?: boolean; result?: string; error?: string };

    if (response.error) return text(response.error, true);
    return text(response.result ?? JSON.stringify(response));
  } catch (error) {
    return text(error instanceof Error ? error.message : String(error), true);
  }
});

function text(body: string, isError = false) {
  return { content: [{ type: "text" as const, text: body }], isError };
}

await server.connect(new StdioServerTransport());
