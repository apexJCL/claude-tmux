# quota-reporting Specification

## Purpose
`bin/claude-tmux-status` is Claude Code's `statusLine` command. It prints the in-app status line and records the account's rate-limit usage (5-hour and 7-day windows) to a state file that `quota-badge` reads. Quotas are per account, not per session, so any running session is an equally good reporter.

## Requirements

### Requirement: Account Selection

The reporter SHALL name the account after `CLAUDE_CONFIG_DIR`:

- unset, empty, or equal to `$HOME/.claude`: `personal`
- `$HOME/.claude-<name>`: `<name>`
- any other directory: its basename, with a leading `.` and then a leading `claude-` removed

Characters other than `A-Z a-z 0-9 _ -` in the name SHALL become `-`. If the resulting name is empty, the account SHALL be `personal`. The state file SHALL be `~/.cache/claude-tmux/quota` for `personal` and `~/.cache/claude-tmux/quota-<name>` for any other account.

#### Scenario: Work account

- **GIVEN** `CLAUDE_CONFIG_DIR=$HOME/.claude-work`
- **WHEN** the reporter runs
- **THEN** it writes `~/.cache/claude-tmux/quota-work`
- **AND** the status line shows `[work]`

#### Scenario: Personal account

- **GIVEN** `CLAUDE_CONFIG_DIR` is unset, empty, or `$HOME/.claude`
- **WHEN** the reporter runs
- **THEN** it writes `~/.cache/claude-tmux/quota`
- **AND** the status line shows `[personal]`

#### Scenario: Any other config directory

- **GIVEN** `CLAUDE_CONFIG_DIR=/opt/agents/.claude-client a`
- **WHEN** the reporter runs
- **THEN** it writes `~/.cache/claude-tmux/quota-client-a`
- **AND** the status line shows `[client-a]`

### Requirement: Quota State File

The reporter SHALL write one line `<5h used> <5h resets_at> <7d used> <7d resets_at> <written>`: whole-number percentages (floored), epoch-second reset times, and the epoch second of the write. It SHALL write only when the payload carries the weekly window. The 5h window is optional: when the payload has none, the reporter SHALL write `-1` for its usage and `0` for its reset time. It SHALL write to `<state>.tmp` and rename it over the state file, so a reader never sees a partial line. It SHALL create `~/.cache/claude-tmux` when absent.

#### Scenario: Payload carries both windows

- **GIVEN** a payload with `rate_limits.five_hour.used_percentage = 41.7`, `rate_limits.five_hour.resets_at = 1000`, `rate_limits.seven_day.used_percentage = 12.2`, `rate_limits.seven_day.resets_at = 2000`
- **WHEN** the reporter runs at epoch second `T`
- **THEN** the state file contains `41 1000 12 2000 T`

#### Scenario: Account without a 5h window

- **GIVEN** a payload with `rate_limits.seven_day` (`used_percentage = 12.2`, `resets_at = 2000`) but no `rate_limits.five_hour`, as verified Ultra accounts send since 2026-10-30
- **WHEN** the reporter runs at epoch second `T`
- **THEN** the state file contains `-1 0 12 2000 T`

#### Scenario: Payload without a weekly window

- **GIVEN** a payload whose `rate_limits` has no `seven_day`
- **WHEN** the reporter runs
- **THEN** the state file is left as it was

#### Scenario: Payload without subscription limits

- **GIVEN** a payload with no `rate_limits` (API-key authentication)
- **WHEN** the reporter runs
- **THEN** the state file is left as it was

#### Scenario: Payload without a directory (known gap)

- **GIVEN** a payload with neither `workspace.current_dir` nor `cwd`
- **WHEN** the reporter runs
- **THEN** it currently shifts every later field left by one, because consecutive tabs collapse under `IFS=$'\t'`
- **AND** it overwrites the state file with misaligned values

#### Scenario: Unparseable payload (known gap)

- **GIVEN** a payload that is not valid JSON
- **WHEN** the reporter runs
- **THEN** it currently overwrites the state file with empty fields followed by the timestamp
- **AND** `quota-badge` consequently prints nothing until the next valid report

### Requirement: In-App Status Line

