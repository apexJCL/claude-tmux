# two-row-status Specification

## Purpose
`bin/tmux-two-row-status` splits the tmux status line into two rows: the window list with `@status-top-right` on top, and status-left plus status-right below. It slices tmux's own default `status-format[0]` rather than carrying a copy.

## Requirements

### Requirement: Row Layout

The script SHALL set `status` to `2`. `status-format[0]` SHALL be the default format's window-list segment followed by `#{E:@status-top-right}` right-aligned. `status-format[1]` SHALL be the default format's status-left segment followed by its status-right segment.

#### Scenario: Applied to a stock tmux

- **GIVEN** a tmux server with the built-in `status-format[0]`
- **WHEN** the script runs
- **THEN** `status` is `2`
- **AND** `status-format[0]` contains `#{E:@status-top-right}`
- **AND** `status-format[1]` begins with the default status-left segment

### Requirement: Idempotent Reapplication

On first run the script SHALL store the pristine `status-format[0]` in `@status-format-default`, and every run SHALL slice that stored value, so running it again (config reload) produces the same result.

#### Scenario: Second run

- **GIVEN** the script has already run
- **WHEN** it runs again
- **THEN** both `status-format` rows are unchanged

### Requirement: Unfamiliar Default Is Left Alone

The script SHALL change nothing when the default format lacks the `#[list=on align=` anchor followed by the `#[nolist align=right range=right ` anchor, or when no format can be read.

#### Scenario: Customised format

- **GIVEN** `@status-format-default` lacks both anchors
- **WHEN** the script runs
- **THEN** `status` and both `status-format` rows are unchanged
