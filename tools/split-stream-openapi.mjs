#!/usr/bin/env node
// Splits the OpenAPI document of the Wildix stream service into one file per section (tag), each with
// only the paths of the section and the schemas those paths reach. The files are the reference of the
// wildix-chat skill: skills/wildix-chat/references/<section>.openapi.json.
//
// Operations listed in tools/stream-not-implemented.json get `x-not-implemented: true` and a note in their description.
//
// Usage: node tools/split-stream-openapi.mjs <stream-client.openapi.json> [outDir]
//   source: wildix-sdk/sdk-ts/packages/stream-client/etc/stream-client.openapi.json
//   outDir: skills/wildix-chat/references (default)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [src, outDir = 'skills/wildix-chat/references'] = process.argv.slice(2);
if (!src) { console.error('usage: split-stream-openapi.mjs <openapi.json> [outDir]'); process.exit(1); }

const doc = JSON.parse(fs.readFileSync(src, 'utf8'));

// operations the service answers with "Operation <Name> is not implemented." (kept by hand next to this script)
const notImplemented = JSON.parse(fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), 'stream-not-implemented.json'), 'utf8'));
const NOT_READY = new Set(notImplemented.operations);
const schemas = doc.components?.schemas ?? {};
const METHODS = ['get', 'put', 'post', 'delete', 'patch'];

// every $ref reachable from a value, followed through the schemas
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

const bySection = new Map();
for (const [p, item] of Object.entries(doc.paths)) {
  for (const m of METHODS) {
    let op = item[m];
    if (!op) continue;
    if (NOT_READY.has(op.operationId)) {
      op = {
        ...op,
        description: `NOT IMPLEMENTED YET in the service (checked ${notImplemented.checked}): it answers HTTP 400 "Operation ${op.operationId} is not implemented." ${op.description ?? ''}`.trim(),
        'x-not-implemented': true,
      };
    }
    const tag = (op.tags && op.tags[0]) || 'Other';
    if (!bySection.has(tag)) bySection.set(tag, {});
    const paths = bySection.get(tag);
    paths[p] = { ...(paths[p] ?? {}), [m]: op };
    if (item.parameters) paths[p].parameters = item.parameters;
  }
}

fs.mkdirSync(outDir, { recursive: true });
const index = [];
for (const [tag, paths] of [...bySection.entries()].sort()) {
  const seen = new Set();
  collect(paths, seen);
  const slice = {
    openapi: doc.openapi,
    info: { title: `${doc.info.title}: ${tag}`, version: doc.info.version },
    servers: doc.servers,
    security: doc.security,
    paths,
    components: {
      schemas: Object.fromEntries([...seen].sort().map((n) => [n, schemas[n]])),
      securitySchemes: doc.components.securitySchemes,
    },
  };
  const file = `${tag.toLowerCase()}.openapi.json`;
  fs.writeFileSync(path.join(outDir, file), JSON.stringify(slice, null, 2) + '\n');
  const ops = Object.values(paths).flatMap((i) => METHODS.filter((m) => i[m]).map((m) => i[m].operationId));
  index.push({ tag, file, operations: ops.length, schemas: seen.size, bytes: fs.statSync(path.join(outDir, file)).size });
}
console.table(index);
