#!/usr/bin/env python3
"""Assemble ARCHITECTURE.md from $OUT/survey/*.md (+ scope.md, open-questions.md, review-log.md).

The survey files are the source of truth; ARCHITECTURE.md is generated and never hand-edited.
Usage: assemble.py <OUT> --sha <sha> [--repo <name>] [--focus <text>] [--cap 160]
Prints warnings (dangling names, duplicate seams with different mechanisms, long cells) to stderr.
"""
import argparse, datetime, hashlib, os, re, sys, glob

MECHS = {"http","grpc","queue/topic","db-read","db-write","file/object-store",
         "cron/workflow-trigger","shared-library","env/config","external-saas"}

def parse_tables(text):
    """-> {heading: [row dict]} for '### Heading' blocks holding one markdown table."""
    out, head, cols = {}, None, None
    for line in text.splitlines():
        m = re.match(r"^###\s+(.+?)\s*$", line)
        if m: head, cols = m.group(1).strip().lower(), None; out.setdefault(head, []); continue
        if head is None or not line.startswith("|"): continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cols is None: cols = [c.lower() for c in cells]; continue
        if all(re.fullmatch(r":?-+:?", c) for c in cells): continue
        if len(cells) < len(cols): cells += [""] * (len(cols) - len(cells))
        out[head].append(dict(zip(cols, cells)))
    return out

