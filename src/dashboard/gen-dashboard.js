#!/usr/bin/env node
// gen-dashboard.js — data/db.jsonl を「1本の時系列リスト」に変換して data/dashboard.json を作る
//
// 予定も実績も同じ配列 `records` に入る。違いは「時刻が未来かどうか」だけ。
//   future: true  → これからの予定（状態 = planned / due）
//   future: false → 済んだ実績（状態 = ok / fail / info）
//
// usage: node src/dashboard/gen-dashboard.js [--root <repo dir>]
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { normalizeRecord } from "../core/db-schema.mjs";

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

const raw = readFileSync(dbPath, "utf8")
  .split(/\r?\n/)
  .filter((l) => l.trim())
  .flatMap((line) => {
    try {
      return [JSON.parse(line)];
    } catch {
      return []; // 壊れた行は捨てる
    }
  })
  .map(normalizeRecord);

const now = Date.now();
const epochOf = (r) => {
  const v = r.t ?? r.time;
  const ms = v ? Date.parse(v) : NaN;
  return Number.isNaN(ms) ? 0 : ms;
};

const classify = (r, epoch) => {
  const future = epoch > now;
  const plannedCmd = r.cmd === "rotate_planned";

  let state;
  if (plannedCmd && future) state = "planned";
  else if (plannedCmd) state = "due";
  else if (r.ok === true) state = "ok";
  else if (r.ok === false) state = "fail";
  else state = "info";

  return { future, state };
};

// ★ 全部ひとつの配列。時刻の昇順（古い → 未来）。
const records = raw
  .map((r) => {
    const epoch = epochOf(r);
    const { future, state } = classify(r, epoch);
    return {
      ...r,
      time: r.t ?? r.time ?? null,
      epoch,
      future,
      state,
      in_min: future ? Math.round((epoch - now) / 60000) : null,
    };
  })
  .sort((a, b) => a.epoch - b.epoch);

const rotateRecs = records.filter((r) => typeof r.mac === "string" && !r.future);
const lastReal = [...rotateRecs].reverse().find((r) => r.ok === true) ?? null;
const nextPlanned = records.find((r) => r.future) ?? null;

const out = {
  generated_at: new Date(now).toISOString(),
  now_local: new Date(now).toLocaleString("ja-JP", { timeZone: "Asia/Tokyo", hour12: false }),
  now_epoch: now,
  current_mac: lastReal ? { mac: lastReal.mac, at: lastReal.time, ok: lastReal.ok } : null,
  stats: {
    total: records.length,
    done: records.filter((r) => !r.future).length,
    planned: records.filter((r) => r.future).length,
    ok: rotateRecs.filter((r) => r.ok === true).length,
    failed: rotateRecs.filter((r) => r.ok === false).length,
    next_at: nextPlanned?.time ?? null,
    next_in_min: nextPlanned?.in_min ?? null,
  },
  records,
};

writeFileSync(join(dataDir, "dashboard.json"), JSON.stringify(out, null, 2) + "\n", "utf8");

console.log(
  `dashboard.json: ${out.stats.total} records ` +
  `(done=${out.stats.done} planned=${out.stats.planned} ok=${out.stats.ok} failed=${out.stats.failed})` +
  ` current=${out.current_mac?.mac ?? "?"}` +
  (out.stats.next_in_min != null ? ` next=${out.stats.next_at} (${out.stats.next_in_min}min)` : "")
);
