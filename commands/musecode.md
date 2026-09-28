---
description: "Ultracode" on Muse Spark 1.3 (free) — orchestrate the task as a Workflow where every fan-out agent is the `muse` relay (agentType 'muse'), so the work itself runs on Muse via opencode at zero token cost and Claude only scopes, orchestrates and judges. Trigger on /musecode, "muse code", "kjør dette på muse", "fan out on muse".
---

The user wants the task after `/musecode` done the ultracode way — decomposed and run across many subagents — but with **Meta Muse Spark 1.3** (free, OpenCode Zen) doing the work instead of Claude. This command is the explicit opt-in for the Workflow tool.

**Relation to ultracode:** this is ultracode with Muse as the workers. Same Workflow tool, same quality patterns, same "exhaustive and correct" goal. What changes: leaf work runs on Muse for free, judging stays on Claude, and breadth is bought with time and RAM instead of tokens.

## How it works

- `~/.claude/agents/muse.md` is a Haiku relay: it pipes its prompt into `muse-run`, which runs a standalone `opencode run --auto -m opencode/muse-spark-1.3-contributor-free` (about 7 s startup per call) and returns Muse's answer verbatim. Cost per agent: a few thousand Haiku tokens for the relay; the Muse work is free.
- In a Workflow script, `agent(prompt, {agentType: 'muse', ...})` therefore runs on Muse. `schema` still works — the relay fills the StructuredOutput from Muse's text.
- Outside workflows the same thing is `Agent({subagent_type: 'muse', prompt})`.
- **On Sleeper, prefer `agentType: 'mac-muse'`** for implement-shaped leaves: the same Muse work runs on Petter's Mac (up to 6 at once instead of Sleeper's 3–5), each job in its own mirror or clone, with the changes applied back here as a patch. Its split protocol is `MAC-START` / `MAC-WAIT <id>`. It falls back to `muse-run` here when the Mac sleeps. Two jobs whose patches touch the same file conflict on apply, so give parallel editors `isolation: 'worktree'` as usual.
- Muse reads `AGENTS.md` in the repo through opencode, so it has the same project context.
- **Jobs are detached**: `muse-run` launches opencode as a background job under `~/.cache/muse-run/jobs/<id>/` and only *waits* in the foreground. If the wait passes 540 s it prints `MUSE-RUN PENDING <id>` and exits 3; the relay then loops `muse-run --wait <id>`. A Muse job may therefore run for up to **one hour** (`MUSE_MAX`), not ten minutes. `muse-run --status` lists jobs; `muse-run --env` shows the effective settings.

## The two caps, and how far they go

