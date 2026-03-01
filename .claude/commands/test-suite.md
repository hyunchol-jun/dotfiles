---
name: test-suite
description: Detect the project's test framework and run the full test suite
---

Detect the project's test framework and run the full test suite. Report results clearly.

Follow these steps:

1. **Detect the test framework** — look for config files in the project root to identify the ecosystem and test runner:
   - `package.json` → check `scripts.test`, look for jest, vitest, mocha, playwright, etc.
   - `pyproject.toml` / `setup.cfg` / `pytest.ini` → pytest
   - `Cargo.toml` → `cargo test`
   - `go.mod` → `go test ./...`
   - `mix.exs` → `mix test`
   - `Gemfile` / `Rakefile` → `bundle exec rspec` or `rake test`
   - `build.gradle` / `pom.xml` → `./gradlew test` or `mvn test`
   - If multiple frameworks exist (e.g., unit + e2e), identify all of them.

2. **Run the test suite** — execute the appropriate test command. Use verbose flags where available so individual test names are visible. If the project has a Makefile or script target for tests, prefer that.

3. **Report results** — summarize clearly:
   - Total tests run, passed, failed, skipped
   - List any failing tests with their error messages
   - If all tests pass, confirm that explicitly

4. **If tests fail** — briefly analyze the failures. Identify whether they look like real bugs, flaky tests, or environment issues. Do not attempt to fix anything unless asked.
