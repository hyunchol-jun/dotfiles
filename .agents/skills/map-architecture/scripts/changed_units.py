#!/usr/bin/env python3
"""Incremental mode: which survey units need re-surveying since the map's commit?
Usage: changed_units.py <OUT>   (run from the repo toplevel)
Reads the commit from ARCHITECTURE.md §1 and the `paths` / `manifests` columns of inventory.md.
Prints: units to re-survey, changed paths no unit claims, and whether deploy manifests changed."""
import os, re, subprocess, sys
OUT = sys.argv[1]
md = open(os.path.join(OUT, "ARCHITECTURE.md")).read()
sha = re.search(r"- commit: `([0-9a-f]+)`", md).group(1)
inv = open(os.path.join(OUT, "inventory.md")).read()
rows, cols = [], None
for line in inv.splitlines():
    if not line.startswith("|"): continue
    cells = [c.strip().strip("`") for c in line.strip().strip("|").split("|")]
    if cols is None: cols = [c.lower() for c in cells]; continue
    if all(re.fullmatch(r":?-+:?", c) for c in cells): continue
    rows.append(dict(zip(cols, cells)))
changed = subprocess.run(["git", "diff", "--name-only", f"{sha}..HEAD"], capture_output=True, text=True, check=True).stdout.split()
root_manifests = re.compile(r"^(package\.json|pnpm-workspace\.yaml|Cargo\.toml|pyproject\.toml|go\.mod|.*Dockerfile.*)$")
hit, unclaimed, manifests = {}, [], False
for p in changed:
    if p.endswith("version.yaml"): continue  # image-pin bumps are not structural
    owners = set()
    for r in rows:
        for pref in re.split(r"[,\s]+", r.get("paths", "")):
            if pref and p.startswith(pref.rstrip("/") + "/") or p == pref: owners.add(r["unit"])
        for pref in re.split(r"[,\s]+", r.get("manifests", "")):
            if pref and (p.startswith(pref.rstrip("/")) ): owners.add(r["unit"]); manifests = True
    if root_manifests.match(p) or p.startswith(("environments/", "infrastructure/")): manifests = True
    if owners:
        for u in owners: hit.setdefault(u, []).append(p)
    else: unclaimed.append(p)
print(f"since: {sha}  changed files: {len(changed)}")
print("re-survey:", " ".join(sorted(hit)) or "(none)")
for u, ps in sorted(hit.items()): print(f"  {u}: {len(ps)} files, e.g. {ps[0]}")
print("manifests-changed:", "yes (re-run pass 1 inventory)" if manifests else "no")
print("unclaimed paths:", len(unclaimed))
for p in unclaimed[:40]: print("  ", p)
