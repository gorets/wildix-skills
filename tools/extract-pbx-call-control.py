#!/usr/bin/env python3
"""Builds the reference of the wildix-call-control skill from the OpenAPI of the Wildix PBX.

  python3 tools/extract-pbx-call-control.py <pbx-openapi.yaml> [skills/wildix-call-control/references]

The source is the PBX API document published at https://docs.wildix.com/pbx-openapi.yaml (the page
https://docs.wildix.com/api-reference/rest/wms/pbx shows it). It keeps the Call Control operations and the
components they refer to, and points the server at /api/v2: the operations live at
https://<pbx>/api/v2/call-control/..., although the document's global server says /api/v1.
Needs PyYAML (`pip install pyyaml`).
"""
import json, os, sys
try:
    import yaml
except ImportError:
    sys.exit("PyYAML is needed: pip install pyyaml")

if len(sys.argv) < 2:
    sys.exit(__doc__)
src = sys.argv[1]
out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "skills", "wildix-call-control", "references")
doc = yaml.safe_load(open(src, encoding="utf-8"))

paths = {p: v for p, v in doc["paths"].items() if p.startswith("/call-control/")}
if not paths:
    sys.exit("no /call-control/ paths in the source")

# Collect the components the operations refer to, following references inside components too.
refs, queue = set(), [paths]
while queue:
    node = queue.pop()
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "$ref" and isinstance(v, str) and v.startswith("#/components/") and v not in refs:
                refs.add(v)
                kind, name = v.split("/")[2:4]
                queue.append(doc["components"][kind][name])
            else:
                queue.append(v)
    elif isinstance(node, list):
        queue.extend(node)

components = {}
for r in sorted(refs):
    kind, name = r.split("/")[2:4]
    components.setdefault(kind, {})[name] = doc["components"][kind][name]
schemes = doc.get("components", {}).get("securitySchemes", {})
components["securitySchemes"] = {k: schemes[k] for k in ("OAuth2", "Token", "Bearer", "CompanyApiKey") if k in schemes}

tag = next((t for t in doc.get("tags", []) if t.get("name") == "Call Control"), {"name": "Call Control"})
ref = {
    "openapi": doc.get("openapi", "3.0.0"),
    "info": {
        "title": "Wildix PBX Call Control",
        "version": str(doc.get("info", {}).get("version", "")),
        "description": "The Call Control operations of the Wildix PBX API (WMS), taken from "
                       "https://docs.wildix.com/pbx-openapi.yaml. They live under /api/v2/call-control/ of the "
                       "user's PBX. The wildix-call-control skill calls them with the user's x-bees login token "
                       "(Authorization: Bearer <ID token>); the PBX also takes the other schemes listed here.",
    },
    "servers": [{"url": "https://{pbx}/api/v2", "variables": {"pbx": {"default": "demo.wildixin.com", "description": "The user's PBX host (with :port when it is not 443)"}}}],
    "tags": [tag],
    "paths": paths,
    "components": components,
}
os.makedirs(out_dir, exist_ok=True)
dest = os.path.join(out_dir, "call-control.openapi.json")
with open(dest, "w", encoding="utf-8") as f:
    json.dump(ref, f, indent=2, ensure_ascii=False)
    f.write("\n")
ops = sum(1 for v in paths.values() for m in v if m in ("get", "post", "put", "patch", "delete"))
print(f"{dest}: {ops} operations")
