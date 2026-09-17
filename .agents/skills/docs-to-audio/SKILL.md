---
name: docs-to-audio
description: Convert Markdown or HTML documentation into chaptered audio with a narration script. Use for listening to documentation, guided spoken explanations, or faithful document narration.
---

# Docs to audio

Default to a guided explanation: retain the document's substantive coverage while adapting it for listening. Offer faithful reading when exact wording matters. A target duration is a preference, not permission to silently discard requirements; explain a coverage/runtime conflict before abridging.

## Prepare the narration

1. Read the supplied files completely, preserving their section order. For HTML, extract the main article and exclude navigation, scripts, styles, and repeated page chrome. Inspect the source if extraction loses tables, code, or image descriptions. For script-rendered pages, use an available browser skill when needed. Ask for a source only if none was supplied or identifiable.
2. Write one UTF-8 plain-text narration file per chapter, normally following major headings. Keep the source language unless the user requests translation. Default to a single narrator and no music.
3. In guided mode, explain terminology at first use, turn tables into meaningful comparisons, and describe code's purpose, inputs, outputs, and important behavior. Preserve conditions, negations, numbers, units, version constraints, warnings, and exceptions. Keep exact commands and identifiers in a companion notes file when they are impractical to speak. Clearly introduce added analogies or examples as explanatory additions; ground technical claims in the source. Describe diagrams only when their content is available; record inaccessible visuals as coverage gaps.
4. In faithful mode, preserve prose wording and order. Speak headings and list items naturally. Represent links by their labels, with destinations in companion notes. Read code or tables in full where practicable; flag material that cannot be conveyed faithfully and agree on its treatment rather than silently omit it.
5. Save `coverage.md`, mapping every substantive source section to its narration chapter and recording adaptations, omissions, and uncertain interpretations. Compare scripts against the sources before synthesis. Keep narration files free of Markdown syntax and production instructions that would be spoken aloud.

## Render

Choose an output folder alongside the document or in the user's requested artifact location; preserve the sources. Save scripts and coverage there. Create `chapters.json`:

```json
{"title":"Architecture walkthrough","chapters":[{"title":"Overview","text_file":"scripts/01-overview.txt"},{"title":"Data flow","text_file":"scripts/02-data-flow.txt"}]}
```

Paths are relative to the manifest. Each script should include its spoken chapter heading.

On macOS, use the bundled local renderer when no voice provider was requested. It requires `say`, `ffmpeg`, and `ffprobe`, and uses the system voice unless `--voice` is provided. Run `say -v '?'` to find an installed voice matching the narration language. Local speech synthesis does not upload scripts; script preparation still occurs in the current assistant session.

```bash
python3 <skill-dir>/scripts/render_audio.py <output-dir>/chapters.json --out <output-dir>/audio --rate 175
```

Use a new audio output directory for rerenders. If a dependency is missing, identify it and use an available suitable backend; do not claim that a script alone is finished audio. For requested cloud voices or non-macOS environments, read [Cloud narration](references/cloud.md). Preserve existing provider authorization and preferences.

## Verify and deliver

The renderer validates nonempty audio, measures duration, joins chapters, and writes chapter start times to `index.json`. Check that chapter count and order match the manifest and that coverage gaps are explicit. Listen to representative passages if an audio inspection tool is available, especially identifiers and language changes. Otherwise report that validation was structural, without claiming pronunciation or listening quality was verified.

Return links to the combined MP3, chapter folder, narration scripts, and coverage notes. State the mode, speech backend, duration, and any material coverage or verification limits. Generate actual audio when the source is available; do not stop after drafting the script.
