#!/usr/bin/env node
// Builds the `queues` reference of the wildix-calls-history skill: the reports of the WDA x-caracal service
// (/v2/xcaracal/...: distribution, answered, unanswered, the call list and the events of a call) and the list of
// the queues of the company (/v2/stream/services of the WDA stream service), with only the schemas they reach.
// Left out on purpose: the dashboards of the x-caracal screens (/v2/xcaracal/dashboards), the setup of a screen.
//
// Usage: node tools/split-xcaracal-openapi.mjs <WdaXcaracal.openapi.json> <wda-stream-client.openapi.json> [outDir]
//   WdaXcaracal.openapi.json: built from wildix-sdk/sdk-models with the smithy `openapi` plugin, projection
//     {"plugins": {"openapi": {"service": "wildix.wda.xcaracal#WdaXcaracal", "protocol": "aws.protocols#restJson1",
//     "version": "3.1.0"}}} in smithy-build.json and software.amazon.smithy:smithy-openapi in build.gradle.kts,
//     then ./gradlew build: build/smithyprojections/<project>/<projection>/openapi/WdaXcaracal.openapi.json
//   wda-stream-client.openapi.json: wildix-sdk/sdk-docs/static/codegen/api/
//   outDir: skills/wildix-calls-history/references (default)
import fs from 'node:fs';
import path from 'node:path';

const [xcSrc, streamSrc, outDir = 'skills/wildix-calls-history/references'] = process.argv.slice(2);
if (!xcSrc || !streamSrc) {
  console.error('usage: split-xcaracal-openapi.mjs <WdaXcaracal.openapi.json> <wda-stream-client.openapi.json> [outDir]');
  process.exit(1);
}
const xc = JSON.parse(fs.readFileSync(xcSrc, 'utf8'));
const stream = JSON.parse(fs.readFileSync(streamSrc, 'utf8'));
const METHODS = ['get', 'put', 'post', 'delete', 'patch'];

const take = [
  [xc, (p) => p.startsWith('/v2/xcaracal/') && !p.startsWith('/v2/xcaracal/dashboards')],
  [stream, (p) => p === '/v2/stream/services'],
];

// Each document's paths reach only its own schemas; a name both use must mean the same schema.
function collect(value, seen, own) {
  if (Array.isArray(value)) { value.forEach((v) => collect(v, seen, own)); return; }
  if (value && typeof value === 'object') {
    for (const [k, v] of Object.entries(value)) {
      if (k === '$ref' && typeof v === 'string' && v.startsWith('#/components/schemas/')) {
        const name = v.split('/').pop();
        if (seen.has(name)) {
          if (JSON.stringify(seen.get(name)) !== JSON.stringify(own[name])) throw new Error(`schema ${name} differs between the documents`);
          continue;
        }
        seen.set(name, own[name]);
        collect(own[name], seen, own);
      } else collect(v, seen, own);
    }
  }
}

const paths = {};
const seen = new Map();
for (const [d, keep] of take) {
  const own = d.components?.schemas ?? {};
  for (const [p, item] of Object.entries(d.paths)) {
    if (!keep(p)) continue;
    const ops = Object.fromEntries(METHODS.filter((m) => item[m]).map((m) => [m, item[m]]));
    paths[p] = ops;
    collect(ops, seen, own);
  }
}
for (const name of seen.keys()) if (!seen.get(name)) throw new Error(`schema ${name} not found`);

const slice = {
  openapi: xc.openapi,
  info: {title: 'WDA x-caracal: reports on the calls of queues', version: xc.info.version, description: xc.info.description},
  servers: [{url: 'https://wda.wildix.com'}],
  security: xc.security,
  paths: Object.fromEntries(Object.entries(paths).sort(([a], [b]) => a.localeCompare(b))),
  components: {
    schemas: Object.fromEntries([...seen.keys()].sort().map((n) => [n, seen.get(n)])),
    securitySchemes: xc.components?.securitySchemes,
  },
};
fs.mkdirSync(outDir, {recursive: true});
const file = path.join(outDir, 'queues.openapi.json');
fs.writeFileSync(file, JSON.stringify(slice, null, 2) + '\n');
const ops = Object.values(paths).flatMap((i) => METHODS.filter((m) => i[m]).map((m) => i[m].operationId));
console.table([{section: 'queues', file, operations: ops.length, schemas: seen.size, bytes: fs.statSync(file).size}]);
