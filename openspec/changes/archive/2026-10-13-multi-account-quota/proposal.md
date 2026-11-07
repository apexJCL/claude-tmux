## Why

Quotas are per account, and this setup already runs more than one account (`~/.claude` and `~/.claude-work`). The reporter records the work account's quota to `quota-work`, but the badge only ever reads `quota`. That means the work account's usage is never shown, even when the focused pane is a work session. The user needs to see either the account they chose or the account they are currently using, and to tell at a glance which of the two the badge is showing.

## What Changes

- **Any number of accounts.** The reporter derives the account name from `CLAUDE_CONFIG_DIR` (`~/.claude-<name>` → `<name>`) instead of recognising only `work`. Existing state file names are unchanged: `quota` for `personal`, `quota-<name>` for the others.
- **Pane attribution.** When Claude runs inside tmux, the reporter also records which account the pane (`$TMUX_PANE`) belongs to, together with the PID of the Claude process. This tells the badge what the focused pane is running without inspecting other processes' environments.
- **Pinned account.** The tmux option `@claude-quota-pin` names the account to show by default. Unset means `personal`, which is today's behaviour.
- **Auto-detection.** When `@claude-quota-auto` is on (the default) and the active pane is running a live Claude session, the badge shows that session's account. This overrides the pin. When the pane is not running Claude, the badge falls back to the pinned account.
- **Inverted style for auto-detected accounts.** The pinned account keeps today's look. An auto-detected account that differs from the pin is drawn inverted: near-black background, a barely visible dark gauge shadow, and text in the scheme's strong fill colour.
- **Per-account appearance.** Each account can have its own colour scheme (a built-in preset or a custom `base,fill` pair) and its own logo glyph, set through tmux options. This shows *which* account is on screen, while the style shows *why* it is shown.
- **Account menu.** A new `bin/tmux-claude-menu` opens a tmux `display-menu` (bound to `prefix + Q` in the shipped conf). It lists the accounts that have reported, and offers unpin and an auto-detection toggle.
- **BREAKING (badge CLI):** `tmux-claude-widget` takes three more positional arguments, `<pane_id> <pin> <auto>`. They are filled from tmux formats in `tmux/claude-tmux.conf`. If they are omitted, the badge behaves as today, apart from honouring the personal account's appearance options.

## Capabilities

### New Capabilities
- `quota-account-menu`: the tmux menu and options for choosing the pinned account and toggling auto-detection.

### Modified Capabilities
- `quota-reporting`: account naming generalises beyond `work`, and the reporter gains pane attribution.
- `quota-badge`: the state source becomes account-resolved (pin vs auto-detected). The badge gains the inverted style and per-account colour schemes and logos. The "work account is not displayed" rule is removed.

## Impact

- `bin/claude-tmux-status`: account naming and pane attribution files under `~/.cache/claude-tmux/panes/`.
- `bin/tmux-claude-widget`: new arguments, account resolution, appearance options read from tmux, inverted palette.
- `bin/tmux-claude-menu`: new script. `install.sh` already symlinks every file in `bin/*`.
- `tmux/claude-tmux.conf`: widget invocations pass `#{pane_id}`, `#{@claude-quota-pin}`, `#{@claude-quota-auto}`; adds the menu key binding and option defaults.
- `tests/run.sh`: new checks for every new scenario; the badge tests that need tmux options use the isolated tmux server.
- `README.md`: documents the options, the presets and the menu.
- No new dependencies. The reporter uses `ps` to find the Claude process; it is available on macOS and Linux.
