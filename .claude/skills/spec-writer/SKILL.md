---
name: spec-writer
description: Write or revise a spec file in docs/specs/ from a feature request or a problem report. Used by the spec-writer agent and by /spec-writer. Produces testable requirements; never writes code or tests.
---

# Spec writer procedure

## Inputs
- The request text (feature or bug description), and optionally:
- A previous spec path, plus a problem report from the implementer or tester that says what in the spec is wrong, missing or contradictory.

## Steps
1. **Survey the repo briefly.** Use Glob and Grep to learn what exists: language, frameworks, folder layout, existing modules related to the request. Do not read everything.
2. **If revising**, read the existing spec and the problem report. Change only what the report requires. Record each change in the Revision history section.
3. **Write `docs/specs/<slug>.md`** (kebab-case slug from the feature name). Use these sections in order:
   - `# <Title>`, then `Status: Draft | Ready`, `Slug: <slug>`
   - **Goal**: why this exists, in 2–4 sentences.
   - **Scope** and **Non-goals**.
   - **Stack and constraints**: language, frameworks, and anything the repo already fixes. If the repo has no code yet and the request does not name a stack, state the most conventional choice for the need and mark it as an assumption.
   - **Requirements**: numbered `REQ-1`, `REQ-2`, ... Each requirement is one atomic, observable behavior.
   - **Acceptance criteria**: for each REQ, a Given/When/Then case with concrete inputs and expected outputs.
   - **Edge cases and errors**: invalid input, empty input, limits, failure behavior.
   - **Assumptions**: decisions you made without asking.
   - **Open questions**: only questions whose answer would change the design and that cannot be assumed sensibly.
   - **Revision history**: date and one line per revision.
4. **Set Status.** `Ready` only if Open questions is empty. Otherwise `Draft`.

## Rules
- Every requirement must be verifiable. Replace vague words ("fast", "intuitive", "robust") with numbers or observable behavior.
- Do not write code, test code, or implementation plans. The spec states *what*, not *how*.
- Do not invent requirements the request did not ask for. Put useful extras under Non-goals or Open questions instead.
- Keep the spec short enough to read in one sitting. Prefer a table for many similar cases.

## Report format (final message)
Always end with this report, even when you stop early or fail. Never end with only a tool call.
```
STATUS: READY | NEEDS_INPUT
SPEC: docs/specs/<slug>.md
REQUIREMENTS: REQ-1 .. REQ-n
ASSUMPTIONS: <bullets, or none>
OPEN_QUESTIONS: <bullets, or none>
REVISION: <what changed, only when revising>
```
