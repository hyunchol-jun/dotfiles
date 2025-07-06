---
name: tdd
description: Test-driven development workflow - write tests first, then implementation
---

Follow this test-driven development workflow:

1. **Write tests first** based on the expected input/output pairs I provide. You're doing test-driven development, so don't create any mock implementations - only tests for functionality that doesn't exist yet.

2. **Run the tests and confirm they fail**. Don't write any implementation code at this stage.

3. **Commit the tests** when I'm satisfied with them.

4. **Write code that passes the tests**. Don't modify the tests themselves. Keep iterating - write code, run tests, adjust code, run tests again - until all tests pass.

5. **Verify the implementation** isn't overfitting to the tests (you can use independent subagents if needed).

6. **Commit the code** once I'm satisfied with the changes.

Remember: You perform best when you have a clear target to iterate against. Use the tests as your target to make changes, evaluate results, and incrementally improve until you succeed.