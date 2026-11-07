# quota-badge Specification

## Purpose
`bin/tmux-claude-widget <variant> [sepbg] [pane] [pin] [auto] [pane_pid]` renders one tmux status badge for one rate-limit window, from the state files `quota-reporting` writes. It shows the account Claude runs in the active pane, or else the pinned account. It needs no running Claude session and no polling daemon.

## Requirements

### Requirement: State Source

The badge SHALL read only the state file of the account chosen by Account Resolution: `~/.cache/claude-tmux/quota` for `personal`, `~/.cache/claude-tmux/quota-<name>` otherwise. It SHALL print nothing when that file is missing or empty, when the line has no `written` field, when `written` is more than 604,800 seconds (7 days) old, or when the variant is neither `session` nor `week`.

#### Scenario: Work account is not displayed

- **GIVEN** `quota-work` exists and `quota` does not, nothing is pinned, and the active pane is not running Claude
- **WHEN** the badge renders
- **THEN** it prints nothing, because the displayed account is `personal`

#### Scenario: Pinned account has not reported

- **GIVEN** `quota` exists, `quota-work` does not, the pin is `work`, and the active pane is not running Claude
- **WHEN** the badge renders
- **THEN** it prints nothing

#### Scenario: Stale report

- **GIVEN** a state line written 604,801 seconds ago
- **WHEN** the badge renders
- **THEN** it prints nothing

### Requirement: Window Variants

`session` SHALL show the 5-hour window with the time left as `HH:MM`. `week` SHALL show the 7-day window with the local reset date as `MM/DD`. The label SHALL be ` <logo> <used>% │ <icon> <when> `. `<logo>` SHALL be the displayed account's icon (see Account Appearance), which defaults to U+F0674 (nf-md-creation). `<icon>` SHALL be U+F0954 (clock) for `session` and U+F00ED (calendar) for `week`. Glyphs are named by codepoint here because an editor or font can drop them silently.

#### Scenario: Session time left

- **GIVEN** 5-hour usage 50% resetting 2h13m from now
- **WHEN** `session` renders
- **THEN** the label reads ` <logo> 50% │ <clock> 02:13 `

#### Scenario: Week reset date

- **GIVEN** 7-day usage 41% resetting on 21 September (local time)
- **WHEN** `week` renders
- **THEN** the label reads ` <logo> 41% │ <calendar> 09/21 `


### Requirement: Accounts Without A 5-Hour Window

When the displayed account's state line records 5-hour usage `-1` (no 5-hour window, as for verified Ultra accounts), both variants SHALL use the 7-day window and its alarm threshold. `session` SHALL label ` <logo> <calendar> <MM/DD> <HH:MM> ` with the window's local reset time and date (`--/-- --:--` once it has passed). `week` SHALL drop the `│ <icon> <when>` part and centre ` <used>%` on a badge as wide as the regular `week` label, keeping ` <logo> ` at its left edge. Accounts that have a 5-hour window render both variants as usual.

#### Scenario: Session shows the weekly reset date-time

- **GIVEN** 5-hour usage `-1` and 7-day usage 26% resetting at 09:00 on 15 January (local time)
- **WHEN** `session` renders
- **THEN** the label reads ` <logo> <calendar> 01/15 09:00 ` and the gauge fills 26%

#### Scenario: Week centres the percentage

- **GIVEN** 5-hour usage `-1` and 7-day usage 26%
- **WHEN** `week` renders
- **THEN** the label is ` <logo> ` followed by `26%` centred on the regular badge width, with no reset date

### Requirement: Window Rollover

When a window's `resets_at` has passed, the badge SHALL show it as `0%`, because a rolled-over window is empty. Its next reset is unknown until a session reports again, so `<when>` SHALL be `--:--` (session) or `--/--` (week). When `resets_at` is `0` or less, `<when>` SHALL be the same placeholder and the reported percentage SHALL be kept.

#### Scenario: Reset has passed

