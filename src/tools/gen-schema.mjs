#!/usr/bin/env node
// gen-schema.mjs — src/core/db-schema.mjs から schema/db.schema.json を作る
//   node src/tools/gen-schema.mjs
import { writeFileSync, mkdirSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { toJsonSchema } from "../core/db-schema.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const outDir = join(root, "schema");
mkdirSync(outDir, { recursive: true });

const schema = toJsonSchema();
const outPath = join(outDir, "db.schema.json");
writeFileSync(outPath, JSON.stringify(schema, null, 2) + "\n", "utf8");

console.log(`wrote ${outPath} (${schema.oneOf.length} cmd variants)`);