1. **Concurrent Workflow agents**: the harness hardcodes `min(16, max(2, cpus − 2))`, no env override (verified in Claude Code 2.1.261, 2026-09-05). A 4-core server gets **2**; a 10-core laptop gets 8. `install.sh` prints the number for the host you're on. The Agent tool's separate cap is `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (default 20). The way around a low Workflow cap is the **MUSE-START / MUSE-WAIT split** below: starting a job takes one agent for ~15 s, then the job runs on its own; waiting takes an agent only to collect. So the number of Muse jobs actually running is bounded by `muse-run`'s own gate, not by the harness.
2. **Muse jobs at once**: `muse-run --start` admits a job only while fewer than `MUSE_MAX_JOBS` run *and* available memory minus `MUSE_MEM_RESERVE_MB` leaves `MUSE_JOB_MB` to spare. Each opencode is 580–900 MB RSS; the gate is what keeps the box from swapping. Tune in `~/.config/muse-run/env` (profiles in the repo's `env.example`); `muse-run --env` shows what is in effect. Plan fan-outs up to the `MUSE_MAX_JOBS` it reports (e.g. 16 on a 36 GB laptop, 6 on Sleeper), using the split protocol when that exceeds the Workflow cap. Exit 4 = no slot within `MUSE_START_WAIT` s.

## Steps

1. **Read the task** after `/musecode`. If empty, ask what to run and stop.
2. **Scout inline first** (you, not Muse): list the files, find the work-list, decide the phases. Muse gets the leaf work; you keep the shape.
3. **Author the Workflow** (load `workflow-authoring` if you need the API). Rules for the Muse edition:
   - Every fan-out `agent()` gets `agentType: 'muse'`. Omit `model`/`effort` on those calls — the relay's own definition (Haiku) wins.
   - **Split by role: Muse works, Claude judges.** Fan-out stages that read, search, implement or run tests get `agentType: 'muse'`. Stages that decide whether a finding is real, score competing designs, or pick a winner stay on Claude (omit `agentType`). Judges read short findings, not the codebase, so this costs little and is what keeps the result at ultracode quality. You still synthesize the final result yourself in the main loop. Override only if the user says "everything on Muse".
   - **Muse does not verify unless told.** Known pattern: it reads and reasons but skips running tests, builds, or audits. Every Muse prompt that should verify must say so literally: "run `npm test` and paste the last 20 lines of output", "run the script and report its exit code". Prompts that produce findings should require file:line evidence.
   - Muse prompts are self-contained: absolute paths, the exact question, the exact output format. It sees nothing from this conversation.
   - Agents that edit files in parallel need `isolation: 'worktree'`; `muse-run` runs in the agent's cwd, so the worktree is what Muse edits.
   - Long tasks are fine (one hour per job). Split only when a task is conceptually two.
   - **Wide fan-outs (more jobs than the Workflow cap that should overlap)** use the split protocol. Prompt A starts with the line `MUSE-START` followed by the task; the relay answers with the job id. Prompt B is exactly `MUSE-WAIT <id>`; the relay answers with Muse's output. Two barriers, because every job must be started before any agent blocks on a wait:
     ```js
     const ids = await parallel(TASKS.map((t, i) => () =>
       agent(`MUSE-START\n${t}`, {agentType: 'muse', label: `start:${i}`, phase: 'Start'})))
     const outs = await parallel(ids.map((id, i) => () =>
       agent(`MUSE-WAIT ${id.trim()}`, {agentType: 'muse', label: `wait:${i}`, phase: 'Wait', schema: OUT_SCHEMA})))
     ```
     Wall-clock ≈ slowest job + ~15 s per start, instead of jobs running cap-at-a-time.
     Verify with `muse-run --status` that N jobs show `running` at once. Plain `agent()` (start+wait in one relay) is still right for fan-outs within the cap or when a pipeline stage needs the result immediately.
   - **Use the ultracode quality patterns, sized for free workers.** The Workflow reference's patterns (adversarial verify, perspective-diverse verify, judge panel, loop-until-dry, multi-modal sweep, completeness critic) apply unchanged; the difference is that breadth is free. Default shapes:
     - *Review / audit*: 6–12 Muse finders with distinct lenses → dedup in plain code → 3 Claude refuters per finding, majority wins → loop until two dry rounds.
     - *Design*: 3–5 Muse proposals from different angles → Claude judge panel → you synthesize from the winner.
     - *Implement*: one Muse agent per unit of work in a worktree, prompt ends with "run the tests and paste the last 20 lines" → Claude reviewer per diff → you merge.
     - *Understand / research*: multi-modal Muse sweep → Muse deep-read per hit → Claude completeness critic → next round.
     Don't cap coverage silently; `log()` anything dropped.
   - **Multi-phase work is several workflows in sequence**, one per phase (understand → design → implement → review), with you reading each result before authoring the next. Same as ultracode.

4. **Run it**, read `journal.jsonl` if a result looks empty, then **verify the outcome yourself** before reporting — run the tests, diff the tree. Treat Muse's high-priority claims as unverified until you or a "run it and paste" Muse agent has checked them.
5. **Report**: what ran on Muse (agent count), what you changed, what you verified. If files changed in the repo, commit and push as usual.
