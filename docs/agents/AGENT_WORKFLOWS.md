# Agent Workflows — zig-gui

> Reference document for AI agent orchestration in this project.
> All agents must read `docs/AGENT_GUIDE.md` and `docs/specs/00_constitution.md` first.

---

## 1. How GitHub Copilot agents communicate

### Native mechanism — subagents (same session)

An orchestrator agent lists specialized agents in its `agents:` frontmatter and invokes
them programmatically via the `agent` tool. This is the **built-in Copilot mechanism**. The
orchestrator passes context in the invocation prompt; results return within the same session.

```
Orchestrator (single session)
  │── invokes ──► Implementer (via agent tool)
  │── reads result
  │── invokes ──► Tester      (via agent tool)
  │── reads result
  │── invokes ──► Validator   (via agent tool)
  └── logs final status
```

Within a single session, agents communicate by: **invoking → waiting → reading output**.
No files needed for same-session handoffs.

### Native mechanism — handoffs (VS Code)

Agent `.agent.md` files can declare `handoffs:` frontmatter. After a response completes,
a button appears in the chat that switches to the target agent with a pre-filled prompt and
context. This is for **human-controlled** sequential workflows (human reviews and approves
each step before clicking next).

### Cross-session workflow state — handoff files

When a task spans multiple independent sessions (one agent session ends, human picks up or
creates a new session with a different agent), agents write structured handoff files to
`docs/.agent-context/`. This is a **custom file-based coordination pattern** for this project.

**Handoff file format** (one per step):

```
docs/.agent-context/
  <run-id>/
    step-01-validator.md      ← validator analyzed spec
    step-02-implementer.md    ← implementer wrote code
    step-03-test-designer.md  ← test-designer wrote tests
    step-04-tester.md         ← tester ran all tests
    step-05-validator.md      ← validator checked checklist
    registry.json             ← current status index
```

Each handoff file template (Markdown):

```markdown
---
from_agent: validator
to_agent: implementer
step_number: 1
status: PASS
module: NN
timestamp: 2026-06-02T15:30:45Z
---

## Summary
<what was accomplished>

## Artifacts produced
- path/to/file1
- path/to/file2

## For next agent
<explicit next step and context>

## Issues
<any blockers or warnings>
```

The orchestrator reads these files to decide which agent to route to next. If any handoff has
`status: FAIL` or `ESCALATION_NEEDED`, the orchestrator stops routing and surfaces the issue
to the human.

---

## 2. Core operating principle — do → validate → redo

Every step in every workflow follows this loop:

```
┌─ DO ──────────────────────────────────────────┐
│  Perform the step (implement, run, analyze…)   │
└────────────────────────────────────────────────┘
             │
             ▼
┌─ VALIDATE ─────────────────────────────────────┐
│  Check explicit pass/fail criteria (see below)  │
└────────────────────────────────────────────────┘
             │
     ┌───────┴───────┐
  PASS               FAIL
     │               │
     ▼               ▼
 Next step      ┌─ REDO ──────────────────────────┐
                │  Diagnose, fix, repeat from DO   │
                │  Max 3 attempts, then ESCALATE   │
                └─────────────────────────────────┘
```

**Escalation** = write `docs/.agent-context/YYYYMMDD_escalation.md` with the exact blocker,
what was tried, and what decision is needed from the human. Do NOT guess. Do NOT work around
constitution invariants.

---

## 3. Agent roster

| Agent | File | Role |
|---|---|---|
| **Orchestrator** | `.github/agents/orchestrator.agent.md` | Routes tasks, manages handoff files, never writes code |
| **Implementer** | `.github/agents/implementer.agent.md` | Writes and fixes module code against `types.zig` |
| **Test Designer** | `.github/agents/test-designer.agent.md` | Writes unit tests for modules (creates `NN_test.zig`) |
| **Validator** | `.github/agents/validator.agent.md` | Checks specs, code, docs vs invariants; read-only |
| **Tester** | `.github/agents/tester.agent.md` | Runs tests, triages failures, reports results |
| **Infra** | `.github/agents/infra.agent.md` | Build config, dependencies, toolchain |

---

## 4. Workflow 1 — Module implementation

**Trigger:** "Implement module NN" / "Build module NN" / new module spec exists and code doesn't.

**Owner:** Orchestrator routes → Implementer (primary) + Tester (step 4) + Validator (step 5)

