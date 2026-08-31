---
name: review-plan
description: Adversarially review an implementation or fix plan — a fresh-context subagent verifies every claim against the codebase and reports the holes.
disable-model-invocation: true
---

# review-plan

Review an implementation or fix plan before anyone implements it. The reviewer is never the plan's author: authorship context carries the author's blind spots, so the review always runs in a subagent that receives only the goal, the plan, and repo access — even when the plan was written in this conversation.

## Steps

1. **Pin down the plan and the goal.** The argument is a path to the plan file; with no argument, use the most recent plan in this conversation. If the plan exists only inline, write it verbatim to a scratchpad file first — the subagent must read exactly the text under review. Also capture the one-paragraph goal the plan is meant to achieve (from the plan itself or the conversation); completeness can only be judged against the goal.

2. **Dispatch one general-purpose subagent** with the prompt template below, filling in the goal and the plan path. Pass no other conversation context.

3. **Relay the verdict and every hole** the reviewer reports — do not summarize holes away. Split them into *fix before implementing* and *worth noting*. Then stop: the deliverable is the assessment. Offer one next action — patch the plan with the fixes — and wait for the user.

## Reviewer prompt template

> You are reviewing an implementation plan you did not write. Your job is to find the holes before implementation starts. Assume the plan is wrong until the code proves it right.
>
> Goal the plan must achieve: {goal}
> Plan: read {plan_path}
>
> **Ground every claim.** For every file, function, symbol, config key, command, or behavior the plan names, open the code and confirm it exists and behaves as the plan assumes. Each claim ends as either *verified* (cite file:line) or a *hole*. Run any check that takes under two minutes instead of trusting a "should work."
>
> Hunt these hole classes:
> - **Phantom** — code or API the plan references that doesn't exist or works differently than assumed.
> - **Missing step** — work the goal requires that no step covers: call sites, migrations, config, tests, error paths.
> - **Blast radius** — code affected by the change that the plan never mentions (other callers of a changed function, consumers of a changed schema).
> - **Ordering** — a step that needs the output of a later step, or breaks the build/tests until a later step lands.
> - **Underspecified** — a step an implementer with no extra context could not execute without guessing.
>
> You are done only when every named artifact has been opened and every hole class hunted across the whole plan.
>
> Report: a one-line verdict (*sound* or *N holes found*), then each hole with its class, severity (*blocker* — the plan fails as written / *gap* — missing or risky work), evidence (file:line or command output), and a concrete suggested edit to the plan.
