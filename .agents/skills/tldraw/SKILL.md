---
name: tldraw
description: Generate editable tldraw diagram files (.tldr). Use when the user asks for a diagram, flowchart, or sketch they can open and edit in tldraw specifically. If no tool is named, prefer the excalidraw skill instead.
---

# tldraw diagrams

Write a `.tldr` file (plain JSON) the user can open at tldraw.com (File → Open, or drag the file onto the canvas) or in the tldraw VS Code extension. The file is local and self-contained.

## The one strategy that makes this reliable

Do NOT write the current tldraw schema — it changes often (e.g. `text` became `richText`) and hand-written current-format files break. Instead, write the **older schemaVersion-1 format** below. tldraw runs migrations on every file it opens and upgrades old files automatically; this exact format ships as example/test files inside the tldraw repo itself, so migration support for it is permanent. When the user re-saves from tldraw, the app writes the current format — that's fine.

Never edit a `.tldr` that tldraw has re-saved by hand-patching JSON; regenerate from your own old-format source or let the user edit in-app.

## Process

1. Plan the layout: assign every shape (x, y) before writing JSON. Boxes ≥ 160×70, gaps ≥ 120px horizontal / 100px vertical.
2. Copy `examples/minimal.tldr` from this skill directory as the starting skeleton — the `schema` block must be byte-for-byte identical; only edit `records`.
3. Write to the project (e.g. `docs/diagrams/<name>.tldr`).
4. Validate: `python3 -m json.tool <file> > /dev/null`.
5. Tell the user: drag the file onto tldraw.com, or File → Open.

## Records

`records` must contain exactly one `document` and one `page`, then shapes:

```json
{ "gridSize": 10, "name": "", "meta": {}, "id": "document:document", "typeName": "document" },
{ "meta": {}, "id": "page:page", "name": "Page 1", "index": "a1", "typeName": "page" }
```

Every shape record shares this base:

```json
{
  "id": "shape:box1", "typeName": "shape", "type": "geo",
  "x": 100, "y": 100, "rotation": 0,
  "isLocked": false, "opacity": 1, "meta": {},
  "parentId": "page:page", "index": "a1",
  "props": { }
}
```

- `id` must start with `shape:`; use readable suffixes (`shape:box-api`).
- `index` is the z-order: unique per page, ordered like `"a1" < "a2" < "a3"`. Just number shapes `a1, a2, a3…`; put arrows after boxes.

## Shape types (props)

**`geo`** — boxes, ellipses, diamonds:
```json
"props": {
  "w": 160, "h": 70, "geo": "rectangle",
  "color": "blue", "labelColor": "black", "fill": "semi",
  "dash": "draw", "size": "m", "font": "draw",
  "text": "Client", "align": "middle", "verticalAlign": "middle",
  "growY": 0, "url": ""
}
```
`geo`: `rectangle`, `ellipse`, `diamond`, `triangle`, `hexagon`, `cloud`, `star`. Text lives directly in the shape via `text` — no separate label element needed (simpler than Excalidraw).

**`text`** — standalone text:
```json
"props": { "color": "black", "size": "m", "w": 300, "font": "draw", "align": "start", "autoSize": true, "scale": 1, "text": "Title" }
```

**`arrow`** — bind to shapes by id; tldraw computes the endpoints:
```json
"props": {
  "dash": "draw", "size": "m", "fill": "none",
  "color": "black", "labelColor": "black", "bend": 0,
  "start": { "type": "binding", "boundShapeId": "shape:box1",
             "normalizedAnchor": { "x": 0.5, "y": 0.5 }, "isExact": false },
  "end":   { "type": "binding", "boundShapeId": "shape:box2",
             "normalizedAnchor": { "x": 0.5, "y": 0.5 }, "isExact": false },
  "arrowheadStart": "none", "arrowheadEnd": "arrow",
  "text": "HTTP", "font": "draw"
}
```
Give the arrow an `x`/`y` roughly between the two shapes (used as a fallback anchor). For an unbound endpoint use `{ "type": "point", "x": 0, "y": 0 }` (relative to the arrow's x/y). Arrow labels go in `props.text`.

**`note`** — sticky note, text goes in `props.text`: `"props": { "color": "yellow", "size": "m", "font": "draw", "align": "middle", "growY": 0, "url": "", "text": "..." }`. Prefer `geo` shapes for diagram nodes; use `note` only when the user asks for sticky notes.

## Colors

Named enum only — hex values are invalid and fail validation: `black`, `grey`, `blue`, `light-blue`, `violet`, `light-violet`, `red`, `light-red`, `green`, `light-green`, `yellow`, `orange`. Fill styles: `none`, `semi` (tinted), `solid`, `pattern`.

## Reference

`examples/minimal.tldr`: correct schema block + two geo boxes joined by a labeled bound arrow. Schema and binding format verified against fixtures in the tldraw repo (`packages/tldraw/src/lib/tools/selection-logic/selection.tldr`).
