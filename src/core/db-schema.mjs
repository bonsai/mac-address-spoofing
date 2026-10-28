// db-schema.mjs — data/db.jsonl の1行 = 1レコード のスキーマ（唯一の定義元）
//
// ここを直したら `npm run schema` で schema/db.schema.json を作り直す。
// 検証は `npm run validate`（src/tools/validate-db.mjs）がこの定義をそのまま使う。
//
// 時刻は `t` か `time` のどちらでもよい（古いログが time、新しいのが t）。

const ISO = "date-time";
const MAC = "^02([-:][0-9A-Fa-f]{2}){5}$"; // 02 始まり = ローカル管理ユニキャスト

/** 位置情報（scripts/location.ps1 の出力） */
export const LOCATION = {
  type: "object",
  required: ["source"],
  props: {
    source: { type: "string", enum: ["gps", "wifi", "cellular", "ip", "windows"] },
    gps: { type: "boolean" },
    lat: { type: "number" },
    lon: { type: "number" },
    accuracy_m: { type: "number" },
    city: { type: "string" },
    region: { type: "string" },
    country: { type: "string" },
    isp: { type: "string" },
    public_ip: { type: "string" },
  },
};

/**
 * cmd ごとの定義。
 *   require  … 必ず要るフィールド
 *   optional … あってもよいフィールド
 *   props    … 型・パターン（省略したフィールドは検証しない）
 *   strict   … true なら定義外のフィールドをエラーにする
 */
export const COMMANDS = {
  rotate: {
    description: "MAC を付けかえた実績（成功も失敗も残す）",
    require: ["cmd", "mac", "ok"],
    optional: ["adapter", "dry_run", "location", "note"],
    props: {
      cmd: { type: "string" },
      mac: { type: "string", pattern: MAC },
      ok: { type: "boolean" },
      adapter: { type: "string" },
      dry_run: { type: "boolean" },
      note: { type: "string" },
      location: LOCATION,
    },
    strict: false,
  },

  rotate_planned: {
    description: "これから実行する予定（t が未来なら予定として扱われる）",
    require: ["cmd", "run", "of", "task"],
    optional: ["scheduled", "adapter", "status", "note", "interval_min"],
    props: {
      cmd: { type: "string" },
      run: { type: "integer", minimum: 1 },
      of: { type: "integer", minimum: 1 },
      task: { type: "string" },
      scheduled: { type: "string", format: ISO },
      adapter: { type: "string" },
      status: { type: "string", enum: ["pending", "done", "skipped", "failed"] },
      interval_min: { type: "integer", minimum: 1 },
      note: { type: "string" },
    },
    strict: false,
  },

  schedule_rotate: {
    description: "予約を入れた記録",
    require: ["cmd", "in_min"],
    optional: ["task", "at", "note"],
    props: {
      cmd: { type: "string" },
      in_min: { type: "integer", minimum: 1 },
      task: { type: "string" },
      at: { type: "string" },
      note: { type: "string" },
    },
    strict: false,
  },

  speed_record: {
    description: "回線の速さ・遅延の記録",
    require: ["cmd"],
    optional: ["latency_s", "speed_mbps", "public_ip", "local_ip", "location", "note"],
    props: {
      cmd: { type: "string" },
      latency_s: { type: "number", minimum: 0 },
      speed_mbps: { anyOf: [{ type: "number", minimum: 0 }, { type: "null" }] },
      public_ip: { type: "string" },
      local_ip: { type: "string" },
      location: LOCATION,
      note: { type: "string" },
    },
    strict: false,
  },

  // --- ここから下は「ゆるい」記録。必須は cmd だけ ---
  wifi_record: { description: "Wi-Fi 接続の記録", require: ["cmd"], optional: ["ssid", "host", "public_ip", "location", "note"] },
  mcd_connect: { description: "店舗 Wi-Fi に接続", require: ["cmd"], optional: ["ssid", "note"] },
  switch_to_TEX: { description: "SSID 切りかえ", require: ["cmd"], optional: ["ssid", "note"] },
  mac_current: { description: "今の MAC を控えただけ", require: ["cmd"], optional: ["mac", "note"] },
  mac_refresh: { description: "手動リフレッシュ", require: ["cmd"], optional: ["note"] },
  rotate_alert: { description: "「そろそろ変える時間」の通知", require: ["cmd"], optional: ["note", "in_min"] },
};

/** 時刻フィールド（t か time のどちらか） */
export const TIME_FIELDS = ["t", "time"];

/** 未知の cmd を受け入れるか（古いログを壊さないため true） */
export const ALLOW_UNKNOWN_CMD = true;

/* ---------------------------------------------------------------- */

const TYPE_CHECK = {
  string: (v) => typeof v === "string",
  number: (v) => typeof v === "number" && Number.isFinite(v),
  integer: (v) => Number.isInteger(v),
  boolean: (v) => typeof v === "boolean",
  object: (v) => v !== null && typeof v === "object" && !Array.isArray(v),
  null: (v) => v === null,
};

