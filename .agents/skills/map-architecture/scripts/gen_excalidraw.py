#!/usr/bin/env python3
"""Render the mermaid block in ARCHITECTURE.md §6 as an editable .excalidraw file.
Usage: gen_excalidraw.py <ARCHITECTURE.md> <out.excalidraw>
Subgraphs -> frames laid out as columns (in order of appearance; stores in their own column; External last).
Nodes -> rectangles (stores -> ellipses, external -> dashed). One bound arrow per (from,to) pair, labelled."""
import re, json, sys, random
src, dst = sys.argv[1], sys.argv[2]
md = open(src).read()
i = md.index("```mermaid") + 10
mer = md[i: md.index("```", i)]
groups, gtitle, nodes, edges, cur = {}, {}, {}, {}, None
node_re = re.compile(r'^\s*([A-Za-z0-9_]+)(\[\("|\[)(.*?)("\)\]|\])\s*$')
edge_re = re.compile(r'^\s*([A-Za-z0-9_]+)\s*(<-->|-->|-\.->)\s*\|([^|]*)\|\s*([A-Za-z0-9_]+)\s*$')
for l in mer.splitlines():
    if not l.strip() or l.strip().startswith(("flowchart", "style")): continue
    m = re.match(r'^\s*subgraph\s+([A-Za-z0-9_]+)(?:\["(.*)"\])?', l)
    if m: cur = m.group(1); groups[cur] = []; gtitle[cur] = m.group(2) or cur; continue
    if l.strip() == "end": cur = None; continue
    m = node_re.match(l)
    if m:
        nid, op, label = m.group(1), m.group(2), m.group(3)
        kind = "store" if op == '[("' else ("external" if cur == "External" else "box")
        nodes[nid] = (label, kind)
        groups.setdefault(cur or "_stores", []).append(nid); continue
    m = edge_re.match(l)
    if m:
        a, op, label, b = m.groups()
        e = edges.setdefault((a, b), {"label": label.strip(), "dashed": op == "-.->", "bi": op == "<-->"}); continue
    print("unparsed:", l, file=sys.stderr)

W, H, VG, COLW = 240, 70, 30, 520
order = [g for g in groups if g not in ("_stores", "External")] + [g for g in ("_stores", "External") if g in groups]
pos, frames = {}, []
for ci, g in enumerate(order):
    x, y = 100 + ci * COLW, 100
    ids = groups[g]
    if not ids: continue
    for nid in ids: pos[nid] = (x, y); y += H + VG
    if g != "_stores": frames.append((g, x - 30, 40, W + 60, y - VG - 40 + 40))
rnd = random.Random(7); els = []
def base(eid, typ, x, y, w, h, **kw):
    d = {"id": eid, "type": typ, "x": x, "y": y, "width": w, "height": h, "angle": 0, "strokeColor": "#1e1e1e",
         "backgroundColor": "transparent", "fillStyle": "solid", "strokeWidth": 2, "strokeStyle": "solid", "roughness": 1,
         "opacity": 100, "groupIds": [], "frameId": None, "roundness": {"type": 3}, "seed": rnd.randint(1, 2**30),
         "version": 1, "versionNonce": rnd.randint(1, 2**30), "updated": 1, "isDeleted": False, "boundElements": [],
         "link": None, "locked": False}
    d.update(kw); return d
frame_ids = {}
for g, fx, fy, fw, fh in frames:
    frame_ids[g] = f"frame-{g}"
    els.append(base(frame_ids[g], "frame", fx, fy, fw, fh, name=gtitle.get(g, g), roundness=None, boundElements=None))
palette = ["#a5d8ff", "#b2f2bb", "#ffec99", "#d0bfff", "#ffd8a8", "#e9ecef", "#c3fae8", "#fcc2d7"]
gcolor = {g: (palette[i % len(palette)] if g not in ("_stores", "External") else ("#ffc9c9" if g == "_stores" else "transparent")) for i, g in enumerate(order)}
node_group = {nid: g for g, ids in groups.items() for nid in ids}
for nid, (label, kind) in nodes.items():
    x, y = pos[nid]; g = node_group[nid]
    typ = "ellipse" if kind == "store" else "rectangle"
    box = base(f"n-{nid}", typ, x, y, W, H, backgroundColor=gcolor.get(g, "transparent"),
               strokeStyle="dashed" if kind == "external" else "solid",
               roundness={"type": 2} if typ == "ellipse" else {"type": 3}, frameId=frame_ids.get(g))
    txt = base(f"t-{nid}", "text", x + 10, y + 12, W - 20, H - 24, text=label, originalText=label, fontSize=14, fontFamily=2,
               textAlign="center", verticalAlign="middle", lineHeight=1.25, baseline=14, containerId=f"n-{nid}",
               roundness=None, boundElements=None, frameId=frame_ids.get(g))
    box["boundElements"].append({"type": "text", "id": f"t-{nid}"}); els += [box, txt]
def center(n): x, y = pos[n]; return (x + W / 2, y + H / 2)
def port(n, toward):
    (cx, cy), (tx, ty) = center(n), center(toward); x, y = pos[n]
    if abs(tx - cx) > W: return (x + W if tx > cx else x, cy)
    return (cx, y + H if ty > cy else y)
byid = {e["id"]: e for e in els}
for (a, b), e in edges.items():
    if a not in pos or b not in pos: print("missing node", a, b, file=sys.stderr); continue
    sx, sy = port(a, b); ex, ey = port(b, a); aid = f"a-{a}-{b}"
    arrow = base(aid, "arrow", sx, sy, ex - sx, ey - sy, points=[[0, 0], [ex - sx, ey - sy]],
                 startBinding={"elementId": f"n-{a}", "focus": 0, "gap": 4}, endBinding={"elementId": f"n-{b}", "focus": 0, "gap": 4},
                 startArrowhead="arrow" if e["bi"] else None, endArrowhead="arrow",
                 strokeStyle="dashed" if e["dashed"] else "solid", strokeWidth=1, roundness={"type": 2})
    lt = base(f"l-{aid}", "text", (sx + ex) / 2 - 50, (sy + ey) / 2 - 10, 100, 20, text=e["label"], originalText=e["label"],
              fontSize=11, fontFamily=2, textAlign="center", verticalAlign="middle", lineHeight=1.25, baseline=11,
              containerId=aid, roundness=None, boundElements=None)
    arrow["boundElements"].append({"type": "text", "id": lt["id"]})
    byid[f"n-{a}"]["boundElements"].append({"id": aid, "type": "arrow"}); byid[f"n-{b}"]["boundElements"].append({"id": aid, "type": "arrow"})
    els += [arrow, lt]
lg = "Generated from ARCHITECTURE.md §6. Rectangles = subsystems, ellipses = data stores, dashed = external services; arrow labels = mechanisms."
els.append(base("legend", "text", 100, 10, 1400, 24, text=lg, originalText=lg, fontSize=14, fontFamily=2, textAlign="left",
                verticalAlign="top", lineHeight=1.25, baseline=14, containerId=None, roundness=None, boundElements=None))
json.dump({"type": "excalidraw", "version": 2, "source": "https://excalidraw.com", "elements": els,
           "appState": {"viewBackgroundColor": "#ffffff", "gridSize": None}, "files": {}}, open(dst, "w"))
print(f"nodes={len(nodes)} groups={len(groups)} arrows={len(edges)} elements={len(els)}")
