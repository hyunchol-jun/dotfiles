# Survey brief — one unit

You are mapping ONE unit of this repository for an architecture map. Read code, never guess. Every row cites `path:line` (repo-relative) that a reader can open and see the claim.

## Budget

- At most **40 tool calls**. Plan them: route tables and clients first, then env/config, then imports across package boundaries.
- Use `grep -n` / `rg -n` and `sed -n A,Bp`. Never `cat` a file longer than 120 lines; never print a deploy manifest or terragrunt file in full.
- `inventory.md` already tells you how this unit is built and deployed (image, workload, workflow templates, manifest lines). Cite those lines; do **not** re-read `environments/`, `infrastructure/`, or workspace manifests beyond the lines it names.
- Stop when the budget is spent and write what you have; mark anything unfinished `unverified` in the evidence cell.

## Where seams hide

HTTP/gRPC clients and route tables; SDK clients (AWS, Snowflake, OpenAI/Anthropic/OpenRouter, GitHub, Slack, Monday); queue/topic names (SQS/SNS); connection strings and env vars; ORM/schema/migration definitions; workflow templates that name other templates or images; docker-compose links; nginx proxy configs; cross-package imports.

## Output — write the file, then reply with one line

Write `$OUT/survey/<unit>.md` with **exactly** these four headed tables and nothing else. Reply with only: `<path> — units N, edges N, stores N, externals N`. Do not paste the tables in your reply.

```
### Unit
| name | group | path | runtime | deployed how | purpose | evidence |

### Edges
| from | to | mechanism | seam | evidence |

### Data stores
| store | kind | access | evidence |

### External services
| service | mechanism | purpose | evidence |
```

Rules for the cells:

- **Every cell ≤ 160 characters.** No replica counts, template lists, host names, or migration counts in prose cells — those live at the cited line, not in the map.
- `name` is the unit's directory name; `group` is one of `frontend`, `service`, `worker`, `data-platform`, `platform-infra`, `tooling`.
- `from` / `to` name another unit by directory name, a store by its `store` name, or an external service by its `service` name. One row per distinct seam; a bidirectional seam is two rows.
- `mechanism` ∈ `http`, `grpc`, `queue/topic`, `db-read`, `db-write`, `file/object-store`, `cron/workflow-trigger`, `shared-library`, `env/config`, `external-saas`.
- `seam` names the concrete thing the arrow stands for (route, topic, table group, bucket, env var), briefly.
- `evidence`: up to three `path:line` refs separated by `; `. A row with no line is `unverified` there.
- `kind` ∈ `postgres-schema`, `snowflake-schema`, `iceberg-table`, `s3-bucket`, `queue`, `cache`, `other`. `access` ∈ `owns`, `writes`, `reads`.

A missing seam is worse than a duplicate; the assembler deduplicates.
