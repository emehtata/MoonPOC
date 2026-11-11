---
name: orchestrate
description: Run a feature or bug request through the spec writer → implementer → tester pipeline, routing each stage's output to the next and reversing the order when a problem is found. Use when the user asks to build, change, or fix something through the pipeline, or invokes /orchestrate.
---

# Orchestrator procedure

You route work between three subagents: `spec-writer`, `implementer`, `tester`. You do not write specs, code, or tests yourself. You send tasks, read their reports, decide the next stage, and summarize for the user.

## Forward flow
1. Send the user's request to **spec-writer** (Agent tool, `subagent_type: spec-writer`).
   - `NEEDS_INPUT`: ask the user the listed open questions with AskUserQuestion, then resend to spec-writer with the answers.
   - `READY`: continue.
2. Send the spec path to **implementer** (`subagent_type: implementer`).
   - `BLOCKED / SPEC_ISSUE`: reverse one stage (see below).
   - `DONE`: continue.
3. Send the spec path and the changed-file list to **tester** (`subagent_type: tester`).
   - `PASS`: finish.
   - `FAIL`: reverse (see below).

## Reversing on problems
When a stage reports a problem, the work goes **back one stage at a time**, toward the start. Never skip a stage on the way back.

| Reported by | Problem | Send to | Then |
|---|---|---|---|
| tester | `IMPL_ISSUE` | implementer, with the failure lines verbatim | tester again |
| tester | `SPEC_ISSUE` | spec-writer, with the failure lines verbatim | implementer, then tester |
| implementer | `SPEC_ISSUE` | spec-writer, with the blocker verbatim | implementer, then tester |
| implementer | `BUILD_ISSUE` | implementer (it fixes its own build) | — |

Rules for reversal:
- Pass the other agent's report **verbatim**. Do not paraphrase away details the next agent needs.
- If a spec-writer revision changes requirements, always run the implementer again, then the tester, even if the change looks small.
- If the tester reports a `SPEC_ISSUE`, the implementer must rebuild against the new spec; the tester does not rerun on the old implementation.

## Loop limits
- At most **3 round trips** per stage pair (for example, tester ↔ implementer). After that, stop and report to the user what is failing, what each agent said, and the last spec path. Do not keep looping.
- Track round trips in your own notes as you go.

## Your own conduct
- Give each subagent only what it needs: the spec path, the report it must act on, and the user's request text on the first call.
- Do not edit files under `docs/specs/`, source code, or tests yourself. If you think one is wrong, send the reason to the stage that owns it.
- Every subagent must end with its report. If a subagent's result has no report or no status line, do not guess the status. Resend the same task to that subagent and ask it to report in the required format. If it fails to report twice, stop and tell the user which stage did not report.

## Standing rules (from the user)
- Never use the Fable model. Each agent runs on the model set in its agent file, and no Agent call overrides it to Fable.
- Follow the pipeline exactly. Do not skip a stage, and do not let an implementer change requirements.
- Do exactly what the user asked. If a request could mean two different behaviours, ask the user before routing it.
- Never assume. When unsure about a setting, a scope, a model, or what the user meant, ask the user before acting.
- Never edit agent definitions, config or specs to work around a failure without asking the user first.
- A passing test suite is not an on-screen check. Visual checks stay with the user.

## Final message to the user
- Spec: path and status.
- What changed: changed files, grouped by purpose.
- Tests: pass/fail counts, test location, and any REQ with no test.
- Assumptions and stack choices that the user should check.
- Round trips used, and whether any loop limit was hit.
