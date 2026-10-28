#!/usr/bin/env node
// validate-db.mjs — JSONL をスキーマで検証する
//   node src/tools/validate-db.mjs data/db.jsonl
//   node src/tools/validate-db.mjs data/sample.db.jsonl --quiet
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { validateRecord } from "../core/db-schema.mjs";

const args = process.argv.slice(2);
const quiet = args.includes("--quiet");
const file = args.find((a) => !a.startsWith("--"));

if (!file) {
  console.error("usage: node src/tools/validate-db.mjs <file.jsonl> [--quiet]");
  process.exit(2);
}

const path = resolve(file);
if (!existsSync(path)) {
  console.error(`not found: ${path}`);
  process.exit(2);
}

const lines = readFileSync(path, "utf8").split(/\r?\n/);

let total = 0;
let bad = 0;
const byCmd = new Map();

lines.forEach((line, i) => {
  if (!line.trim()) return;
  total++;

  let rec;
  try {
    rec = JSON.parse(line);
  } catch (e) {
    bad++;
    console.log(`${path}:${i + 1}: JSON として読めません — ${e.message}`);
    return;
  }

  const res = validateRecord(rec, `${i + 1}`);
  byCmd.set(res.cmd ?? "(none)", (byCmd.get(res.cmd ?? "(none)") ?? 0) + 1);

  if (!res.ok) {
    bad++;
    for (const err of res.errors) console.log(`${path}:${i + 1}: ${err}`);
  }
});

if (!quiet) {
  console.log("");
  console.log(`file    : ${path}`);
  console.log(`records : ${total}`);
  console.log(`invalid : ${bad}`);
  console.log(
    "by cmd  : " +
      [...byCmd.entries()]
        .sort((a, b) => b[1] - a[1])
        .map(([c, n]) => `${c}=${n}`)
        .join(" ")
  );
}

process.exit(bad === 0 ? 0 : 1);
