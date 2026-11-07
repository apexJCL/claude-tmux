## Purpose

`bin/tmux-claude-menu` lets the user choose which Claude account the quota badges pin, and turn pane-based auto-detection on or off, from a tmux menu. The badge reads the choice from the global tmux options `@claude-quota-pin` and `@claude-quota-auto`.

## ADDED Requirements

### Requirement: Known Accounts

The menu SHALL list one item per account with a non-empty state file in `~/.cache/claude-tmux`: `personal` for `quota`, and `<name>` for each `quota-<name>`, but not for `*.tmp` files. `personal` SHALL come first, followed by the other accounts in alphabetical order. The currently pinned account (the value of `@claude-quota-pin`, or `personal` when it is unset) SHALL have its label prefixed with `* `. When no account has reported, the menu SHALL show a single disabled item `No account has reported yet`.

#### Scenario: Two accounts reported

- **GIVEN** `quota`, `quota-work` and `quota-work.tmp` exist, and `@claude-quota-pin` is unset
- **WHEN** the menu opens
- **THEN** its account items are `* personal` then `work`, and nothing else

#### Scenario: Nothing reported

- **GIVEN** `~/.cache/claude-tmux` holds no state file
- **WHEN** the menu opens
- **THEN** it shows the disabled item `No account has reported yet`

### Requirement: Pin Selection

Choosing an account item SHALL set the global option `@claude-quota-pin` to that account. An `Unpin` item SHALL unset the option, which makes `personal` the pinned account again. After any change, the menu SHALL refresh the status line of every client, so the badge updates immediately.

#### Scenario: Pin the work account

- **WHEN** the user chooses `work`
- **THEN** `@claude-quota-pin` is `work`
- **AND** the status line is refreshed

#### Scenario: Unpin

- **GIVEN** `@claude-quota-pin` is `work`
- **WHEN** the user chooses `Unpin`
- **THEN** `@claude-quota-pin` is unset

### Requirement: Auto-Detection Toggle

The menu SHALL show `Auto-detect: on` when `@claude-quota-auto` is anything other than `off`, and `Auto-detect: off` otherwise. Choosing that item SHALL set the option to the opposite value and refresh the status line.

#### Scenario: Turn auto-detection off

- **GIVEN** `@claude-quota-auto` is unset
- **WHEN** the user chooses `Auto-detect: on`
- **THEN** `@claude-quota-auto` is `off`

### Requirement: Key Binding

The shipped `tmux/claude-tmux.conf` SHALL bind `prefix + Q` to open the menu. It SHALL pass `#{pane_id}`, `#{@claude-quota-pin}`, `#{@claude-quota-auto}` and `#{pane_pid}` to every badge invocation.

#### Scenario: Shipped configuration

- **WHEN** `tmux/claude-tmux.conf` is read
- **THEN** it binds `Q` to `tmux-claude-menu`
- **AND** each `tmux-claude-widget` call passes the four formats
