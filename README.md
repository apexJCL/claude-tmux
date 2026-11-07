# claude-tmux

A tmux status badge for Claude Code subscription quota: one badge for the 5-hour window (usage and time left), one for the 7-day window (usage and reset date). Each badge is also a gauge, filled left to right in proportion to usage.

## How it works

| Piece | Role | Spec |
|-------|------|------|
| `bin/claude-tmux-status` | Claude Code `statusLine` command. Prints the in-app status line, writes `~/.cache/claude-tmux/quota` (`quota-<account>` for other accounts), and records which account each tmux pane (or background session) runs | `openspec/specs/quota-reporting` |
| `bin/tmux-claude-widget` | Renders one badge (`session` or `week`) from those files | `openspec/specs/quota-badge` |
| `bin/tmux-claude-menu` | tmux menu for pinning an account and toggling auto-detection | `openspec/specs/quota-account-menu` |
| `bin/tmux-two-row-status` | Splits the tmux status into two rows so the session badge gets the top-right | `openspec/specs/two-row-status` |
| `tmux/claude-tmux.conf` | The tmux.conf block that places the badges and binds the menu | — |

Quotas are per account, so any running Claude session is an equally good reporter. The badge needs no running session and no polling daemon: a window whose reset time has passed is shown as `0%`.

## Several accounts

Each `CLAUDE_CONFIG_DIR` is its own account: `~/.claude` (or unset) is `personal`, `~/.claude-<name>` is `<name>`, any other directory is named after its basename.

The badges show one account at a time:

1. **Auto-detected**: when the active pane runs Claude (directly, or a background session via `claude attach`), its account. Drawn *inverted* (near-black, a faint gauge shadow, text in the fill colour) when it isn't the pinned account.
2. **Pinned**: otherwise, the pinned account, in the normal style.

`prefix + Q` opens a menu listing the accounts that have reported: pick one to pin it, `Unpin`, or toggle `Auto-detect`. The same choices are plain tmux options:

| Option | Values | Default |
|--------|--------|---------|
| `@claude-quota-pin` | an account name | `personal` |
| `@claude-quota-auto` | `on` / `off` | `on` |
| `@claude-quota-scheme-<account>` | `orange` `yellow` `green` `cyan` `pink`, or `#base,#fill` | `orange` |
| `@claude-quota-icon-<account>` | a glyph replacing the logo | U+F0674 |

Schemes and icons tell accounts apart; the style tells whether the account is pinned or detected. Alarm colours (`≥ 90%` session, `≥ 80%` week) override any scheme.

## Install

```bash
git clone https://github.com/apexJCL/claude-tmux.git
cd claude-tmux
./install.sh            # symlinks bin/* into ~/.local/bin (or pass another directory)
```

Then:

- Claude Code `settings.json`: `"statusLine": {"type": "command", "command": "~/.local/bin/claude-tmux-status", "padding": 0}`. If you already have a status line command, `claude-tmux-status` replaces it: it prints its own line (account, model, directory, context use, cost) after recording the quota.
- `~/.tmux.conf`: the block in `tmux/claude-tmux.conf`. If you use a plugin that builds `status-right` (e.g. [tmux2k](https://github.com/2KAbhishek/tmux2k)), put it after tpm's `run` line.

Requires bash 4.2+, `jq`, tmux 3.2+, a Nerd Font (3.4 is enough), and a Claude Code subscription (Pro/Max): API-key sessions carry no rate limits, so nothing is recorded.

### Without tmux2k

The block assumes tmux2k's look; adjust to taste:

- The second argument to `tmux-claude-widget` is the background colour its leading powerline separator butts against (`'#80FFEA'` is tmux2k's clock segment, `'#0B0D0F'` the bar). Set it to whatever sits left of the badge in your bar.
- `tmux-two-row-status` is optional. It moves the window list and the session badge onto a row of their own; without it, put both badges in `status-right` instead:

  ```tmux
  set -ga status-right "#(~/.local/bin/tmux-claude-widget session default '#{pane_id}' '#{@claude-quota-pin}' '#{@claude-quota-auto}' '#{pane_pid}')"
  set -ga status-right "#(~/.local/bin/tmux-claude-widget week default '#{pane_id}' '#{@claude-quota-pin}' '#{@claude-quota-auto}' '#{pane_pid}')"
  ```

### Other consumers

The state files are plain text, so anything can read them (a menu-bar app, a prompt segment): `~/.cache/claude-tmux/quota[-<account>]` holds `<5h used %> <5h resets epoch> <week used %> <week resets epoch> <written epoch>`, with `-1 0` for the 5h pair on accounts without that window.

## Test

```bash
tests/run.sh
```

Runs each spec scenario against `bin/` in a throwaway `$HOME` and an isolated tmux server. `tests/stub/date` pins "now".

## Changes

Behaviour is specified in `openspec/specs/`. Propose a change with `/opsx:propose`, then implement it with `/opsx:apply` and archive it with `/opsx:archive`.
