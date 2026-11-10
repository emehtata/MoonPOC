---
name: tester
description: Write and run tests that verify an implementation against its spec in docs/specs/, then classify each failure as implementation, spec, or test problem. Used by the tester agent and by /tester. Never modifies implementation code or specs.
---

# Tester procedure

## Inputs
- A spec path, `docs/specs/<slug>.md`, and the implementer's list of changed files.

## Steps
1. **Read the spec and the changed files.** Note every REQ id and acceptance criterion, including edge cases.
2. **Find the test setup.** Look for an existing test framework and test folder. If none exists, choose the standard one for the stack and create it. Record the choice in the report.
3. **Write tests.** Cover every REQ and every acceptance criterion, plus the edge and error cases. Name each test with its REQ id, for example `REQ-3: rejects empty input`. Test observable behavior through public interfaces, not internal details.
4. **Run the tests.** Run the new tests, then the full suite.
5. **Classify each failure:**
   - `IMPL_ISSUE`: the behavior differs from what the spec says. Report it to the implementer.
   - `SPEC_ISSUE`: the spec is ambiguous, contradictory, or silent on something the test needs. Report it to the spec writer.
   - `TEST_ISSUE`: the test itself is wrong (bad assertion, wrong fixture, wrong setup). Fix the test yourself, rerun, and do not report it.
6. **Check coverage.** Every REQ must have at least one test. List any REQ that has none.

## Rules
- Do not edit implementation source files or anything under `docs/specs/`.
- Do not make a test pass by weakening its assertion, skipping it, or hard-coding the expected output. A test that was changed only to pass is a `TEST_ISSUE` you must justify in the report.
- Do not mark tests as expected failures to hide a bug.
- Tests must be deterministic. Do not depend on wall-clock time, network access, or test order unless the spec requires it.

## Report format (final message)
Always end with this report, even when the tests cannot run. Never end with only a tool call.
```
STATUS: PASS | FAIL
TESTS: <total> total, <passed> passed, <failed> failed
TEST_LOCATION: <paths of test files you wrote or changed>
TEST_COMMAND: <command used>
COVERAGE: REQ-1 ✓ | REQ-2 ✓ | REQ-3 ✗ (no test) ...
FAILURES:
- <test name> | REQ-n | IMPL_ISSUE | expected: <...> actual: <...>
- <test name> | REQ-n | SPEC_ISSUE | <what the spec leaves unclear>
TEST_FIXES: <TEST_ISSUE fixes you made, with reason, or none>
```
`STATUS: PASS` requires zero failures and full REQ coverage.