def sid(s): return re.sub(r"[^A-Za-z0-9_]", "_", s.strip("`* ")).strip("_") or "x"
def norm(s): return s.strip("`* ").lower()
def eid(a, b, m): return "E-" + hashlib.sha1(f"{norm(a)}|{norm(b)}|{m}".encode()).hexdigest()[:5]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out"); ap.add_argument("--sha", required=True)
    ap.add_argument("--repo", default=os.path.basename(os.getcwd()))
    ap.add_argument("--focus", default="whole repo"); ap.add_argument("--cap", type=int, default=160)
    a = ap.parse_args()
    OUT = a.out; warn = lambda *x: print("WARN:", *x, file=sys.stderr)

    units, edges, stores, externals = [], {}, {}, {}
    for f in sorted(glob.glob(os.path.join(OUT, "survey", "*.md"))):
        src = os.path.basename(f)[:-3]
        t = parse_tables(open(f).read())
        for r in t.get("unit", []): r["_src"] = src; units.append(r)
        for r in t.get("edges", []):
            if not r.get("from") or not r.get("to"): continue
            m = r.get("mechanism", "").strip("` ")
            if m not in MECHS: warn(f"{src}: mechanism '{m}' not in allowed set ({r['from']}→{r['to']})")
            k = (norm(r["from"]), norm(r["to"]), m)
            e = edges.setdefault(k, {"id": eid(r["from"], r["to"], m), "from": r["from"].strip("`* "),
                                     "to": r["to"].strip("`* "), "mechanism": m, "seam": [], "evidence": [], "src": []})
            if r.get("seam") and r["seam"] not in e["seam"]: e["seam"].append(r["seam"])
            for ev in re.split(r";\s*", r.get("evidence", "")):
                if ev and ev not in e["evidence"] and len(e["evidence"]) < 3: e["evidence"].append(ev)
            if src not in e["src"]: e["src"].append(src)
        for r in t.get("data stores", []):
            if not r.get("store"): continue
            s = stores.setdefault(norm(r["store"]), {"store": r["store"].strip("`* "), "kind": r.get("kind", ""),
                                                      "owner": [], "readers": [], "writers": [], "evidence": []})
            acc = r.get("access", "").lower()
            tgt = s["owner"] if "own" in acc else (s["writers"] if "write" in acc else s["readers"])
            if src not in tgt: tgt.append(src)
            if r.get("evidence") and len(s["evidence"]) < 3: s["evidence"].append(r["evidence"])
        for r in t.get("external services", []):
            if not r.get("service"): continue
            x = externals.setdefault(norm(r["service"]), {"service": r["service"].strip("`* "), "callers": [],
                                                           "mechanism": r.get("mechanism", ""), "purpose": r.get("purpose", ""), "evidence": []})
            if src not in x["callers"]: x["callers"].append(src)
            if r.get("evidence") and len(x["evidence"]) < 3: x["evidence"].append(r["evidence"])

    unit_names = {norm(u["name"]) for u in units}
    dangling = {}
    for k, e in edges.items():
        for side in ("from", "to"):
            n = norm(e[side])
            if n not in unit_names and n not in stores and n not in externals:
                dangling[n] = e[side]
                warn(f"dangling name '{e[side]}' in edge {e['id']} (not a unit, store or external service)")
    pairs = {}
    for (f, t, m) in edges: pairs.setdefault((f, t), set()).add(m)
    for (f, t), ms in pairs.items():
        if len(ms) > 1: warn(f"{f}→{t} reported with several mechanisms {sorted(ms)} — check they are distinct seams")
    for u in units:
        for c, v in u.items():
            if len(v) > a.cap: warn(f"long cell ({len(v)}>{a.cap}) unit {u['name']} col {c}")
    for e in edges.values():
        for c in ("seam", "evidence"):
            if len("; ".join(e[c])) > a.cap: warn(f"long cell ({len('; '.join(e[c]))}>{a.cap}) edge {e['id']} col {c}")
    for u in units:
        if not any(norm(u["name"]) in (k[0], k[1]) for k in edges): warn(f"unit {u['name']} has no edges — mark it isolated in scope.md or survey it again")

    def read(p, default=""):
        p = os.path.join(OUT, p); return open(p).read().strip() if os.path.exists(p) else default
    L = []
    L += [f"# Architecture map — {a.repo}", "",
          "Generated by `map-architecture` from `survey/*.md`. Do not hand-edit: fix the survey row, re-run assemble.", "",
          "## 1. Scope", "", f"- repo: `{a.repo}`", f"- commit: `{a.sha}`",
          f"- date: {datetime.date.today().isoformat()}", f"- focus: {a.focus}", "", read("scope.md"), ""]
    L += ["## 2. Subsystems", "", "| id | group | path | runtime | deployed how | purpose | evidence |", "|---|---|---|---|---|---|---|"]
    for u in sorted(units, key=lambda u: (u.get("group", ""), u["name"])):
        L.append(f"| {u['name']} | {u.get('group','')} | {u.get('path','')} | {u.get('runtime','')} | {u.get('deployed how','')} | {u.get('purpose','')} | {u.get('evidence','')} |")
    L += ["", "## 3. Edges", "", "One row = one mechanism between one pair. Direction is from→to. `source` names the survey file that owns the row.", "",
          "| id | from | to | mechanism | seam | evidence | source |", "|---|---|---|---|---|---|---|"]
    for e in sorted(edges.values(), key=lambda e: (norm(e["from"]), norm(e["to"]), e["mechanism"])):
        L.append(f"| {e['id']} | {e['from']} | {e['to']} | {e['mechanism']} | {'; '.join(e['seam'])} | {'; '.join(e['evidence'])} | {', '.join(e['src'])} |")
    L += ["", "## 4. Data stores", "", "| store | kind | owner | writers | readers | evidence |", "|---|---|---|---|---|---|"]
    for s in sorted(stores.values(), key=lambda s: norm(s["store"])):
        L.append(f"| {s['store']} | {s['kind']} | {', '.join(s['owner']) or 'unverified'} | {', '.join(s['writers'])} | {', '.join(s['readers'])} | {'; '.join(s['evidence'])} |")
    L += ["", "## 5. External services", "", "| service | callers | mechanism | purpose | evidence |", "|---|---|---|---|---|"]
    for x in sorted(externals.values(), key=lambda x: norm(x["service"])):
        L.append(f"| {x['service']} | {', '.join(x['callers'])} | {x['mechanism']} | {x['purpose']} | {'; '.join(x['evidence'])} |")

    # --- mermaid, from the same tables ---
    M = ["```mermaid", "flowchart LR"]
    groups = {}
    for u in units: groups.setdefault(u.get("group", "") or "ungrouped", []).append(u)
    for g, us in sorted(groups.items()):
        M.append(f'  subgraph {sid(g)}["{g}"]')
        for u in us: M.append(f'    {sid(u["name"])}["{u["name"]}"]')
        M.append("  end")
    for s in stores.values(): M.append(f'  {sid(s["store"])}[("{s["store"]}")]')
    for n in dangling.values(): M.append(f'  {sid(n)}["{n} ?"]')
    if externals:
        M.append('  subgraph External["External services"]')
        for x in externals.values(): M.append(f'    {sid(x["service"])}["{x["service"]}"]')
        M += ["  end", "  style External stroke-dasharray: 5 5"]
    for (f, t), ms in sorted(pairs.items()):
        ef = next(e for k, e in edges.items() if k[0] == f and k[1] == t)
        M.append(f'  {sid(ef["from"])} -->|{", ".join(sorted(ms))}| {sid(ef["to"])}')
    M.append("```")
    L += ["", "## 6. Diagram", ""] + M
    L += ["", "## 7. Unverified / open questions", "", read("open-questions.md", "_none_"),
          "", "## 8. Review log", "", read("review-log.md", "_no rounds yet_"), ""]
    open(os.path.join(OUT, "ARCHITECTURE.md"), "w").write("\n".join(L))
    print(f"units={len(units)} edges={len(edges)} stores={len(stores)} externals={len(externals)} -> {OUT}/ARCHITECTURE.md")

if __name__ == "__main__": main()
