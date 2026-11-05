#!/usr/bin/env python3
"""Checks the skills of this repository the way a strict consumer would read them.

  python3 tools/check-skills.py

For every skills/<name>/: SKILL.md has a frontmatter that a strict YAML parser reads, `name` equals the
folder, `description` is up to 1024 characters; peers.yaml parses and names existing skills; the relative
links of SKILL.md point at files that exist; every script passes `bash -n`. Also: no hard-coded
`~/.claude/skills` path in SKILL.md, peers.yaml, commands or a command line of the README, and every script that is run (not sourced)
is executable. Needs PyYAML (`pip install pyyaml`). Exit code 1 when anything is wrong.
"""
import glob, os, re, subprocess, sys
try:
    import yaml
except ImportError:
    sys.exit("PyYAML is needed: pip install pyyaml")

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(root)
problems = []
def bad(msg): problems.append(msg)

names = sorted(d for d in os.listdir("skills") if os.path.isdir(os.path.join("skills", d)))
for n in names:
    skill = os.path.join("skills", n, "SKILL.md")
    if not os.path.isfile(skill):
        bad(f"{n}: no SKILL.md"); continue
    text = open(skill, encoding="utf-8").read()
    parts = text.split("---", 2)
    if len(parts) < 3:
        bad(f"{skill}: no frontmatter"); continue
    try:
        fm = yaml.safe_load(parts[1])
    except yaml.YAMLError as e:
        bad(f"{skill}: frontmatter is not valid YAML: {str(e).splitlines()[0]} (quote it or use `description: >-`)"); continue
    if fm.get("name") != n: bad(f"{skill}: name {fm.get('name')!r} differs from the folder {n!r}")
    d = fm.get("description") or ""
    if not d: bad(f"{skill}: empty description")
    if len(d) > 1024: bad(f"{skill}: description is {len(d)} characters (limit 1024)")
    for link in re.findall(r"\]\((?!https?:|#|mailto:)([^)\s]+)\)", parts[2]):
        if not os.path.exists(os.path.join("skills", n, link.split("#")[0])): bad(f"{skill}: broken link {link}")
    if "~/.claude/skills" in text or ".claude/skills/" in text: bad(f"{skill}: hard-coded ~/.claude/skills path")
    peers = os.path.join("skills", n, "peers.yaml")
    if os.path.isfile(peers):
        try:
            pd = yaml.safe_load(open(peers, encoding="utf-8"))
            for p in pd.get("peers", []):
                if p["name"] not in names: bad(f"{peers}: peer {p['name']!r} is not a skill of this repository")
                if "glob" in p: bad(f"{peers}: path-based `glob` field (installation is judged by what the agent can see)")
        except yaml.YAMLError as e:
            bad(f"{peers}: not valid YAML: {str(e).splitlines()[0]}")
    for sh in glob.glob(os.path.join("skills", n, "scripts", "*.sh")):
        r = subprocess.run(["bash", "-n", sh], capture_output=True, text=True)
        if r.returncode: bad(f"{sh}: bash -n failed: {r.stderr.strip()}")

for f in glob.glob("commands/*.md"):
    if "~/.claude/skills" in open(f, encoding="utf-8").read(): bad(f"{f}: hard-coded ~/.claude/skills path")
# the README may talk about the folder, but a command line of it must not depend on it
for n, line in enumerate(open("README.md", encoding="utf-8"), 1):
    if re.match(r"\s*(cp|bash|ls|cat|node|python3?)\b.*~/\.claude/skills", line): bad(f"README.md:{n}: a command with a hard-coded ~/.claude/skills path")

# scripts that are run by the agent must be executable; libraries that are only sourced need not be
sourced = {"config.sh", "load-token.sh", "lib.sh"}
for sh in glob.glob("skills/*/scripts/*.sh"):
    if os.path.basename(sh) not in sourced and not os.access(sh, os.X_OK): bad(f"{sh}: not executable")

print(f"{len(names)} skills checked")
for p in problems: print("PROBLEM:", p)
sys.exit(1 if problems else 0)
