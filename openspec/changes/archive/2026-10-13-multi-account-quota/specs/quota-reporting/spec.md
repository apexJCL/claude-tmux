## MODIFIED Requirements

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

## ADDED Requirements

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
