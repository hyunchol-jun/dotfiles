---
name: excalidraw
description: Generate editable Excalidraw diagram files (.excalidraw). Use when the user asks for a diagram, flowchart, or architecture sketch they can open and edit in Excalidraw — or asks for an editable, shareable local diagram file without naming a specific tool (Excalidraw is the default; use the tldraw skill only when they say tldraw).
---

# Excalidraw diagrams

Write a `.excalidraw` file (plain JSON) the user can open at excalidraw.com, in the Excalidraw VS Code extension, or the desktop app. The file is self-contained and local — they can send it to anyone.

## Process

1. Plan the layout first: assign every shape an (x, y) on a grid before writing JSON. Boxes ≥ 160×70, horizontal gap ≥ 120, vertical gap ≥ 100. Overlapping shapes are the #1 quality failure.
2. Write the file to the current project (e.g. `docs/diagrams/<name>.excalidraw`) unless the user names a location.
3. Validate: `python3 -m json.tool <file> > /dev/null`.
4. Tell the user: open excalidraw.com → hamburger menu → Open, and pick the file.

## File skeleton

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "https://excalidraw.com",
  "elements": [],
  "appState": { "viewBackgroundColor": "#ffffff", "gridSize": null },
  "files": {}
}
```

`files` stays `{}` unless embedding images. Excalidraw fills defaults for missing element fields on load (`restoreElements`), but include the full field set below anyway — some older builds are stricter.

## Fields every element needs

```json
{
  "id": "unique-string",
  "type": "rectangle",
  "x": 100, "y": 100, "width": 160, "height": 70,
  "angle": 0,
  "strokeColor": "#1e1e1e", "backgroundColor": "transparent",
  "fillStyle": "solid", "strokeWidth": 2, "strokeStyle": "solid",
  "roughness": 1, "opacity": 100,
  "groupIds": [], "frameId": null,
  "roundness": { "type": 3 },
  "seed": 1, "version": 1, "versionNonce": 1, "updated": 1,
  "isDeleted": false, "boundElements": null, "link": null, "locked": false
}
```

- `id`: any unique string. Use readable ids (`box-api`, `arrow-1`) — you will cross-reference them in bindings.
- `seed` / `versionNonce`: any positive integers; vary them per element so the hand-drawn jitter differs.
- `roundness`: `{ "type": 3 }` for rectangles, `{ "type": 2 }` for lines/arrows/other shapes, `null` for sharp corners and text.

## Element types

**Containers** — `rectangle`, `ellipse`, `diamond` (decision nodes). Style with `backgroundColor` + `fillStyle: "solid"`.

**Text label inside a shape** — two-way link, both sides required:
1. Text element: `"type": "text"` with `containerId: "<shape-id>"`, plus `text`, `originalText` (same value), `fontSize: 20`, `fontFamily: 1` (hand-drawn; 2 = normal, 3 = code), `textAlign: "center"`, `verticalAlign: "middle"`, `lineHeight: 1.25`, `baseline: 18`.
2. Container gets `"boundElements": [{ "type": "text", "id": "<text-id>" }]`.

Rough text width = `0.6 × fontSize × char_count`; Excalidraw remeasures on load, estimates just need to be sane. Standalone text (no container): same fields, `containerId: null`, `textAlign: "left"`.

**Arrows** — `"type": "arrow"`, position at the source shape's edge:
```json
{
  "type": "arrow", "x": 265, "y": 135, "width": 150, "height": 0,
  "points": [[0, 0], [150, 0]],
  "startBinding": { "elementId": "box-a", "focus": 0, "gap": 5 },
  "endBinding":   { "elementId": "box-b", "focus": 0, "gap": 5 },
  "startArrowhead": null, "endArrowhead": "arrow",
  "roundness": { "type": 2 }
}
```
`points` are relative to the arrow's own (x, y). Both bound shapes must list the arrow back in their `boundElements`: `{ "id": "<arrow-id>", "type": "arrow" }`. Missing back-references = arrows that don't follow shapes when dragged. To label an arrow, bind a text element to it the same way as container labels.

## Palette

Stroke `#1e1e1e`. Backgrounds (pastel set matching the app's picker): blue `#a5d8ff`, green `#b2f2bb`, yellow `#ffec99`, red `#ffc9c9`, violet `#d0bfff`, or `"transparent"`.

## Reference

`examples/minimal.excalidraw` in this skill directory: two labeled boxes joined by a labeled bound arrow. Copy its structure.

## Escape hatch

If the diagram is huge or auto-layout matters more than hand-tuned positions, generate Mermaid instead and tell the user to use excalidraw.com → More tools → Mermaid to Excalidraw. Converts to fully editable shapes. (This is Excalidraw-only; tldraw has no Mermaid import.)