```
STEP 1 — Validate requirement           [Validator]
────────────────────────────────────────────────────
DO:
  - Read 00_constitution.md in full
  - Read NN.spec.md, NN.types.zig, NN.acceptance_test.zig, NN.checklist.md
  - Check: does any spec instruction contradict a constitution invariant?
  - Check: does any term lack a glossary definition?
  - Check: does the spec require a dependency not in INV-5.6?

VALIDATE — pass criteria:
  ✓ No constitution contradiction found
  ✓ All terms resolvable from glossary
  ✓ All dependencies are pre-approved

FAIL → escalate immediately. Record contradiction in escalation file.
PASS → handoff context to Implementer, proceed to step 2.

────────────────────────────────────────────────────
STEP 2 — Plan implementation            [Implementer]
────────────────────────────────────────────────────
DO:
  - Map every public API in NN.types.zig to an implementation task
  - Identify edge cases from NN.acceptance_test.zig (read tests, do NOT change them)
  - List all imports needed (only modules numbered < NN — INV-3.4)
  - Identify data layout (parallel arrays, no per-widget heap — INV-3.1)

VALIDATE — pass criteria:
  ✓ Every types.zig stub has a corresponding implementation task
  ✓ Every acceptance_test.zig case is covered by the plan
  ✓ No upward module imports planned

FAIL → refine plan.
PASS → proceed to step 3.

────────────────────────────────────────────────────
STEP 3 — Develop code                   [Implementer]
────────────────────────────────────────────────────
DO:
  - Implement each function, matching types.zig signatures exactly (INV-5.1)
  - Follow all architecture invariants (see AGENT_GUIDE.md §4)
  - Do NOT implement any non-goal listed in the spec (INV-5.4)
  - Run `zig build` after each meaningful change

VALIDATE — pass criteria:
  ✓ `zig build` compiles without errors
  ✓ Every public signature matches NN.types.zig byte-for-byte
  ✓ No spec non-goal implemented
  ✓ No upward imports

FAIL → diagnose compiler errors, fix, re-validate. Max 3 cycles → escalate.
PASS → proceed to step 4.

────────────────────────────────────────────────────
STEP 4 — Design unit tests              [Test Designer]
────────────────────────────────────────────────────
DO:
  - Read NN.spec.md and NN.acceptance_test.zig (do NOT modify acceptance_test.zig)
  - Write comprehensive unit tests to `src/NN/NN_test.zig`
  - Cover edge cases, error paths, and boundary conditions not in acceptance_test.zig
  - Ensure tests are deterministic (no random, no wall-clock time)

VALIDATE — pass criteria:
  ✓ Unit test file created at src/NN/NN_test.zig
  ✓ Test code compiles (zig build succeeds with test file present)
  ✓ Tests cover meaningful scenarios from the spec

FAIL → revise tests until they compile.
PASS → proceed to step 5.

────────────────────────────────────────────────────
STEP 5 — Run all tests                  [Tester]
────────────────────────────────────────────────────
DO:
  Run acceptance tests:
    zig test docs/specs/NN.acceptance_test.zig
  
  Run unit tests (if NN_test.zig exists):
    zig test src/NN/NN_test.zig
  
  Collect full output (pass count, fail count, error messages)
  For each failure: identify the test name and the assertion that failed

VALIDATE — pass criteria:
  ✓ All acceptance tests pass (0 failures)
  ✓ All unit tests pass (0 failures)
  ✓ No compilation errors in test runners

FAIL → write failure report; hand context back to Implementer with:
  - Exact test name(s) that failed
  - Assertion message + actual vs expected values
  - Hypothesis about root cause
  Then Implementer fixes code (step 3) and loops back to step 5.
PASS → proceed to step 6.

────────────────────────────────────────────────────
STEP 6 — Validate checklist             [Validator]
────────────────────────────────────────────────────
DO:
  - Open NN.checklist.md
  - For each unchecked item: verify it is actually satisfied by the code
  - Tick items only when positively confirmed (do NOT tick speculatively)
  - Identify any item that cannot be ticked (missing work or manual step)

VALIDATE — pass criteria:
  ✓ All automatable items ticked
  ✓ Manual items (if any) documented with who must confirm them

FAIL → list un-ticked items; route gap items back to Implementer or flag manual items for human.
PASS → proceed to step 7.

────────────────────────────────────────────────────
STEP 7 — Update documentation           [Implementer]
────────────────────────────────────────────────────
DO:
  - If the module introduced a new pattern not in AGENT_GUIDE.md, add it
  - If the module corrects the constitution (as some specs do), apply the update to
    00_constitution.md per the spec's explicit instruction
  - Update docs/HOW_TO_USE.md to reflect any new public API, new tags, new class names,
    new widget kinds, new form keywords, or changes to the build command list introduced
    by this module. If the module completes the renderer bridge (post-v1), remove or
    update the "What is NOT wired yet" section accordingly.
  - Write a one-paragraph completion summary to docs/.agent-context/

VALIDATE — pass criteria:
  ✓ No new pattern is undocumented
  ✓ Any constitution updates listed in the spec's "action" items are applied
  ✓ docs/HOW_TO_USE.md reflects the current public API (no stale entries, no missing entries)
  ✓ Completion summary written

PASS → module complete. Orchestrator marks done.
```

