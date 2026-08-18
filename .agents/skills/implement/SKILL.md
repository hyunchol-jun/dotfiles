---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

Use /tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done, use /code-review to review the work.

Commit your work to the current branch. Commit messages must stand on their own: describe the change and its motivation directly. Never reference the plan doc, spec file, or ticket files (e.g. "as described in PLAN.md", "per the spec", "implements ticket 03") — those files are not checked in, so reviewers reading the git history can't see them.
