#!/usr/bin/env node
// serve.mjs — リポジトリのルートを配信するだけの静的サーバ（python 不要）
//   node src/tools/serve.mjs [--port 8080] [--open]
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, resolve, extname, normalize } from "node:path";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { exec } from "node:child_process";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const argv = process.argv.slice(2);
const portArg = argv.includes("--port") ? Number(argv[argv.indexOf("--port") + 1]) : 8080;
const open = argv.includes("--open");

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".jsonl": "application/x-ndjson; charset=utf-8",
  ".md": "text/markdown; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon",
};

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://127.0.0.1");
    let pathname = decodeURIComponent(url.pathname);

    // 短い URL でダッシュボードを開けるようにする
    //   /           → /src/dashboard/index.html
    //   /d  /dash   → 同上
    if (pathname === "/" || pathname === "" || pathname === "/d" || pathname === "/dash") {
      pathname = "/src/dashboard/index.html";
    }

    // ディレクトリトラバーサル防止
    const target = normalize(join(root, pathname));
    if (!target.startsWith(root)) {
      res.writeHead(403).end("forbidden");
      return;
    }
    if (!existsSync(target)) {
      res.writeHead(404, { "content-type": "text/plain; charset=utf-8" }).end(`404 ${pathname}`);
      return;
    }
    const st = await stat(target);
    if (st.isDirectory()) {
      res.writeHead(302, { location: pathname.replace(/\/?$/, "/") + "index.html" }).end();
      return;
    }

    const body = await readFile(target);
    res.writeHead(200, {
      "content-type": MIME[extname(target).toLowerCase()] ?? "application/octet-stream",
      "cache-control": "no-store",
    }).end(body);
  } catch (e) {
    res.writeHead(500, { "content-type": "text/plain; charset=utf-8" }).end(String(e));
  }
});

server.listen(portArg, "127.0.0.1", () => {
  const url = `http://127.0.0.1:${portArg}/`;
  console.log(`dashboard: ${url}   ← これだけ覚えればOK`);
  console.log(`(短縮: /d でも同じ / Ctrl+C で停止 / root: ${root})`);
  if (open) {
    const cmd =
      process.platform === "win32" ? `start "" "${url}"` :
      process.platform === "darwin" ? `open "${url}"` : `xdg-open "${url}"`;
    exec(cmd, () => {});
  }
});

server.on("error", (e) => {
  if (e.code === "EADDRINUSE") {
    console.error(`port ${portArg} は使用中です。 --port 8081 のように変えてください。`);
  } else {
    console.error(e.message);
  }
  process.exit(1);
});
