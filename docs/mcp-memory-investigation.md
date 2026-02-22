# UCM/MCP Memory Investigation Log

Last updated: 2026-02-22T06:43:11-05:00

## Scope

Track findings about long-lived Unison MCP/UCM process memory growth and zombie children, plus baseline process snapshots before/after restart actions.

## Key Findings So Far

1. In the recommended setup, each agent gets its own independent `ucm mcp` process (`docs/mcp.md`).
2. `ucm mcp` is a long-lived in-process server (`unison-cli/src/Unison/MCP.hs`), not a short subprocess per tool call.
3. UCM launches MCP using persistent runtimes (`unison-cli/src/Unison/Main.hs`), which intentionally retain runtime state across requests.
4. Runtime cache population appears additive in the hot path:
   - `cacheAdd0` inserts new groups/maps into runtime cache state (`unison-runtime/src/Unison/Runtime/Machine.hs`).
   - `preEvalTopLevelConstants` also materializes cached values (`unison-runtime/src/Unison/Runtime/Machine.hs`).
5. Process memory observed is mostly anonymous/private memory (heap-like), not file-backed mappings.
6. FD/thread counts looked relatively flat per MCP process (roughly ~105 FDs, ~75 threads for most), which does not suggest a primary FD leak.
7. Zombies are present:
   - Most are under one interactive UCM process.
   - At least one MCP process also has zombie children.
8. Runtime cleanup path in persistent mode kills tracked forked runtime threads after eval (`unison-runtime/src/Unison/Runtime/Interface.hs`), and runtime exposes process APIs (`unison-runtime/src/Unison/Runtime/Foreign/Function.hs`), which is a plausible path for unreaped children if waiting threads are interrupted.

## Current Baseline Snapshot (Pre-Restart)

Command timestamp: `2026-02-22T06:39:44-05:00`

### MCP Processes (`/home/bbarker/workspace/unison/result/bin/unison mcp`)

Total MCP count: `9`  
Total MCP RSS: `18,728,196 KiB` (`17.86 GiB`)

| PID | PPID | Elapsed | Threads | VmRSS (MiB) | RssAnon (MiB) | VmSwap (MiB) | Zombie Children |
|---|---:|---|---:|---:|---:|---:|---:|
| 1844909 | 1844716 | 8-22:00:24 | 75 | 5672.7 | 5672.7 | 258.9 | 0 |
| 302840 | 302762 | 3-21:55:41 | 75 | 4885.1 | 4844.8 | 7.5 | 2 |
| 307839 | 307765 | 3-21:52:22 | 75 | 3229.8 | 3229.8 | 399.2 | 0 |
| 2510088 | 2509979 | 13-19:28:35 | 75 | 2248.9 | 2248.9 | 2459.0 | 0 |
| 3966797 | 3966734 | 11-13:48:08 | 75 | 1336.3 | 1336.2 | 83.9 | 0 |
| 3933978 | 3933763 | 7-23:53:51 | 75 | 644.7 | 644.7 | 226.1 | 0 |
| 3747985 | 3747772 | 9-22:09:47 | 75 | 217.1 | 217.1 | 24.9 | 0 |
| 1276286 | 1276213 | 3-13:05:34 | 57 | 28.2 | 28.2 | 3.9 | 0 |
| 2892207 | 2892133 | 6-14:14:32 | 58 | 26.5 | 26.5 | 0.2 | 0 |

### Interactive UCM Process (`/home/bbarker/workspace/unison/result/bin/unison`)

| PID | PPID | Elapsed | Threads | VmRSS (MiB) | RssAnon (MiB) | VmSwap (MiB) | Children | Zombie Children |
|---|---:|---|---:|---:|---:|---:|---:|---:|
| 2143558 | 2143557 | 4-22:53:09 | 129 | 8163.6 | 8118.2 | 89.6 | 85 | 84 |

## Evidence Pointers in Code

1. MCP process model and entrypoints:
   - `unison-cli/src/Unison/Main.hs`
   - `unison-cli/src/Unison/MCP.hs`