function checkValue(name, value, spec, path, errors) {
  if (spec.anyOf) {
    const sub = [];
    const okAny = spec.anyOf.some((s) => {
      const e = [];
      checkValue(name, value, s, path, e);
      sub.push(...e);
      return e.length === 0;
    });
    if (!okAny) errors.push(`${path}: 型が合いません (${sub.map((s) => s.split(": ")[1]).join(" / ")})`);
    return;
  }

  const typeOk = spec.type ? TYPE_CHECK[spec.type]?.(value) : true;
  if (!typeOk) {
    errors.push(`${path}: ${spec.type} であるべき (実際: ${value === null ? "null" : typeof value})`);
    return;
  }

  if (spec.enum && !spec.enum.includes(value)) {
    errors.push(`${path}: ${JSON.stringify(value)} は ${spec.enum.join(" | ")} のどれかであるべき`);
  }
  if (spec.pattern && typeof value === "string" && !new RegExp(spec.pattern).test(value)) {
    errors.push(`${path}: ${JSON.stringify(value)} がパターン ${spec.pattern} に合いません`);
  }
  if (typeof spec.minimum === "number" && typeof value === "number" && value < spec.minimum) {
    errors.push(`${path}: ${value} は ${spec.minimum} 以上であるべき`);
  }
  if (spec.format === ISO && typeof value === "string" && Number.isNaN(Date.parse(value))) {
    errors.push(`${path}: ${JSON.stringify(value)} が日時として読めません`);
  }
  if (spec.type === "object" && spec.props) {
    for (const [k, s] of Object.entries(spec.props)) {
      if (value[k] !== undefined && value[k] !== null) checkValue(k, value[k], s, `${path}.${k}`, errors);
    }
    if (spec.required) {
      for (const k of spec.required) {
        if (value[k] === undefined) errors.push(`${path}.${k}: 必須`);
      }
    }
  }
}

// --- 古い行の救済 ---
// cmd が無く mac だけある行は、昔の rotate 実績なので cmd を補ってから検証する。
export function normalizeRecord(rec) {
  if (rec && typeof rec === "object" && !Array.isArray(rec) && rec.cmd === undefined && rec.mac !== undefined) {
    return { ...rec, cmd: "rotate", legacy: true };
  }
  return rec;
}

/** 1レコードを検証する。戻り値 { ok, errors, cmd } */
export function validateRecord(input, where = "") {
  const rec = normalizeRecord(input);
  const errors = [];
  const at = where ? `[${where}] ` : "";

  if (rec === null || typeof rec !== "object" || Array.isArray(rec)) {
    return { ok: false, errors: [`${at}行がオブジェクトではありません`], cmd: null };
  }

  // 時刻（t か time）
  const timeField = TIME_FIELDS.find((f) => rec[f] !== undefined);
  if (!timeField) {
    errors.push(`${at}t か time が必要`);
  } else if (Number.isNaN(Date.parse(rec[timeField]))) {
    errors.push(`${at}${timeField}: ${JSON.stringify(rec[timeField])} が日時として読めません`);
  }

  const cmd = rec.cmd;
  if (typeof cmd !== "string") {
    errors.push(`${at}cmd は文字列であるべき`);
    return { ok: false, errors, cmd: null };
  }

  const def = COMMANDS[cmd];
  if (!def) {
    if (ALLOW_UNKNOWN_CMD) return { ok: true, errors, cmd };
    errors.push(`${at}未知の cmd: ${cmd}`);
    return { ok: false, errors, cmd };
  }

  for (const f of def.require ?? []) {
    if (rec[f] === undefined) errors.push(`${at}${cmd}.${f}: 必須`);
  }

  for (const [k, spec] of Object.entries(def.props ?? {})) {
    if (rec[k] === undefined || rec[k] === null) continue;
    checkValue(k, rec[k], spec, `${at}${cmd}.${k}`, errors);
  }

  if (def.strict) {
    const known = new Set([...TIME_FIELDS, ...(def.require ?? []), ...(def.optional ?? []), ...Object.keys(def.props ?? {})]);
    for (const k of Object.keys(rec)) {
      if (!known.has(k)) errors.push(`${at}${cmd}: 定義にないフィールド "${k}"`);
    }
  }

  return { ok: errors.length === 0, errors, cmd };
}

/** schema/db.schema.json を組み立てる（JSON Schema draft-07） */
export function toJsonSchema() {
  const variants = Object.entries(COMMANDS).map(([cmd, def]) => {
    const props = { cmd: { const: cmd }, t: { type: "string", format: ISO }, time: { type: "string", format: ISO } };
    for (const [k, spec] of Object.entries(def.props ?? {})) {
      if (!["cmd", "t", "time"].includes(k)) props[k] = spec;
    }
    return {
      description: def.description,
      type: "object",
      required: [...new Set(["cmd", ...(def.require ?? [])])],
      anyOf: [{ required: ["t"] }, { required: ["time"] }],
      properties: props,
      additionalProperties: !def.strict,
    };
  });

  return {
    $schema: "http://json-schema.org/draft-07/schema#",
    $id: "https://github.com/bonsai/mac-address-spoofing-cron/schema/db.schema.json",
    title: "mac-spoof db.jsonl record",
    description:
      "data/db.jsonl の1行ぶんのスキーマ。t（または time）が未来なら「予定」、過去なら「実績」として扱う。",
    type: "object",
    oneOf: variants,
  };
}