- **GIVEN** 5-hour usage 87% with `resets_at` in the past
- **WHEN** `session` renders
- **THEN** the label reads ` <logo> 0% │ <clock> --:-- `

### Requirement: Gauge Fill And Alarm Colours

The badge background SHALL fill left to right in proportion to usage: the first `round(used × width / 100)` label cells (half rounds up, clamped to `0..width`) take the fill colour, the rest the base colour, and the split SHALL land on a whole cell. Base and fill SHALL come from the displayed account's colour scheme (see Account Appearance), which defaults to base `#FFCA80` / fill `#F08C00`. At `≥ 90%` for `session` and `≥ 80%` for `week`, they SHALL switch to base `#FF9580` / fill `#E8553A`, whatever the scheme. In the pinned style, text SHALL be `#0B0D0F`. The auto-detected style is defined by Inverted Style.

#### Scenario: Week alarm threshold

- **GIVEN** 7-day usage 80%
- **WHEN** `week` renders
- **THEN** it uses the alarm colours

#### Scenario: Session below threshold

- **GIVEN** 5-hour usage 89%
- **WHEN** `session` renders
- **THEN** it uses the normal colours

#### Scenario: Empty gauge

- **GIVEN** usage 0%
- **WHEN** the badge renders
- **THEN** no cell takes the fill colour

#### Scenario: Alarm overrides a custom scheme

- **GIVEN** the displayed account's scheme is `green` and 5-hour usage is 95%
- **WHEN** `session` renders
- **THEN** it uses base `#FF9580` / fill `#E8553A`

### Requirement: Self-Contained Powerline Segment

The badge SHALL emit its own leading powerline separator (U+E0B2), with foreground equal to the colour of the first run (fill if any cell is filled, else base) and background equal to `sepbg`. `sepbg` defaults to `#80FFEA`. The badge SHALL end with `#[norange default]`. When it prints nothing, no separator remains.

#### Scenario: Default separator background

- **GIVEN** no `sepbg` argument and usage 50%
- **WHEN** the badge renders
- **THEN** output begins `#[fg=#F08C00,bg=#80FFEA]`

### Requirement: Account Resolution

The badge SHALL accept `tmux-claude-widget <variant> [sepbg] [pane] [pin] [auto] [pane_pid]`. `pane` is a tmux pane id (`%<n>`), `pin` an account name, `auto` either `on` or `off`, and `pane_pid` the PID of the pane's own process. The pinned account SHALL be `pin`, or `personal` when `pin` is empty or absent. Auto-detection SHALL be on unless `auto` is `off`. When auto-detection is on, the badge SHALL detect the pane's account as follows:

1. **Direct session.** `pane` is `%<n>`, `~/.cache/claude-tmux/panes/<n>` exists, and its PID is running: its account.
2. **Attached background session.** Otherwise, `pane_pid` or one of its direct children runs `claude attach <id>`, exactly one file in `~/.cache/claude-tmux/sessions/` has a name starting with `<id>`, and that file's PID is running: its account.

If an account is detected and its state file passes the State Source checks, the badge SHALL display it. Otherwise it SHALL display the pinned account.

The display SHALL use the auto-detected style (Inverted Style) only when it shows a detected account that differs from the pinned account. In every other case it SHALL use the pinned style.

#### Scenario: No arguments beyond the variant

- **GIVEN** only `quota` exists
- **WHEN** `tmux-claude-widget session` renders
- **THEN** it shows the `personal` account in the pinned style

#### Scenario: Active pane runs another account

- **GIVEN** pin `personal`, auto on, and `panes/4` reading `work <running pid>`, with `quota` and `quota-work` both fresh
- **WHEN** the badge renders with pane `%4`
- **THEN** it shows the `work` figures in the inverted style

#### Scenario: Active pane runs the pinned account

- **GIVEN** pin `work`, auto on, and `panes/4` reading `work <running pid>`
- **WHEN** the badge renders with pane `%4`
- **THEN** it shows `work` in the pinned style

#### Scenario: Claude has exited in the pane

