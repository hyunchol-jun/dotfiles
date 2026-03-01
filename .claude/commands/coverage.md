---
name: coverage
description: Run tests with coverage reporting and highlight uncovered areas
---

Run the test suite with coverage enabled and report which areas of the codebase lack test coverage.

Follow these steps:

1. **Detect the test framework and coverage tool** — check project config files:
   - Python → `pytest --cov` (pytest-cov), `coverage run -m pytest`
   - Node.js/Jest → `jest --coverage` or `vitest --coverage`
   - Go → `go test -cover ./...` or `go test -coverprofile=coverage.out ./...`
   - Rust → `cargo tarpaulin` or `cargo llvm-cov` (if installed)
   - Ruby → check for `simplecov` in Gemfile
   - If the coverage tool is not installed, note that and suggest how to install it.

2. **Run tests with coverage** — execute the test command with appropriate coverage flags. Request a summary report (not just raw data).

3. **Report overall coverage** — state the total line/branch coverage percentage clearly.

4. **Identify uncovered areas** — list files or modules with the lowest coverage, focusing on:
   - Files below 50% coverage
   - Any files with 0% coverage (completely untested)

5. **Cross-reference with recent changes** — run `git diff --name-only HEAD~5` (or `main...HEAD` if on a branch) to find recently changed files, then highlight any recently changed files that have low or no coverage. These are the highest priority for new tests.

6. **Summarize** — provide a concise overview:
   - Overall coverage percentage
   - Number of files with no coverage
   - Recently changed files needing tests
   - Suggest specific files that would benefit most from additional tests
