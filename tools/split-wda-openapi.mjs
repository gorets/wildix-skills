#!/usr/bin/env node
// Builds the references of the wildix-conversation-history skill from the OpenAPI documents of the two services
// behind it: WDA History (the records) and WDA Insights (summaries, insights, recordings, search).
// One file per section, each with only its paths and the schemas those paths reach:
//   conferences   /history/conferences/*   /insights/conferences/*
//   calls         /history/calls/*  /history/user/calls   /insights/calls/*
//   conversations /history/conversations /insights/conversations*
// Left out on purpose: chats (they belong to the chat service), and the setup of the analytics screens
// (dashboards, filters, playlists, projections, analysis settings, watch history).
//
// Usage: node tools/split-wda-openapi.mjs <wda-history-client.openapi.json> <wda-insights-client.openapi.json> [outDir]
//   sources: wildix-sdk/sdk-docs/static/codegen/api/
//   outDir:  skills/wildix-conversation-history/references (default)
import fs from 'node:fs';
import path from 'node:path';

const [historySrc, insightsSrc, outDir = 'skills/wildix-conversation-history/references'] = process.argv.slice(2);
if (!historySrc || !insightsSrc) { console.error('usage: split-wda-openapi.mjs <history.openapi.json> <insights.openapi.json> [outDir]'); process.exit(1); }

const docs = [historySrc, insightsSrc].map((f) => JSON.parse(fs.readFileSync(f, 'utf8')));
const METHODS = ['get', 'put', 'post', 'delete', 'patch'];

const SECTIONS = [
  ['conferences', /^\/v2\/(history|insights)\/conferences(\/|$)/],
  ['calls', /^\/v2\/(history\/calls\/|history\/user\/calls$|insights\/calls\/)/],
  ['conversations', /^\/v2\/(history\/conversations$|insights\/conversations(\/|$))/],
];

// the schemas of both documents under one name each; the same name must mean the same schema
const schemas = {};
for (const d of docs) for (const [name, s] of Object.entries(d.components?.schemas ?? {})) {
  if (schemas[name] && JSON.stringify(schemas[name]) !== JSON.stringify(s)) throw new Error(`schema ${name} differs between the documents`);
  schemas[name] = s;
}

function collect(value, seen) {
  if (Array.isArray(value)) { value.forEach((v) => collect(v, seen)); return; }
  if (value && typeof value === 'object') {
    for (const [k, v] of Object.entries(value)) {
      if (k === '$ref' && typeof v === 'string' && v.startsWith('#/components/schemas/')) {
        const name = v.split('/').pop();
        if (!seen.has(name)) { seen.add(name); collect(schemas[name], seen); }
      } else collect(v, seen);
    }
  }
}

fs.mkdirSync(outDir, { recursive: true });
const rows = [];
for (const [section, re] of SECTIONS) {
  const paths = {};
  for (const d of docs) for (const [p, item] of Object.entries(d.paths)) {
    if (!re.test(p)) continue;
    for (const m of METHODS) if (item[m]) paths[p] = { ...(paths[p] ?? {}), [m]: item[m] };
  }
  const seen = new Set();
  collect(paths, seen);
  const slice = {
    openapi: docs[0].openapi,
    info: { title: `WDA conversation history: ${section}`, version: docs[0].info.version },
    servers: docs[0].servers,
    security: docs[0].security,
    paths: Object.fromEntries(Object.entries(paths).sort(([a], [b]) => a.localeCompare(b))),
    components: { schemas: Object.fromEntries([...seen].sort().map((n) => [n, schemas[n]])), securitySchemes: docs[0].components.securitySchemes },
  };
  const file = `${section}.openapi.json`;
  fs.writeFileSync(path.join(outDir, file), JSON.stringify(slice, null, 2) + '\n');
  const ops = Object.values(paths).flatMap((i) => METHODS.filter((m) => i[m]).map((m) => i[m].operationId));
  rows.push({ section, file, operations: ops.length, schemas: seen.size, bytes: fs.statSync(path.join(outDir, file)).size });
}
console.table(rows);