---

## 5. Workflow 2 — Issue resolution

**Trigger:** A failing test, a reported bug, a contradiction surfaced during another workflow.

**Owner:** Orchestrator routes → Validator (analysis) → Implementer (fix) → Tester (verify)

```
STEP 1 — Analyze issue                  [Validator]
────────────────────────────────────────────────────
DO:
  - Read the issue description and any attached context
  - Identify the affected module(s)
  - Read the module's spec.md and relevant constitution sections
  - Check: is fixing this in scope? Does the fix violate any invariant?

VALIDATE — pass criteria:
  ✓ Root module identified
  ✓ Fix is within spec scope and respects all invariants
  ✓ No invariant violation required to fix

FAIL → escalate (out-of-scope or invariant conflict requires human decision).
PASS → write analysis context; route to Implementer.

────────────────────────────────────────────────────
STEP 2 — Reproduce                      [Tester]
────────────────────────────────────────────────────
DO:
  - Run the specific failing test or reproduce the exact failure condition
  - Capture full error output

VALIDATE — pass criteria:
  ✓ Issue is reproducible with a specific test or command

FAIL → if non-reproducible: escalate with reproduction steps needed.
PASS → route to Implementer with reproduction context.

────────────────────────────────────────────────────
STEP 3 — Fix code                       [Implementer]
────────────────────────────────────────────────────
DO:
  - Diagnose root cause from reproduction output + code
  - Implement the minimal fix (do NOT refactor beyond what is needed — INV-5.4)
  - Run `zig build` to confirm fix compiles

VALIDATE — pass criteria:
  ✓ `zig build` succeeds
  ✓ Fix is narrowly scoped (no unrelated changes)
  ✓ No non-goal implemented as a side-effect

FAIL → try alternative approach. Max 3 attempts → escalate.
PASS → proceed to step 4.

────────────────────────────────────────────────────
STEP 4 — Full regression test           [Tester]
────────────────────────────────────────────────────
DO:
  - Run the acceptance test for the fixed module
  - Run acceptance tests for ALL modules that import the fixed module (dependents)
  - Collect full results

VALIDATE — pass criteria:
  ✓ Original failing test now passes
  ✓ No previously passing test now fails (zero regressions)

FAIL → route regression details back to Implementer.
PASS → proceed to step 5.

────────────────────────────────────────────────────
STEP 5 — Confirm resolution             [Validator]
────────────────────────────────────────────────────
DO:
  - Confirm the original issue description is satisfied
  - Verify the fix does not introduce a constitution violation

VALIDATE — pass criteria:
  ✓ Issue is resolved
  ✓ No new invariant violations

PASS → Orchestrator marks issue closed. Write completion note.
```

---

## 7. Workflow 3 — Full test run

**Trigger:** "Run all tests" / pre-release check / after a series of changes.

**Owner:** Orchestrator routes → Tester (all steps); failures route to Implementer.

```
STEP 1 — Run all acceptance tests       [Tester]
────────────────────────────────────────────────────
DO:
  Run each module's acceptance test in build order:
    zig test docs/specs/02.acceptance_test.zig
    zig test docs/specs/03.acceptance_test.zig
    zig test docs/specs/04.acceptance_test.zig
    zig test docs/specs/05.acceptance_test.zig
    zig test docs/specs/06.acceptance_test.zig
    zig test docs/specs/07.acceptance_test.zig
    zig test docs/specs/08.acceptance_test.zig
  Note: module 01 uses smoke_test.zig and requires a GPU + manual visual check.

VALIDATE — pass criteria:
  ✓ All tests collected (no "file not found" errors)

────────────────────────────────────────────────────
STEP 2 — Triage results                 [Tester]
────────────────────────────────────────────────────
DO:
  Categorize each failure:
    COMPILE_ERROR  — module code does not compile
    LOGIC_FAILURE  — test assertion failed (wrong output)
    MISSING_IMPL   — function is a stub / returns undefined

VALIDATE — pass criteria:
  ✓ Every failure is categorized

────────────────────────────────────────────────────
STEP 3 — Route failures                 [Orchestrator]
────────────────────────────────────────────────────
  - For each failing module: invoke Implementer with the triage report
  - Implementer fixes (see Workflow 1, Step 3)
  - After fixes: re-run that module's tests (Workflow 1, Step 4)
  - Repeat until all modules pass

────────────────────────────────────────────────────
STEP 4 — Final report                   [Tester]
────────────────────────────────────────────────────
DO:
  Write a test run summary to docs/.agent-context/YYYYMMDD_test_run.md:
    - Modules tested
    - Pass/fail per module
    - Failures that remain (if any, with escalation status)

VALIDATE — pass criteria:
  ✓ All modules passing, OR
  ✓ Remaining failures documented with escalation file written

PASS → Orchestrator marks run complete.
```

