---
name: obsidian-note
description: Research a topic and save a well-formatted Markdown note to the Obsidian vault
---

Save a well-formatted Markdown note to the Obsidian vault at `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/vimwiki/`.

**Topic:** If `$ARGUMENTS` is provided and non-empty, treat it as the topic to research and write about. Otherwise, derive the topic from the current conversation context.

Follow these steps:

1. **Research the topic** — search the web, read relevant files in the current project, or use any other available tools to gather accurate, up-to-date information.

2. **Write a clean, concise Markdown document** — use headings, bullet points, numbered lists, tables, and code blocks as appropriate. Aim for a practical reference that is easy to scan. Do not add YAML frontmatter to the note itself.

3. **Choose a kebab-case filename** based on the topic (e.g., `docker-cheatsheet.md`, `git-rebase-guide.md`).

4. **Save the file** to `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/vimwiki/<filename>.md`.

5. **Confirm** by printing the full path of the saved file and a brief summary of what was written.