2. Persistent runtime setup and cleanup behavior:
   - `unison-runtime/src/Unison/Runtime/Interface.hs`
3. Runtime cache growth path:
   - `unison-runtime/src/Unison/Runtime/Machine.hs`
4. Runtime process primitives:
   - `unison-runtime/src/Unison/Runtime/Foreign/Function.hs`
5. MCP setup docs:
   - `docs/mcp.md`

## Planned Next Snapshot (Post-Restart)

After restarting the target UCM REPLs/MCP-connected processes, capture and append:

1. Same MCP table (`PID`, `VmRSS`, `RssAnon`, `VmSwap`, thread count, zombie children).
2. Aggregate MCP RSS total.
3. Interactive UCM table and zombie count.
4. Delta summary versus this baseline.

## Post-Restart Snapshot (After Restarting UCM REPL Processes)

Command timestamp: `2026-02-22T06:43:11-05:00`

### Quick Outcome

1. Restarting UCM REPL processes did **not** recycle MCP processes.
2. The same heavy MCP PIDs are still alive.
3. Interactive UCM memory and zombies dropped sharply after restart.
4. MCP PIDs are still parented by active `claude`/`codex` client processes.

### MCP Processes (Post-Restart)

Total MCP count: `9`  
Total MCP RSS: `19,066,936 KiB` (`18.18 GiB`)

| PID | PPID | Elapsed | Threads | VmRSS (MiB) | RssAnon (MiB) | VmSwap (MiB) | Zombie Children |
|---|---:|---|---:|---:|---:|---:|---:|
| 1844909 | 1844716 | 8-22:03:48 | 75 | 5672.7 | 5672.7 | 258.9 | 0 |
| 302840 | 302762 | 3-21:59:05 | 75 | 4885.1 | 4844.8 | 7.5 | 2 |
| 307839 | 307765 | 3-21:55:46 | 75 | 3229.8 | 3229.8 | 399.2 | 0 |
| 2510088 | 2509979 | 13-19:32:00 | 75 | 2524.6 | 2510.5 | 2197.4 | 0 |
| 3966797 | 3966734 | 11-13:51:32 | 75 | 1391.4 | 1375.7 | 44.4 | 0 |
| 3933978 | 3933763 | 7-23:57:15 | 75 | 644.7 | 644.7 | 226.1 | 0 |
| 3747985 | 3747772 | 9-22:13:11 | 75 | 217.1 | 217.1 | 24.9 | 0 |
| 1276286 | 1276213 | 3-13:08:58 | 57 | 28.2 | 28.2 | 3.9 | 0 |
| 2892207 | 2892133 | 6-14:17:56 | 58 | 26.5 | 26.5 | 0.2 | 0 |

### Interactive UCM Process (Post-Restart)

| PID | PPID | Elapsed | Threads | VmRSS (MiB) | RssAnon (MiB) | VmSwap (MiB) | Children | Zombie Children |
|---|---:|---|---:|---:|---:|---:|---:|---:|
| 910187 | 910186 | 00:53 | 58 | 302.6 | 255.7 | 0.0 | 0 | 0 |

### Delta vs Pre-Restart Baseline

1. MCP total RSS: `17.86 GiB` -> `18.18 GiB` (`+0.32 GiB`).
2. MCP process count: unchanged (`9`).
3. Large MCP PIDs: unchanged (no recycle happened).
4. Interactive UCM RSS: `8163.6 MiB` -> `302.6 MiB`.
5. Interactive UCM zombie children: `84` -> `0`.

### Memory Composition Recheck (Selected MCP PIDs)

Privileged `smaps_rollup` recheck still shows mostly anonymous/private memory:

1. `1844909`: ~`5808 MiB` anonymous.
2. `302840`: ~`4961 MiB` anonymous.
3. `307839`: ~`3307 MiB` anonymous.
4. `2510088`: ~`2571 MiB` anonymous.
5. `3966797`: ~`1409 MiB` anonymous.
