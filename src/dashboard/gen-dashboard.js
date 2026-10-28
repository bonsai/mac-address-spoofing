#!/usr/bin/env node
// gen-dashboard.js — data/db.jsonl を「実績」と「予定(未来)」に分けて data/dashboard.json を作る
// usage: node src/dashboard/gen-dashboard.js [--root <repo dir>]
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// 既定のルート = このファイルから2階層上（<repo>）
const root = process.argv.includes("--root")
  ? resolve(process.argv[process.argv.indexOf("--root") + 1])
  : resolve(dirname(fileURLToPath(import.meta.url)), "../..");

const dataDir = join(root, "data");
const dbPath = join(dataDir, "db.jsonl");
if (!existsSync(dbPath)) {
  console.error(`db.jsonl not found: ${dbPath}`);
  process.exit(1);
}

const records = readFileSync(dbPath, "utf8")
  .split(/\r?\n/)
  .filter((l) => l.trim())
  .flatMap((line) => {
    try {
      return [JSON.parse(line)];
    } catch {
      return []; // 壊れた行は捨てる
    }
  });

// cmd が無いが mac を持つ行は rotate 実績とみなす
for (const r of records) if (!r.cmd && r.mac && "ok" in r) r.cmd = "rotate";

const t = (r) => new Date(r.t ?? r.time ?? 0).getTime() || 0;
const now = Date.now();

// 未来の予定 = t が現在より後 / 明示的に pending
const planned = records
  .filter((r) => r.cmd === "rotate_planned" || t(r) > now)
  .sort((a, b) => t(a) - t(b))
  .map((r) => ({
    ...r,
    in_min: Math.max(0, Math.round((t(r) - now) / 60000)),
    state: t(r) > now ? "upcoming" : "due",
  }));

const done = records
  .filter((r) => !planned.includes(r) && t(r) <= now)
  .sort((a, b) => t(b) - t(a));

const macs = done.filter((r) => typeof r.mac === "string");
const current = macs[0] ?? null;

const out = {
  generated_at: new Date(now).toISOString(),
  now_local: new Date(now).toLocaleString("ja-JP", { timeZone: "Asia/Tokyo" }),
  current_mac: current ? { mac: current.mac, at: current.t ?? current.time, ok: current.ok ?? null } : null,
  stats: {
    total_records: records.length,
    rotations_ok: macs.filter((r) => r.ok === true).length,
    rotations_failed: macs.filter((r) => r.ok === false).length,
    planned: planned.length,
  },
  planned,
  recent: done.slice(0, 30),
};

writeFileSync(join(dataDir, "dashboard.json"), JSON.stringify(out, null, 2) + "\n", "utf8");
console.log(
  `dashboard.json: ${out.stats.total_records} records, ${out.stats.planned} planned, ` +
  `ok=${out.stats.rotations_ok} failed=${out.stats.rotations_failed}, current=${out.current_mac?.mac ?? "?"}`
);
