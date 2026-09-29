# musecode

"Ultracode" for Claude Code on **Meta Muse Spark 1.3** — the free model on OpenCode Zen. Claude scopes the task, fans it out as a Workflow, and judges the result; every leaf agent is a relay that hands its prompt to Muse through `opencode`. The work itself costs no tokens, only the few thousand Haiku tokens per relay.

Three pieces, wired into Claude Code by symlink:

| File | Installed as | Role |
|---|---|---|
| `commands/musecode.md` | `~/.claude/commands/musecode.md` | The `/musecode <task>` slash command: how to scope, author the Workflow, and verify |
| `agents/muse.md` | `~/.claude/agents/muse.md` | The `muse` relay agent (Haiku, Bash only; a PreToolUse hook, `sleeper/claude/hooks/mac-relay-guard.sh muse-run`, blocks every command but `muse-run`). Runs `muse-run` and returns Muse's stdout verbatim |
| `bin/muse-run` | `~/.local/bin/muse-run` | Bash CLI: one task → one detached `opencode run` job, with a memory-aware start gate |

Outside a Workflow the same relay is `Agent({subagent_type: 'muse', prompt})`.

## Install

Needs `opencode` (1.18+), `jq`, and Claude Code. The Zen "contributor-free" Muse model needs no API key or login (verified 2026-09-05).

```bash
git clone git@github.com:phareim/musecode.git ~/github/musecode
~/github/musecode/install.sh
```

The installer symlinks the three files, creates `~/.config/muse-run/env` from `env.example` if it is missing, and prints your host's numbers (see "Settings"). Agent definitions load at Claude Code startup, so open a **new session** afterwards. `./install.sh --check` reports without changing anything; `./install.sh --uninstall` removes the symlinks.

Smoke test without Claude:

```bash
muse-run 'Reply with exactly the word OK and nothing else'
muse-run --status
```

## Settings

Everything environment-specific lives in **`~/.config/muse-run/env`** (plain shell, sourced on every call; template in `env.example`, effective values from `muse-run --env`). Nothing in the repo is host-specific.

| Knob | Default | What it does |
|---|---|---|
| `MUSE_MODEL` | `opencode/muse-spark-1.3-contributor-free` | Model passed to `opencode run -m` |
| `MUSE_MAX_JOBS` | 2 | Max concurrent opencode processes |
| `MUSE_JOB_MB` / `MUSE_MEM_RESERVE_MB` | 800 / 1024 | A job starts only if `available − reserve ≥ job` (MB); available is the user slice's free memory (`memory.max − memory.current` under `/sys/fs/cgroup/user.slice/user-<uid>.slice`) when that slice has a cap, else `MemAvailable`/`vm_stat`. One opencode run is 580–900 MB RSS |
| `MUSE_START_WAIT` | 300 | Seconds `--start` polls for a slot before exit 4 |
| `MUSE_WAIT` | 540 | Foreground wait before `MUSE-RUN PENDING <id>` / exit 3 (stay under Claude's 600 s Bash cap) |
| `MUSE_MAX` | 3600 | Hard wall per job |
| `MUSE_JOBS` | `~/.cache/muse-run/jobs` | Job directories (`task`, `out.json`, `err`, `rc`, `pid`, `meta`); pruned after 2 days |
| `MUSE_OPENCODE` | `opencode` | Binary path, if not on PATH for detached jobs |
| `MUSE_SERVER` | unset | Opt-in attach to a persistent `opencode serve` (hung on short runs with 1.18.27) |

`env.example` carries four commented memory profiles: small VPS (4 cores / 8 GB), 16 GB laptop, 36 GB MacBook, 32 GB+ workstation. The memory gate, not `MUSE_MAX_JOBS`, is what does the real limiting on small hosts.

### The two caps

1. **Workflow concurrency** is hardcoded in Claude Code as `min(16, max(2, cpus − 2))` (2.1.261, 2026-09-05). `install.sh` prints yours. On a 4-core host that is 2, which is why `muse-run` has a detached-job protocol: a prompt starting with the line `MUSE-START` returns a job id in seconds, and a prompt `MUSE-WAIT <id>` collects the result later. Start every job first, then wait on all of them, and the running count is bounded by the memory gate instead of the harness. The command file has the Workflow snippet.
2. **Bash tool time** is 10 minutes per call. Jobs are detached (`setsid`, or a perl fallback on macOS), so `muse-run` only waits; past `MUSE_WAIT` it prints `MUSE-RUN PENDING <id>` and exits 3, and the relay loops `muse-run --wait <id>`. A job may run for `MUSE_MAX` (one hour).

## `muse-run` reference

```
muse-run [-d DIR] [-m provider/model] [-t SECONDS] "task"    run and wait
muse-run <<'EOF' … EOF                                       task on stdin
muse-run --start [-d DIR] "task"                             detach, print job id
muse-run --wait [-t SECONDS] ID                              wait, print answer
muse-run --status                                            list jobs, slots, free memory
muse-run --env                                               effective settings
```

Exit codes: 0 ok · 2 usage · 3 still running · 4 no slot · anything else is opencode's own code. Muse's text goes to stdout; the tool trace and token counts go to stderr.

Portable to Linux and macOS: reads `/proc/meminfo` or `vm_stat`, uses `timeout`/`gtimeout` when present and a bash watchdog otherwise, `setsid` when present and `perl -MPOSIX` otherwise. Bash 3.2 (stock macOS) is enough.

## On Sleeper: Muse on the Mac

Sleeper (4 cores, 7.6 GB) fits only 3–5 Muse jobs, so it can also send them to Petter's Mac: `mac-muse "task"`, or the `mac-muse` relay agent (`agentType: 'mac-muse'`, protocol lines `MAC-START` / `MAC-WAIT <id>`). It lives in phareim/sleeper (`bin/mac-muse`, `claude/agents/mac-muse.md`, docs in `mac/README.md`), not here, because it depends on that host's ssh tunnel. The job runs on a synced mirror of the repo and its changes come back as a git patch; up to 6 run at once on the Mac. When the Mac is asleep or full, `mac-muse` falls back to `muse-run` on Sleeper. The Mac's own `muse-run` install (this repo, `~/.config/muse-run/env`) is separate and only serves sessions started on the Mac.

## Known behaviour of Muse Spark 1.3

- **It does not verify unless told.** It reads and reasons but skips running tests, builds, or audits. Prompts that should verify must say so literally ("run `npm test` and paste the last 20 lines").
- Prompts are self-contained: Muse sees the repo (`AGENTS.md` through opencode) but nothing from the Claude conversation.
- Parallel editors need `isolation: 'worktree'` in the Workflow; `muse-run` runs in the agent's cwd.
- The Haiku relay must be told bluntly not to do the task itself, and not to `--wait` on a `MUSE-START` job. `agents/muse.md` says both; in a session older than an edit to it, add a one-line "RELAY NOTE" to the prompt.

## History

Built on the Sleeper server 2026-09-05 (previously in `phareim/sleeper` under `claude/{agents,bin,commands}`), lifted into this repo the same day so it installs on any machine. Session notes live in the private journal thread `muse-spark-testing`.
