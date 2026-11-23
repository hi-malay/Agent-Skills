---
name: speed
description: Use when a Mac is slow, laggy, beachballing, fans loud, apps stalling or unresponsive, or when load average, swap and memory pressure look wrong and stray processes may be piling up. Also use when the user invokes /speed, cpu usage is high, lagging, ram/memory usage high.
---

# speed

Diagnose why a Mac is slow, then relieve it without destroying anything the user cares about.

**Core principle: measure before you kill.** The cause is almost never the process at the top of the memory list. Free RAM is not the goal and never was. macOS deliberately uses all of it.

## Iron rules

1. **Never kill anything you have not identified.** No `killall`, no pattern-kill you have not first printed and read.
2. **Never kill your own session or any of its ancestors.** Resolve your own PID chain first and exclude it explicitly.
3. **Anything holding state gets confirmed, never assumed.** Editors, databases, VMs, containers, long-running jobs, agent sessions.
4. **A kill that returns 0 proves nothing.** Re-check with `ps`. Signals get silently swallowed (see Gotchas).
5. **If it respawns, stop killing it.** Find the supervisor. Whack-a-mole wastes the user's time and yours.
6. **Report honestly.** Before and after numbers, and say plainly what you did not touch.

## Phase 1: Measure

Run these together. They take a second and decide everything after.

```bash
top -l 1 -n 0 | sed -n '3p;7p;8p'   # Load Avg, PhysMem, VM (swapins/swapouts)
sysctl -n vm.swapusage               # the real thrash signal
sysctl -n hw.ncpu hw.memsize         # core count (for load) and RAM bytes
df -h /System/Volumes/Data           # full disk mimics a slow machine
ps -Ao comm | sed 's|.*/||' | sort | uniq -c | sort -rn | head -20
ps -Ao rss,pid,%cpu,etime,comm | sort -rn | head -20
```

**Reading it:**

| Signal | Healthy | Problem | Means |
|---|---|---|---|
| Load average | roughly <= core count | several times core count | CPU contention or I/O wait |
| Swap used | well under total | near total | thrashing, the usual cause of whole-system lag |
| PhysMem unused | anything | near zero with big compressor | real memory exhaustion |
| Disk free | > 10% | < 5-10% | macOS purges caches constantly, everything crawls |
| Process counts | flat spread | one name repeated many times | duplication, the usual cause of process bloat |

Load average counts processes waiting on I/O, not just CPU. A very high load with idle CPU means waiting, usually on swap.

**Do not chase "free RAM".** Memory pressure and swap are the metrics. `purge` needs sudo, rarely helps, and can stall the machine. Skip it unless the user asks.

## Phase 2: Find the pattern

The count table from Phase 1 is the main clue. One name appearing many times is duplication, and duplication has a source.

For any suspicious cluster, resolve what owns it before touching it:

```bash
# parent chain of a PID: who started this, and who would restart it
p=<PID>; for i in 1 2 3 4 5; do
  read ppid comm <<< "$(ps -o ppid=,command= -p $p 2>/dev/null)"
  [ -z "$ppid" ] && break
  echo "  $p <- $(echo "$comm" | cut -c1-90)"
  p=$ppid
done

pgrep -P <PID>                          # its children
lsof -a -p <PID> -d cwd -Fn | grep ^n   # its working directory, often names the owner

# full descendant tree at any depth. Build the kill list from this, deepest first.
# MCP servers sit 3+ levels deep (agent -> npm exec -> server -> watchdog).
tree() { local p=$1 d=${2:-0}; printf "%*s%s %s\n" $d "" $p "$(ps -o command= -p $p | cut -c1-70)"; for c in $(pgrep -P $p); do tree $c $((d+2)); done; }
tree <PID>
```

`ppid` of 1 usually means orphaned. A live named parent means supervised, and killing the child alone will not stick.

## Phase 3: Identify yourself

Do this before building any kill list. Getting it wrong ends the session mid-cleanup.

```bash
p=$$; while [ -n "$p" ] && [ "$p" != "1" ]; do
  read ppid comm <<< "$(ps -o ppid=,command= -p $p 2>/dev/null)"
  [ -z "$ppid" ] && break
  echo "SELF-CHAIN: $p <- $(echo "$comm" | cut -c1-80)"
  p=$ppid
done
```

Every PID printed is off limits. Hard-code the exclusion into the kill loop rather than trusting a filter.

## Phase 4: Classify

| Tier | What | Action |
|---|---|---|
| **A. Never touch** | Anything owned by root. `kernel_task`, `launchd`, `WindowServer`, `loginwindow`, `mds*`, `coreaudiod`. Your own session chain. Anything you cannot identify. | Leave it. Report it if it is the bottleneck. |
| **B. Safe without asking** | Provably orphaned and stateless: dead parent, no open user files, trivially recreated on next launch. Duplicate idle helpers. Zombie wrappers. | Kill, then verify. |
| **C. Always confirm** | Anything with state or a window: editors, browsers, VMs, containers, databases, long-running agent or shell sessions, whole applications. | List them with age and working directory, then ask. |

**When unsure, it is Tier C.** The cost of asking is one question. The cost of guessing is the user's work.

Give the user real information when you ask: how many, how old, what directory they belong to, and what is recoverable afterwards. "Kill 10 stale sessions" is not a question a person can answer. "10 sessions, 14-19h old, all in ~/project, conversations resume with X" is.

Do not offer to kill something you already know will come back, like a language server (gopls, tsserver, pyright) that an open editor window owns. Offer to close that window instead.

When swap is nearly full, killing a few hundred MB barely changes the numbers. Put the real fix first in the question (close unused editor windows and browser tabs), and offer the kills after it.

