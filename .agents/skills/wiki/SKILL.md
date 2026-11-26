---
name: wiki
description: The user's personal knowledge wiki in their Obsidian vault. Use to ingest a source into it ("add this to my wiki"), answer a question from it ("what does my wiki say about X"), file a finished answer or note into it, or lint it, and whenever knowledge from a source or a research answer is about to be saved anywhere else.
---

The wiki is a compounding knowledge base that you maintain for the user. The user curates sources and asks questions; you write and update every page. Each new source improves the existing pages.

## Where it runs

Before any operation, run `hostname` and check that the vault root exists. The wiki is available when the vault root is a directory and the hostname does not start with `mini1`. Anywhere else, tell the user the wiki is not used on this machine and stop; save nothing in its place.

## Where things are

The vault root is the "Obsidian vault path" in the user's global instructions (`~/.claude/CLAUDE.md`).

| Path in the vault | Role | Who writes it |
| --- | --- | --- |
| `raw/` | Original sources: articles, PDFs, transcripts. Immutable once saved. | You save them; nobody edits them |
| `raw/assets/` | Images belonging to sources | You |
| `wiki/` | Topic pages, one topic per page | You |
| `wiki/index.md` | Catalogue of every page | You, on every change |
| `wiki/log.md` | Append-only record of every operation | You, on every operation |
| everything else | Legacy notes, daily notes, diary | The user. Read them as sources where they are. |

## Wiki or Claude memory

| The information is... | It goes to |
| --- | --- |
| Learned from a source, or something the user would look up later | A wiki page |
| A preference or correction about how you should work | Claude memory |
| A warning you should raise unprompted in a future session | Claude memory: the trigger and a pointer to the wiki page that holds the detail |
| An identifier: account number, login, ticket or reference number, ID number | Claude memory. The wiki names the thing by its role ("the TFSA at IBKR"). |

The wiki is pushed to GitHub and the rules in this skill are public, so identifiers and personal details stay in Claude memory.

## Operations

Read [`rules.md`](rules.md) and follow the section for the operation the user asked for: **ingest**, **query**, **file** or **lint**.
