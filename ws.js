// ws.js — WebSocket bridge (no build, pure Node)
import WebSocket, { WebSocketServer } from "ws";
const wss = new WebSocketServer({ port: 8765 });
console.log("WS bridge on ws://localhost:8765");
wss.on("connection", (ws) => {
  ws.on("message", (data) => {
    const msg = JSON.parse(data);
    if (msg.cmd === "rotate") console.log("WS rotate request");
    ws.send(JSON.stringify({ status: "ok", cmd: msg.cmd, ts: Date.now() }));
  });
});
