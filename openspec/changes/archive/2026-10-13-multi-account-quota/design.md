## Context

- The reporter (`bin/claude-tmux-status`) runs as Claude Code's `statusLine` command, so it is a descendant of the `claude` process and inherits its environment, including `CLAUDE_CONFIG_DIR` and `TMUX_PANE`. On this machine the ancestry is `statusLine shell → claude → pane shell → tmux`.
- The badge (`bin/tmux-claude-widget`) runs as a tmux `#()` job. A job has no reliable idea of which client or pane it is drawn for. Only the format that invokes it does, through `#{pane_id}`, which is the active pane of the client's current window.
- tmux caches `#()` output by command string, and reruns a job at most once per `status-interval` unless the command string changes.
- Quotas are per account, not per session (see `openspec/specs/quota-reporting`), so "which session is in this pane" only matters for knowing which account it uses.

## Goals / Non-Goals

**Goals:**
- Map the focused pane to an account without reading another process's environment. That is not possible on macOS without elevated rights.
- Keep the badge free of polling and daemons, and keep it working when called with only `<variant> [sepbg]`.
- Keep every scenario testable in `tests/run.sh` with a throwaway `$HOME` and an isolated tmux server.

**Non-Goals:**
- Showing two accounts at once (side-by-side badges).
- Detecting Claude sessions that were started before this change and have not reported since. They are picked up on their next status line refresh.
- Per-session (as opposed to per-account) figures such as context or cost in the badge.

## Decisions

### Attribution is pushed by the reporter, keyed by pane id

The reporter writes `~/.cache/claude-tmux/panes/<n>` (`<account> <pid>`) whenever `TMUX_PANE=%<n>`. The badge only reads that one file.
*Alternatives:* (a) The badge walks `#{pane_pid}`'s children and reads `CLAUDE_CONFIG_DIR` from `ps eww` or `/proc/<pid>/environ`. On macOS `ps` withholds the environment of other processes, and walking the process tree on every status redraw is costly. (b) The reporter tags the pane with a tmux pane option (`set -p @claude-account`). That makes the reporter talk to tmux, which `quota-reporting` deliberately avoids, and it fails silently when a different tmux socket is in use. Files keep both scripts tmux-agnostic on the write side.

### Liveness by Claude's PID, not by freshness

The statusLine command only runs when the conversation changes, so an idle session never refreshes its file, and a freshness window would wrongly expire it. The reporter therefore walks `ps -o ppid=,comm=` upward, with at most 8 hops, to the nearest ancestor whose `comm` basename is `claude`. It falls back to `$PPID`, which covers npm installs where the process is named `node`. The badge checks `kill -0 <pid>`. When the user quits Claude and the pane returns to its shell, the PID dies and the pane falls back to the pin.
*Alternative:* comparing `#{pane_current_command}` to `claude`. That breaks for `node` installs and while Claude runs a foreground tool.

### Background sessions are matched by session id

A Claude session started in the background runs under `claude daemon`, not in the pane. The pane only runs a thin `claude attach <short-id>` client, so the session's status line has no `TMUX_PANE` and writes no pane file. The reporter therefore also writes `sessions/<session_id>` = `<account> <pid>` from the payload's `session_id`. When the pane has no pane file, the badge takes `#{pane_pid}`, finds a child running `claude attach <id>`, and matches `<id>` as a prefix of exactly one session file whose PID is alive. The attach id is the leading part of the full session UUID (for example, `2d2bb59a` for `2d2bb59a-35a0-...`). This costs one `ps` call per render, and only when the pane-file fast path misses. Alternative considered: reading the daemon's own registry. Rejected, because its format is internal and undocumented.

### Pin and auto flags are passed as format arguments, appearance is read from tmux

`#{@claude-quota-pin}` and `#{@claude-quota-auto}` are part of the `#()` command string. Changing them therefore changes the string, and tmux runs the badge again on the next redraw instead of waiting up to `status-interval`. Appearance options change rarely and there can be one per account, so the badge reads them with a single `tmux show-options -gq` call, filtered to `@claude-quota-` keys. If the call fails (no server), the badge uses the defaults. This keeps the existing badge tests, which run outside tmux, valid.

### Account naming stays backward compatible

`personal` keeps the bare `quota` file, and `work` keeps `quota-work`, so existing caches and the existing reporter tests carry over. Names are sanitised to `[A-Za-z0-9_-]`, because they become file names and tmux option suffixes.

### Inverted palette is derived, not configured

The user asked for a near-black background, a barely visible orange gauge and strong orange text. These are derived from whatever fill colour is in effect: the shadow is each channel divided by 4, so `#F08C00` gives `#3C2300` and `#E8553A` gives `#3A150E`. This way every preset and custom scheme gets an inverted form without a second palette. "The strong orange used when reaching 100%" is read as the gauge's fill colour (`#F08C00`). Past the alarm threshold the alarm fill `#E8553A` takes its place, so the inverted badge still signals the alarm.

### Pinned style wins when detected == pinned

If the focused pane runs the account that is already pinned, inverting the badge would tell the user nothing new. Inversion therefore means "you are looking at an account other than your pin".

### Menu via `display-menu`, built from state files

`bin/tmux-claude-menu` lists the accounts with a state file, so there is no separate registry to maintain. Each item runs `set -g` or `set -gu`, followed by `refresh-client -S`. Tests stub `tmux` on `PATH` with a recorder to check the `display-menu` arguments, because a real menu needs an attached client.

## Risks / Trade-offs

- [Formats inside `#()` must be expanded by tmux before the job runs.] → Verified on tmux 3.7c with a pty-attached client: `#{pane_id}` → `%0`, and an unset `#{@opt}` → empty string. `set -g` alone redraws every attached client, and the changed command string reruns the job right away. The badge still treats a literal `#{...}` argument as absent, for older tmux versions.
- [Switching panes changes the command string, so the first draw for a new string can be briefly blank while the job runs.] → The badge is fast (one `read`, one `tmux show`). If the flicker is noticeable, a follow-up can make the badge print synchronously cached output. This is a known trade-off, and it does not change the specs.
- [PID reuse could make a dead attribution look alive.] → It is unlikely within a pane's life. The reporter prunes dead entries, and `%n` ids are not reused within a tmux server's lifetime.
- [Attribution files accumulate across tmux server restarts, when pane ids restart at `%0`.] → Pruning by PID removes stale entries. A reused id with a live, unrelated PID is the same PID-reuse risk as above.
- [The `cyan` preset matches tmux2k's clock background (`#80FFEA`), so the separator edge may blend in.] → This is cosmetic; the user chooses the preset.
- [The badge CLI gains positional arguments.] → They are optional. Omitting them keeps today's single-account behaviour.

## Migration Plan

1. Install as before (`./install.sh` symlinks the new `bin/tmux-claude-menu`).
2. Replace the tmux.conf block with the new `tmux/claude-tmux.conf` and reload tmux.
3. Running Claude sessions start attributing their panes on their next status line refresh. No restart is needed.

Rollback: restore the previous conf block. Old reporters ignore `panes/`, and the old badge ignores the extra arguments.
