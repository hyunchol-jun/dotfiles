#!/bin/sh
# Symlink the Matt Pocock agent skills from ~/.claude/skills into ~/.codex/skills
# so Codex (cxr) can use them. Idempotent; skips anything already present.
# The video/HyperFrames skills were linked by hand earlier and are left alone.

set -eu

SRC="$HOME/.claude/skills"
DST="$HOME/.codex/skills"
mkdir -p "$DST"

SKILLS="ask-matt grill-with-docs triage improve-codebase-architecture \
setup-matt-pocock-skills to-spec to-tickets implement wayfinder prototype \
diagnosing-bugs research tdd domain-modeling codebase-design code-review \
resolving-merge-conflicts wizard grill-me handoff teach to-questionnaire \
wait-what grilling writing-for-agents implement-tickets scaffold-exercises \
migrate-to-shoehorn setup-pre-commit setup-ts-deep-modules find-skills \
tdd-review-issues tdd-review-loop"

for s in $SKILLS; do
  if [ -e "$DST/$s" ]; then
    continue
  elif [ -d "$SRC/$s" ]; then
    ln -s "../../.claude/skills/$s" "$DST/$s"
    echo "linked: $s"
  else
    echo "missing in $SRC: $s" >&2
  fi
done
