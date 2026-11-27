# Wiki rules

The operations of the [`wiki`](SKILL.md) skill. Paths are relative to the vault root.

## Page conventions

- **One topic per page**, in `wiki/`, flat, with a kebab-case filename (`korea-five-year-tax-rule.md`).
- **Start with a `# Title`, then one or two sentences** stating what the page covers. No YAML frontmatter.
- **Link related pages** with relative markdown links: `[Korea five-year rule](korea-five-year-tax-rule.md)`.
- **End with a `## Sources` section** listing what the page was built from: files in `raw/`, URLs, legacy notes, or "Claude session, <date>".
- **Date anything that can go stale** ("as of 2026-11-27"), and mark a claim as unverified when no source confirms it.
- **Three kinds of page:** a *source summary* (one per ingested source), a *topic page* (a concept, entity or ongoing matter, fed by many sources), and a *filed answer* (a question the user asked, worth keeping).

`wiki/index.md` lists every page under a category heading, one line each: `- [Title](file.md): one-line summary`.

`wiki/log.md` gains one entry per operation, newest last:

```markdown
## [2026-11-27] ingest | Title of the source
Pages created: ... Pages updated: ...
```

The operation word is `ingest`, `query`, `file`, `lint` or `setup`. `grep "^## \[" wiki/log.md | tail -5` shows the latest entries.

## Ingest

Adds one source. Take sources one at a time unless the user asks for a batch.

1. **Save the original into `raw/`** as markdown or the original file, named `YYYY-MM-DD-short-title.ext`. For a URL, save the page text with the URL on the first line. A legacy note in the vault is already saved: use it in place.
2. **Read it in full, then tell the user the key takeaways** and ask what to emphasise. Wait for the answer; the user's emphasis shapes the pages.
3. **Read `wiki/index.md`** and open every page the source bears on.
4. **Write the source summary page.**
5. **Update every related topic page**: add what is new, revise what the source changes, and where it contradicts a page, keep both claims and flag the contradiction with their sources. Create a topic page for any concept the source treats in depth that has none.
6. **Update `wiki/index.md` and append the log entry.**
7. **Run the lint check below if it is due**, then commit.

Done when every page the source bears on reflects it, each new page is in the index and linked from at least one other page, and the log entry names every page touched.

## Query

Answers a question from the wiki.

1. Read `wiki/index.md`, then open the pages that bear on the question.
2. Answer from those pages and name each page you relied on. Where the wiki is silent or thin, say so, and say what source would fill the gap.
3. If the answer took real synthesis, offer to file it.

A question the wiki cannot answer is a prompt to find a source and ingest it, with the user's agreement.

## File

Saves a finished answer, research result or conversation into the wiki.

1. Read `wiki/index.md`. If a page already covers the topic, update that page; otherwise create one.
2. Link it to related pages in both directions.
3. Update `wiki/index.md`, append the log entry, commit.

## Lint

A health check. It is due when the latest `lint` entry in `wiki/log.md` is more than 30 days old, or there is none; every ingest checks this.

Check every page for:

- contradictions between pages
- claims a newer source has superseded, and dated claims past their date
- pages with no inbound link, and pages missing from the index
- broken links
- concepts mentioned on several pages that have no page of their own
- identifiers that belong in Claude memory

Fix the mechanical findings (links, index entries) yourself. List the rest for the user with a suggested fix each, and suggest sources that would fill the gaps. Append a `lint` log entry with the counts, then commit.

## Housekeeping

- **Commit after every operation** from the vault root, with the log entry's heading as the message, then `git push`. The remote is the user's private repository.
- **iCloud stalls git.** The vault lives in iCloud Drive, and files not downloaded to this Mac make `git add` and `git status` hang. When a git command stalls, run `brctl download .` in the vault root, wait until `find . -type f -flags +dataless` prints nothing, then retry.
- **Legacy notes stay put.** Move or rewrite one only when the user asks.