System daemons burning CPU (`mds_stores`, `mobileassetd`, `duetexpertd`, `deleted`) are usually a symptom, not the cause. Spotlight reindexing or cache purging often means a full disk or a recent large file operation. Fix the cause, do not kill the daemon.

## Phase 5: Act

Order matters: **grandchildren, then children, then the parent.** Killing a parent first orphans its tree and can trigger a supervisor to restart everything.

Write the PIDs out explicitly, deepest first, from the Phase 2 `tree` output. Use an array, not a space-separated string. The Bash tool's shell may be zsh, and in zsh `for pid in $TARGETS` runs once with the whole string. `"${ARR[@]}"` works the same in bash and zsh.

```bash
TARGETS=(27816 27815 27796 27624)     # explicit, deepest first, from tree output
SELF=" 34360 33632 2053 1505 "        # every Phase 3 PID, padded with spaces
for pid in "${TARGETS[@]}"; do
  case "$SELF" in *" $pid "*) echo "SKIP self $pid"; continue;; esac   # hard guard
  /bin/kill -TERM "$pid" 2>/dev/null
done
sleep 3
for pid in "${TARGETS[@]}"; do
  case "$SELF" in *" $pid "*) continue;; esac
  ps -p "$pid" >/dev/null && { echo "KILL $pid"; /bin/kill -9 "$pid"; }
done
```

Send `TERM` first so anything that wants to flush state can, then `KILL` whatever survives (the loop above does this). For whole applications, ask the app to quit rather than killing it, so it saves normally:

```bash
osascript -e 'tell application "<App>" to quit'
```

## Phase 6: Verify

Never report success from the exit status of a kill. Re-measure:

```bash
ps -Ao comm | sed 's|.*/||' | sort | uniq -c | sort -rn | head -10
top -l 1 -n 0 | sed -n '3p;7p'
sysctl -n vm.swapusage
```

Then wait and check once more. Load average is a decaying average and lags the fix by a minute or two. A shrinking swap *total* (not just used) is the strongest sign the pressure genuinely lifted, because macOS only reclaims swap files once the pressure is gone.

Also check for respawns: grep for the killed command names and compare PIDs and `etime`. A new PID a few seconds old means a supervisor brought it back (rule 5).

Report before and after side by side, and state what you deliberately left running. If swap total did not shrink, say so plainly. Freed RAM gets refilled from swap and the compressor right away, so the only lasting fix is fewer open apps.

## Gotchas

| Symptom | Cause | Fix |
|---|---|---|
| `kill` returns exit 0, process still alive | Agent sandbox silently drops signals to processes outside it | Verify with `ps`. Re-run with the runtime's sandbox escape (see Runtime notes). Never trust the exit code. |
| `kill: illegal pid: 123 456 789`, or the loop runs once and nothing dies | zsh does not word-split unquoted `$VAR`. The Bash tool may run zsh. | Use an array with `"${ARR[@]}"`. Check survivors with `ps` every time. |
| Great-grandchild survives or ends up orphaned | Kill loop only went 2 levels deep | Build the list from the recursive `tree` helper, not a fixed-depth loop |
| Language server (gopls, tsserver, pyright) back within seconds | The editor extension in an open window restarts it | Do not offer it as a kill option. Close that editor window. |
| Killed it, it came back seconds later | A supervisor restarts it | Walk the parent chain. Stop the supervisor or disable its config entry. Do not loop-kill. |
| Killed a parent, children became orphans | Wrong order | Children first, then parent |
| Load average stays high after cleanup | It is a 1/5/15 minute decaying average | Wait a minute and re-check. Trust swap and process count for immediate feedback. |
| High CPU in `mds_stores`, `deleted`, `mobileassetd` | Spotlight reindex or cache purge, often from a full disk | Check `df`. Treat the cause, not the daemon. |
| `top` shows huge memory "used" but machine is fine | macOS caches aggressively by design | Ignore. Read memory pressure and swap instead. |

## Patterns worth checking

Hints, not a checklist. The method above finds the real answer; these are just clusters that show up often on developer machines.

- **Duplicated tool stacks.** Dev tooling that spawns a fleet of helper processes per session (language servers, tool servers, watchers, indexers) multiplies when sessions accumulate. One name with a double-digit count in the Phase 1 table.
- **One editor window = one full extension stack.** Each VS Code/Cursor window has its own extension host (`Code Helper (Plugin)`), and that host starts every extension's helpers: AI agents, language servers, env tools. N open windows means N copies. Map each host PID to a project with `lsof cwd` on its children. Closing unused windows is the biggest clean win.
- **Long-lived sessions nobody closed.** Terminal, editor or agent sessions left open for many hours, each holding its own helper tree. Often the single biggest contributor, and usually invisible because each one looks small.
- **Two of the same class of app.** Two editors, two browsers, two container runtimes, where only one is in use.
- **Background VMs and container runtimes** idling with memory reserved from a task that finished long ago.
- **Watchers on large trees.** File watchers or sync clients over big directories, showing steady CPU with no user activity.

In every case the process is cheap on its own. The cost is the multiplier. Report the multiplier, not the individual size.

## Runtime notes

Sandboxes block signals to processes outside them, and they do it silently.

- **Claude Code:** pass `dangerouslyDisableSandbox: true` on the Bash call that sends signals. Keep that call narrowly scoped to the PID list you already printed, never a broad pattern.
- **Codex:** request escalated permissions for the signalling command.
- **Either way:** the diagnostic phases need no escalation. Only signalling does. Escalate as late as possible and as narrowly as possible.
