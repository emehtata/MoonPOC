# AGENTS.md

Instructions for any AI agent working in this repository. They describe the spec → implement → test pipeline and the reporting rules. The same procedures exist as Claude Code agents and skills in `.claude/`; if this file and those files ever disagree, fix both.

## Pipeline

Work moves through three roles, in this order:

1. **Spec writer**: turns the request into a spec at `docs/specs/<slug>.md`. Numbered requirements `REQ-1`, `REQ-2`, ... and acceptance criteria. Writes no code and no tests.
2. **Implementer**: builds the spec in the codebase. Writes production code only. Does not write feature tests and does not edit specs or tests.
3. **Tester**: writes and runs tests that cover every REQ. Does not edit implementation code or specs.

A coordinator (the orchestrator) sends each role's output to the next role.

## Reversing on problems

When a problem is found, the work goes back **one stage at a time** toward the start. Never skip a stage on the way back.

- Tester finds an implementation bug (`IMPL_ISSUE`): send to the implementer, then retest.
- Tester finds a spec gap or contradiction (`SPEC_ISSUE`): send to the spec writer, then the implementer, then the tester.
- Implementer finds a spec problem (`SPEC_ISSUE`): send to the spec writer, then the implementer and tester.
- Implementer finds a build problem (`BUILD_ISSUE`): the implementer fixes its own build.
- Tester finds a broken test (`TEST_ISSUE`): the tester fixes the test itself and reruns it.

Pass the other role's report to the next role verbatim. If a spec change alters requirements, rerun the implementer and the tester even for a small change.

Stop after **3 round trips** between the same two stages and report the situation to the user.

## Reporting (required)

Every agent must end its work with a report, every time: on success, when blocked, and when it fails. Never finish with only a tool call and no report. If the work could not be completed, say so and say why.

Each report ends with a status line:

| Role | Statuses |
|---|---|
| Spec writer | `READY` or `NEEDS_INPUT` |
| Implementer | `DONE` or `BLOCKED` (with `SPEC_ISSUE` or `BUILD_ISSUE`) |
| Tester | `PASS` or `FAIL` (with each failure classified as `IMPL_ISSUE`, `SPEC_ISSUE`, or `TEST_ISSUE`) |

A missing report or status line is treated as a failure to report. Ask the same role again to report in the required format. If it fails to report twice, stop and tell the user which role did not report.

## Rules for all roles

- Do not weaken a test, skip it, or hard-code expected output to make it pass.
- Do not edit `docs/specs/` unless you are the spec writer.
- Do not leave debug code, commented-out code, or TODOs that hide unfinished requirements.
- State assumptions and stack choices in your report so the user can check them.

## Where things live

- `docs/specs/`: specs, one file per feature.
- `.claude/agents/`: Claude Code subagent definitions for the three roles.
- `.claude/skills/`: the detailed procedure and report format for each role, plus `orchestrate` for running the pipeline.