- **GIVEN** `panes/4` reading `work <pid that is not running>` and pin `personal`
- **WHEN** the badge renders with pane `%4`
- **THEN** it shows `personal` in the pinned style

#### Scenario: Auto-detection off

- **GIVEN** `panes/4` reading `work <running pid>`, pin `personal`, and auto `off`
- **WHEN** the badge renders with pane `%4`
- **THEN** it shows `personal` in the pinned style

#### Scenario: Pane attached to a background session

- **GIVEN** pin `personal`, no `panes/4`, pane PID `S` with a child running `claude attach 2d2bb59a`, and `sessions/2d2bb59a-35a0-486e-829e-bf780556d8c8` reading `work <running pid>`, with `quota-work` fresh
- **WHEN** the badge renders with pane `%4` and pane PID `S`
- **THEN** it shows the `work` figures in the inverted style

#### Scenario: Attached session never reported

- **GIVEN** pin `personal`, no `panes/4`, and pane PID `S` with a child running `claude attach 0000beef`, with no matching session file
- **WHEN** the badge renders with pane `%4` and pane PID `S`
- **THEN** it shows `personal` in the pinned style

#### Scenario: Detected account has no usable report

- **GIVEN** `panes/4` reading `api <running pid>`, no `quota-api`, and pin `personal`
- **WHEN** the badge renders with pane `%4`
- **THEN** it shows `personal` in the pinned style

### Requirement: Inverted Style

In the auto-detected style, the base colour SHALL be `#0B0D0F`. The gauge fill SHALL be the shadow of the effective fill colour (the scheme fill, or `#E8553A` past the alarm threshold), where the shadow is each RGB channel divided by 4 and floored. The text SHALL be the effective fill colour. Gauge proportion, label and separator rules SHALL be the same as in the pinned style.

#### Scenario: Default scheme inverted

- **GIVEN** the auto-detected style, the default scheme, and 5-hour usage 50%
- **WHEN** `session` renders
- **THEN** filled cells are `#[fg=#F08C00,bg=#3C2300]` and the rest `#[fg=#F08C00,bg=#0B0D0F]`

#### Scenario: Alarm inverted

- **GIVEN** the auto-detected style and 5-hour usage 95%
- **WHEN** `session` renders
- **THEN** filled cells are `#[fg=#E8553A,bg=#3A150E]`

### Requirement: Account Appearance

The badge SHALL read the displayed account's appearance from the global tmux options `@claude-quota-scheme-<account>` and `@claude-quota-icon-<account>`. A scheme SHALL be either a preset name or a custom `#RRGGBB,#RRGGBB` (base, fill) pair. The presets (base / fill) are:

| Preset | Base | Fill |
|--------|------|------|
| `orange` | `#FFCA80` | `#F08C00` |
| `yellow` | `#FFFF80` | `#C8C800` |
| `green` | `#8AFF80` | `#3CC832` |
| `cyan` | `#80FFEA` | `#20C8AC` |
| `pink` | `#FF80BF` | `#E0408A` |

An unset, unknown or malformed scheme SHALL mean `orange`. A non-empty icon SHALL replace the default logo. When tmux cannot be queried, the badge SHALL use the defaults.

#### Scenario: Preset scheme

- **GIVEN** `@claude-quota-scheme-work` is `green` and `work` is displayed at 50% in the pinned style
- **WHEN** `session` renders
- **THEN** filled cells use background `#3CC832` and the rest `#8AFF80`

#### Scenario: Custom scheme

- **GIVEN** `@claude-quota-scheme-work` is `#AABBCC,#112233`
- **WHEN** `work` renders below the alarm threshold
- **THEN** base is `#AABBCC` and fill is `#112233`

#### Scenario: Malformed scheme

- **GIVEN** `@claude-quota-scheme-work` is `teal`
- **WHEN** `work` renders
- **THEN** it uses the `orange` colours

#### Scenario: Custom icon

- **GIVEN** `@claude-quota-icon-work` is U+F0BBF
- **WHEN** `work` renders
- **THEN** the label begins ` <U+F0BBF> `
