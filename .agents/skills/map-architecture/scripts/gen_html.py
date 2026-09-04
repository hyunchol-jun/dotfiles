#!/usr/bin/env python3
"""Render ARCHITECTURE.md as a single self-contained HTML page.
Usage: gen_html.py <ARCHITECTURE.md> <out.html>
The §6 mermaid block is drawn in the browser (mermaid.js from cdn.jsdelivr.net, so viewing needs network);
the §2–§5 tables are rendered below it so evidence stays next to the picture. Nothing else is embedded."""
import html, re, sys
src, dst = sys.argv[1], sys.argv[2]
md = open(src).read()
title = md.splitlines()[0].lstrip("# ").strip()
i = md.index("```mermaid") + 10
mer = md[i: md.index("```", i)].strip()

def table_html(lines):
    rows = [[c.strip() for c in l.strip().strip("|").split("|")] for l in lines]
    rows = [r for r in rows if not all(re.fullmatch(r":?-+:?", c) for c in r)]
    if not rows: return ""
    cell = lambda c: re.sub(r"`([^`]*)`", r"<code>\1</code>", html.escape(c))
    out = ["<table><thead><tr>" + "".join(f"<th>{cell(c)}</th>" for c in rows[0]) + "</tr></thead><tbody>"]
    for r in rows[1:]: out.append("<tr>" + "".join(f"<td>{cell(c)}</td>" for c in r) + "</tr>")
    return "\n".join(out) + "</tbody></table>"

sections = []  # (heading, html) for ## sections except 6
for m in re.finditer(r"^## (.+?)$\n(.*?)(?=^## |\Z)", md, re.M | re.S):
    head, body = m.group(1).strip(), m.group(2)
    if head.startswith("6."): continue
    parts, buf = [], []
    def flush():
        if buf: parts.append(table_html(buf)); buf.clear()
    for l in body.splitlines():
        if l.startswith("|"): buf.append(l)
        else:
            flush()
            if l.strip(): parts.append(f"<p>{re.sub(r'`([^`]*)`', r'<code>\\1</code>', html.escape(l.strip()))}</p>")
    flush()
    sections.append((head, "\n".join(parts)))

nav = " · ".join(f'<a href="#s{n}">{html.escape(h)}</a>' for n, (h, _) in enumerate(sections))
body = "\n".join(f'<section id="s{n}"><h2>{html.escape(h)}</h2>{b}</section>' for n, (h, b) in enumerate(sections))
page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title>
<style>
 body{{font:14px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;margin:0;padding:24px;color:#1e1e1e;background:#fff}}
 h1{{font-size:20px;margin:0 0 4px}} h2{{font-size:16px;margin:32px 0 8px;border-bottom:1px solid #ddd;padding-bottom:4px}}
 nav{{color:#666;margin-bottom:16px}} nav a{{color:#0366d6;text-decoration:none}}
 #diagram{{border:1px solid #ddd;border-radius:6px;padding:12px;overflow:auto;background:#fafafa}}
 #diagram svg{{max-width:none;height:auto}}
 .legend{{color:#666;font-size:12px;margin:6px 0 0}}
 table{{border-collapse:collapse;width:100%;font-size:13px;margin:8px 0}} th,td{{border:1px solid #ddd;padding:4px 8px;text-align:left;vertical-align:top}}
 th{{background:#f3f4f6;position:sticky;top:0}} code{{background:#f3f4f6;padding:1px 4px;border-radius:3px;font-size:12px}}
 details{{margin:8px 0}} pre{{background:#f3f4f6;padding:12px;overflow:auto;border-radius:6px}}
</style></head><body>
<h1>{html.escape(title)}</h1>
<nav><a href="#diagram">Diagram</a> · {nav}</nav>
<div id="diagram"><pre class="mermaid">{html.escape(mer)}</pre></div>
<p class="legend">Generated from ARCHITECTURE.md §6. Boxes = subsystems, cylinders = data stores, dashed group = external services; arrow labels = mechanisms.
If the diagram does not render, you are offline: the source is in the details below.</p>
<details><summary>Mermaid source</summary><pre>{html.escape(mer)}</pre></details>
{body}
<script type="module">
 import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
 mermaid.initialize({{startOnLoad:true,theme:"neutral",flowchart:{{useMaxWidth:false}}}});
</script>
</body></html>"""
open(dst, "w").write(page)
print(f"sections={len(sections)} mermaid-lines={len(mer.splitlines())} -> {dst}")
