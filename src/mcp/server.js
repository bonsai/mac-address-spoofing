#!/usr/bin/node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
// Tools: detect, rotate, reconnect, status, strategy → call PS1 / JS
const server = new Server({ name: "wifi-mac-mcp", version: "1.0.0" });
server.setRequestHandler("tools/list", async () => ({ tools: [{ name: "mac_rotate", inputSchema: { type: "object" } }] }));
await server.connect(new StdioServerTransport());
console.log("mcp-server-wifi-mac ready (JS only, PS1 backend)");