The reporter SHALL print one line: `<icon> [<account>] <model> · <dir> · <ctx>% (<used>/<window>) · $<cost>`. `<icon>` is U+EC82. `<model>` is `model.display_name` (default `claude`). `<dir>` is `workspace.current_dir`, else `cwd`, with a leading `$HOME` shown as `~`. `<ctx>` is `context_window.used_percentage` rounded. `<used>` is total input plus output tokens and `<window>` is `context_window.context_window_size`, both abbreviated: values of at least 1,000,000 as `N.NM` (truncated), values of at least 1,000 as `Nk` (truncated), smaller values as-is. `<cost>` is `cost.total_cost_usd` rounded to cents.

#### Scenario: Typical session

- **GIVEN** model `Opus`, directory `$HOME/proj`, context 23.4%, 58,436 tokens used of 1,240,000, cost 1.234 USD, personal account
- **WHEN** the reporter runs
- **THEN** it prints `<icon> [personal] Opus · ~/proj · 23% (58k/1.2M) · $1.23`

### Requirement: Pane Attribution

When `TMUX_PANE` is set to `%<n>`, the reporter SHALL write `~/.cache/claude-tmux/panes/<n>` with one line, `<account> <pid>`. `<pid>` SHALL be the nearest ancestor process whose command name is `claude`; if there is none, it SHALL be the reporter's parent process. The reporter SHALL write this file whether or not the payload carries `rate_limits`. It SHALL write through a temporary file and a rename, and SHALL create the directory when it is absent. When `TMUX_PANE` is unset or empty, the reporter SHALL NOT write any attribution file. Each run SHALL delete any attribution file whose `<pid>` is no longer running.

#### Scenario: Claude in a tmux pane

- **GIVEN** `TMUX_PANE=%7` and `CLAUDE_CONFIG_DIR=$HOME/.claude-work`, with the reporter running under a process named `claude` with PID `P`
- **WHEN** the reporter runs
- **THEN** `~/.cache/claude-tmux/panes/7` contains `work P`

#### Scenario: Outside tmux

- **GIVEN** `TMUX_PANE` is unset
- **WHEN** the reporter runs
- **THEN** `~/.cache/claude-tmux/panes/` gains no file

#### Scenario: API-key session still attributes its pane

- **GIVEN** `TMUX_PANE=%3` and a payload with no `rate_limits`
- **WHEN** the reporter runs
- **THEN** `~/.cache/claude-tmux/panes/3` is written
- **AND** the state file is left as it was

#### Scenario: Dead attribution pruned

- **GIVEN** `~/.cache/claude-tmux/panes/9` names a PID that is not running
- **WHEN** the reporter runs from any pane
- **THEN** `~/.cache/claude-tmux/panes/9` no longer exists

### Requirement: Session Attribution

When the payload carries a `session_id`, the reporter SHALL write `~/.cache/claude-tmux/sessions/<session_id>` with one line, `<account> <pid>`, where `<pid>` follows the rule in Pane Attribution. Characters other than `A-Z a-z 0-9 _ -` in the id SHALL become `-`. The reporter SHALL write this file whether or not `TMUX_PANE` is set and whether or not the payload carries `rate_limits`, through a temporary file and a rename. Each run SHALL delete any session file whose `<pid>` is no longer running. This lets the badge find the account of a background session, whose status line runs outside any tmux pane.

#### Scenario: Background session

- **GIVEN** `TMUX_PANE` is unset, `CLAUDE_CONFIG_DIR=$HOME/.claude-work`, and a payload with `session_id = 2d2bb59a-35a0-486e-829e-bf780556d8c8`, with the reporter running under a process named `claude` with PID `P`
- **WHEN** the reporter runs
- **THEN** `~/.cache/claude-tmux/sessions/2d2bb59a-35a0-486e-829e-bf780556d8c8` contains `work P`
- **AND** `~/.cache/claude-tmux/panes/` gains no file

#### Scenario: Dead session pruned

- **GIVEN** `~/.cache/claude-tmux/sessions/abc` names a PID that is not running
- **WHEN** the reporter runs
- **THEN** `~/.cache/claude-tmux/sessions/abc` no longer exists