---

## 8. Workflow 4 — Infrastructure / config / plumbing

**Trigger:** build system changes, new approved dependency, `build.zig` modifications,
environment config, toolchain updates.

**Owner:** Orchestrator routes → Infra (all steps) + Tester (step 4)

```
STEP 1 — Validate change against invariants   [Infra + Validator]
────────────────────────────────────────────────────
DO:
  - Read 00_constitution.md sections 1, 2, 5 (INV-1.x, INV-2.x, INV-5.6)
  - If change requires a new external dependency:
      → STOP immediately. Write escalation file. Await human approval.
      → Only after explicit human approval: proceed with recording the dep in constitution.
  - If change is build config / plumbing only: proceed

VALIDATE — pass criteria:
  ✓ No new unapproved dependency
  ✓ Change stays within approved tool set (GLFW, Vulkan SDK, stb_truetype, std)
  ✓ Platforms affected: Windows and Linux only (INV-1.2)

FAIL → escalate.
PASS → proceed to step 2.

────────────────────────────────────────────────────
STEP 2 — Implement change               [Infra]
────────────────────────────────────────────────────
DO:
  - Make the build/config/plumbing change
  - Run `zig build` immediately after each meaningful edit

VALIDATE — pass criteria:
  ✓ `zig build` succeeds on the current platform
  ✓ No module-level code changes (infra agent touches only build files and config)

FAIL → revert to last working state; diagnose; retry.
PASS → proceed to step 3.

────────────────────────────────────────────────────
STEP 3 — Validate build reproducibility [Infra]
────────────────────────────────────────────────────
DO:
  - Run `zig build` from a clean state (remove zig-cache if needed)
  - Confirm the build is deterministic (same output)

VALIDATE — pass criteria:
  ✓ Clean build succeeds without manual intervention

FAIL → diagnose non-reproducibility (missing step in build.zig?).
PASS → proceed to step 4.

────────────────────────────────────────────────────
STEP 4 — Full test regression           [Tester]
────────────────────────────────────────────────────
  Run Workflow 3 (full test run).

VALIDATE — pass criteria:
  ✓ All previously passing tests still pass

FAIL → revert infra change; route failure analysis back to Infra.
PASS → proceed to step 5.

────────────────────────────────────────────────────
STEP 5 — Update constitution if needed  [Infra]
────────────────────────────────────────────────────
DO:
  - If a new approved dependency was added (human-approved in step 1):
      update INV-5.6 in 00_constitution.md
  - If build tool changed: update the approved-tools list
  - Write a one-paragraph change summary to docs/.agent-context/

VALIDATE — pass criteria:
  ✓ Constitution reflects current approved dep set
  ✓ No silent additions

PASS → Orchestrator marks infra change complete.
```

---

## 9. Escalation protocol

Any agent may escalate at any time. Do NOT work around a blocker by guessing or violating
an invariant.

Write `docs/.agent-context/YYYYMMDD_HHMMSS_escalation.md` with:

```markdown
# Escalation — <agent name> — <date>

## Workflow
<which workflow and step>

## Blocker
<exact description of what cannot proceed>

## What was tried
1. …
2. …
3. …

## Decision needed from human
<specific yes/no or choice required — be concrete>

## Relevant files
- <path>
```

After writing the file: stop all work on this task. Do NOT attempt further steps.

---

## 10. Corrections to the user's original proposal

| Original idea | Correction |
|---|---|
| "agents communicate through handoff files" | **Correct, but now formalized.** In Copilot, native same-session communication is via **subagent invocation** (`agents:` frontmatter + `agent` tool). For cross-session state, agents write structured handoff files to `docs/.agent-context/` with `created_at`, `to_agent`, `status` (PASS/FAIL), and `artifacts` fields. Use `registry.json` to track workflow state. This is the My-Fab pattern. |
| "develop tests" step in module workflow | **Corrected and ADDED.** "Do NOT modify `acceptance_test.zig`" means: don't touch the frozen contract spec. But you MUST **create unit test files** like `src/NN/NN_test.zig`. There IS a **test-designer agent** who writes tests while the implementer writes code. Tests become obsolete when code changes — they're updated/maintained like any other code through normal review. |
| Orchestrator does not do actual work | **Correct.** The orchestrator only creates handoff files, updates registry.json, and routes to subagents. Never writes code or runs commands. |
| do → validate → redo loop | **Correct.** This is the right operating model. |
| Minimize manual calls to human | **Correct.** Escalate only when a genuine decision is needed (e.g., new dependency, constitution conflict). |
