---
name: wiki-note
description: Research a topic and file it as a page in the Obsidian vault's wiki
---

Save a note into the wiki in the Obsidian vault.

**Topic:** If `$ARGUMENTS` is provided and non-empty, treat it as the topic. Otherwise, derive the topic from the current conversation.

1. **Gather the content.** When the topic comes from the conversation, use what was established there. Otherwise research it: search the web, read relevant files, or use other available tools.

2. **Write a clean, concise Markdown page**: a practical reference that is easy to scan, using headings, lists, tables and code blocks as they fit.

3. **File it with the `wiki` skill**, following its **file** operation. That operation decides whether to create a page or update an existing one, and it updates the wiki's index and log.

4. **Confirm** with the full path of the page and a brief summary of what was written.
